import 'dart:async';
import 'dart:math' as math;

import 'package:clock/clock.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../app/errors/app_failure.dart';
import '../../../data/dtos/notification.dart';
import '../../../data/dtos/paged.dart';
import '../../../data/repositories/notification_repository.dart';

enum InboxStatus { initial, loading, success, failure }

/// A failed «mark as read»: [seq] grows with every one, so two equal
/// failures in a row still show their message.
class InboxActionFailure extends Equatable {
  const InboxActionFailure(this.seq, this.failure);

  final int seq;
  final AppFailure failure;

  @override
  List<Object?> get props => [seq, failure];
}

class NotificationsState extends Equatable {
  const NotificationsState({
    this.status = InboxStatus.initial,
    this.items = const [],
    this.hasMore = false,
    this.loadingMore = false,
    this.failure,
    this.moreFailure,
    this.unread = 0,
    this.markingAll = false,
    this.actionFailure,
  });

  final InboxStatus status;

  /// Every page loaded so far, newest first.
  final List<AppNotification> items;
  final bool hasMore;

  /// A next page is on its way (spinner at the end of the list).
  final bool loadingMore;

  /// Error of the first page (with [items] kept from a previous load, if any).
  final AppFailure? failure;

  /// Error of the last «load more» (retry row at the end of the list).
  final AppFailure? moreFailure;

  /// Unread notifications on the server (capped, see [NotificationRepository.unreadCap]).
  final int unread;

  /// «Marcar todas como leídas» in flight.
  final bool markingAll;
  final InboxActionFailure? actionFailure;

  /// Nothing loaded yet: the first load is running or failed.
  bool get isFirstLoad => status != InboxStatus.success && items.isEmpty;

  /// Text of the badge: null when there is nothing unread.
  String? get badgeLabel => unread <= 0 ? null : (unread > 99 ? '99+' : '$unread');

  NotificationsState copyWith({
    InboxStatus? status,
    List<AppNotification>? items,
    bool? hasMore,
    bool? loadingMore,
    AppFailure? Function()? failure,
    AppFailure? Function()? moreFailure,
    int? unread,
    bool? markingAll,
    InboxActionFailure? actionFailure,
  }) => NotificationsState(
    status: status ?? this.status,
    items: items ?? this.items,
    hasMore: hasMore ?? this.hasMore,
    loadingMore: loadingMore ?? this.loadingMore,
    failure: failure == null ? this.failure : failure(),
    moreFailure: moreFailure == null ? this.moreFailure : moreFailure(),
    unread: unread ?? this.unread,
    markingAll: markingAll ?? this.markingAll,
    actionFailure: actionFailure ?? this.actionFailure,
  );

  @override
  List<Object?> get props => [
    status,
    items,
    hasMore,
    loadingMore,
    failure,
    moreFailure,
    unread,
    markingAll,
    actionFailure,
  ];
}

/// HU-31 (COU-108, COU-111, COU-181): the signed-in user's inbox, its unread
/// badge and «mark as read».
///
/// One instance lives for the whole app; [setUser] follows the session:
/// signing out forgets every notification, so nothing leaks to the next
/// account. Every load starts a new generation: answers of a previous user
/// or of an older load are dropped.
class NotificationsCubit extends Cubit<NotificationsState> {
  NotificationsCubit(this._notifications) : super(const NotificationsState());

  final NotificationRepository _notifications;

  String? _userId;
  int _generation = 0;
  Future<void>? _inFlight;
  bool _again = false;

  /// Ids whose «mark as read» is on its way (a double tap sends one call).
  final Set<int> _marking = {};

  String? get userId => _userId;

  /// Starts following [userId]'s notifications, or stops with null.
  Future<void> setUser(String? userId) async {
    if (userId == _userId) return;
    _userId = userId;
    _generation++;
    _inFlight = null;
    _again = false;
    _marking.clear();
    if (isClosed) return;
    emit(const NotificationsState());
    if (userId != null) await load();
  }

  /// Loads (or reloads) the newest page and the unread count. A call during
  /// a load runs once more after it, so bursts of changes cost two requests.
  Future<void> load() {
    if (_userId == null) return Future.value();
    final current = _inFlight;
    if (current != null) {
      _again = true;
      return current;
    }
    final generation = _generation;
    late final Future<void> run;
    run = _loadLoop(generation).whenComplete(() {
      if (identical(_inFlight, run)) _inFlight = null;
    });
    return _inFlight = run;
  }

  Future<void> _loadLoop(int generation) async {
    do {
      _again = false;
      await _load(generation);
    } while (_again && !_isStale(generation));
  }

