import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../app/errors/app_failure.dart';
import '../../../data/dtos/admin.dart';
import '../../../data/repositories/admin_repository.dart';

enum AdminListStatus { initial, loading, success, failure }

class AdminUsersState extends Equatable {
  const AdminUsersState({
    this.status = AdminListStatus.initial,
    this.items = const [],
    this.hasMore = false,
    this.loadingMore = false,
    this.failure,
    this.moreFailure,
    this.search = '',
  });

  final AdminListStatus status;
  final List<AdminUser> items;
  final bool hasMore;
  final bool loadingMore;

  /// Error of the first page.
  final AppFailure? failure;

  /// Error of the last «load more» (retry row at the end).
  final AppFailure? moreFailure;

  /// The term the shown rows answer to.
  final String search;

  bool get isFirstLoad => status != AdminListStatus.success && items.isEmpty;

  AdminUsersState copyWith({
    AdminListStatus? status,
    List<AdminUser>? items,
    bool? hasMore,
    bool? loadingMore,
    AppFailure? Function()? failure,
    AppFailure? Function()? moreFailure,
    String? search,
  }) => AdminUsersState(
    status: status ?? this.status,
    items: items ?? this.items,
    hasMore: hasMore ?? this.hasMore,
    loadingMore: loadingMore ?? this.loadingMore,
    failure: failure == null ? this.failure : failure(),
    moreFailure: moreFailure == null ? this.moreFailure : moreFailure(),
    search: search ?? this.search,
  );

  @override
  List<Object?> get props => [status, items, hasMore, loadingMore, failure, moreFailure, search];
}

/// Users list for admins (HU-28 · COU-201): search with debounce, offset
/// pages and no stale answers. Every [load] starts a new generation; pages of
/// an older search or a «load more» started before it are dropped.
class AdminUsersCubit extends Cubit<AdminUsersState> {
  AdminUsersCubit(this._admin, {this.debounce = const Duration(milliseconds: 350)}) : super(const AdminUsersState());

  final AdminRepository _admin;
  final Duration debounce;
  Timer? _timer;
  int _generation = 0;

  /// (Re)loads the first page for the current search; rows stay meanwhile.
  Future<void> load() async {
    _timer?.cancel();
    final generation = ++_generation;
    final search = state.search;
    emit(
      state.copyWith(status: AdminListStatus.loading, loadingMore: false, failure: () => null, moreFailure: () => null),
    );
    try {
      final page = await _admin.listUsers(search: search);
      if (_isStale(generation)) return;
      emit(state.copyWith(status: AdminListStatus.success, items: page.items, hasMore: page.hasMore));
    } on AppFailure catch (failure) {
      if (_isStale(generation)) return;
      emit(state.copyWith(status: AdminListStatus.failure, failure: () => failure));
    }
  }

  /// Called on every keystroke; the request goes out after [debounce]. The
  /// rows of the previous term are cleared at once (they would not match).
  void search(String term) {
    final trimmed = term.trim();
    if (trimmed == state.search) return;
    _timer?.cancel();
    ++_generation; // drops any answer still on its way for the old term
    emit(AdminUsersState(status: AdminListStatus.loading, search: trimmed));
    _timer = Timer(debounce, () => unawaited(load()));
  }

  /// Appends the next page; ignored while loading or at the end. After a
  /// failure only an explicit [retry] tries again.
  Future<void> loadMore({bool retry = false}) async {
    if (!state.hasMore || state.loadingMore || state.status != AdminListStatus.success) return;
    if (state.moreFailure != null && !retry) return;
    final generation = _generation;
    emit(state.copyWith(loadingMore: true, moreFailure: () => null));
    try {
      final page = await _admin.listUsers(search: state.search, offset: state.items.length);
      if (_isStale(generation)) return;
      // Offsets may overlap when users are created meanwhile: keep each id once.
      final known = {for (final user in state.items) user.userId};
      emit(
        state.copyWith(
          items: [...state.items, ...page.items.where((user) => !known.contains(user.userId))],
          hasMore: page.hasMore,
          loadingMore: false,
        ),
      );
    } on AppFailure catch (failure) {
      if (_isStale(generation)) return;
      emit(state.copyWith(loadingMore: false, moreFailure: () => failure));
    }
  }

  /// A user changed in the detail screen (plan or role): updated in place.
  void replace(AdminUser user) {
    final index = state.items.indexWhere((u) => u.userId == user.userId);
    if (index < 0 || state.items[index] == user) return;
    emit(state.copyWith(items: [...state.items]..[index] = user));
  }

  bool _isStale(int generation) => isClosed || generation != _generation;

  @override
  Future<void> close() {
    _timer?.cancel();
    return super.close();
  }
}