  Future<void> _load(int generation) async {
    emit(state.copyWith(status: InboxStatus.loading, failure: () => null));
    try {
      // Both requests at once; Future.wait reports the first failure.
      final results = await Future.wait<Object>([_notifications.inbox(), _notifications.unreadCount()]);
      if (_isStale(generation)) return;
      final page = results[0] as Paged<AppNotification>;
      final unread = results[1] as int;
      // Older pages already loaded stay below the new head: a live change
      // does not throw away what the user scrolled to.
      final head = page.items;
      final keepOlder = page.hasMore && head.isNotEmpty && state.items.length > head.length;
      final items = keepOlder ? [...head, ...state.items.where((n) => n.id < head.last.id)] : head;
      emit(
        state.copyWith(
          status: InboxStatus.success,
          items: List.unmodifiable(items),
          hasMore: keepOlder ? state.hasMore : page.hasMore,
          moreFailure: keepOlder ? null : () => null,
          unread: unread,
        ),
      );
    } on AppFailure catch (failure) {
      if (_isStale(generation)) return;
      emit(state.copyWith(status: InboxStatus.failure, failure: () => failure));
    }
  }

  /// Appends the next page; ignored while loading or at the end. After a
  /// failure only an explicit [retry] tries again.
  Future<void> loadMore({bool retry = false}) async {
    if (!state.hasMore || state.loadingMore || state.status != InboxStatus.success || state.items.isEmpty) return;
    if (state.moreFailure != null && !retry) return;
    final generation = _generation;
    emit(state.copyWith(loadingMore: true, moreFailure: () => null));
    try {
      final page = await _notifications.inbox(before: state.items.last.id);
      if (_isStale(generation)) return;
      final known = {for (final n in state.items) n.id};
      emit(
        state.copyWith(
          items: List.unmodifiable([...state.items, ...page.items.where((n) => !known.contains(n.id))]),
          hasMore: page.hasMore,
          loadingMore: false,
        ),
      );
    } on AppFailure catch (failure) {
      if (_isStale(generation)) return;
      emit(state.copyWith(loadingMore: false, moreFailure: () => failure));
    }
  }

  /// Marks one notification as read (opening it does too). The list and the
  /// badge change at once; a failure puts them back and explains itself.
  Future<void> markRead(AppNotification notification) async {
    final id = notification.id;
    final current = _find(id);
    if (current == null || current.isRead || _marking.contains(id)) return;
    final generation = _generation;
    _marking.add(id);
    _replace(id, (n) => n.withReadAt(clock.now()), unread: math.max(0, state.unread - 1));
    try {
      await _notifications.markRead([id]);
    } on AppFailure catch (failure) {
      if (_isStale(generation)) return;
      final still = _find(id)?.isRead ?? false;
      _replace(id, (n) => n.withReadAt(null), unread: still ? state.unread + 1 : state.unread, failure: failure);
    } finally {
      _marking.remove(id);
    }
  }

  /// «Marcar todas como leídas»: every unread notification, also the ones
  /// in pages not loaded yet.
  Future<void> markAllRead() async {
    if (state.markingAll || (state.unread == 0 && state.items.every((n) => n.isRead))) return;
    final generation = _generation;
    final before = state;
    final now = clock.now();
    emit(
      state.copyWith(
        markingAll: true,
        unread: 0,
        items: List.unmodifiable([for (final n in state.items) n.isRead ? n : n.withReadAt(now)]),
      ),
    );
    try {
      await _notifications.markAllRead();
      if (!_isStale(generation)) emit(state.copyWith(markingAll: false));
    } on AppFailure catch (failure) {
      if (_isStale(generation)) return;
      emit(
        state.copyWith(markingAll: false, unread: before.unread, items: before.items, actionFailure: _failure(failure)),
      );
    }
  }

  AppNotification? _find(int id) {
    for (final n in state.items) {
      if (n.id == id) return n;
    }
    return null;
  }

  void _replace(int id, AppNotification Function(AppNotification) change, {required int unread, AppFailure? failure}) {
    emit(
      state.copyWith(
        items: List.unmodifiable([for (final n in state.items) n.id == id ? change(n) : n]),
        unread: unread,
        actionFailure: failure == null ? null : _failure(failure),
      ),
    );
  }

  InboxActionFailure _failure(AppFailure failure) => InboxActionFailure((state.actionFailure?.seq ?? 0) + 1, failure);

  bool _isStale(int generation) => isClosed || generation != _generation;
}
