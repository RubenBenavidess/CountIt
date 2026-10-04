import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../app/errors/app_failure.dart';
import '../../../data/dtos/admin.dart';
import '../../../data/repositories/admin_repository.dart';
import 'admin_failures.dart';
import 'admin_users_cubit.dart' show AdminListStatus;

class AuditLogState extends Equatable {
  const AuditLogState({
    this.status = AdminListStatus.initial,
    this.items = const [],
    this.hasMore = false,
    this.loadingMore = false,
    this.failure,
    this.moreFailure,
    this.filter = const AuditFilter(),
  });

  final AdminListStatus status;
  final List<AuditEntry> items;
  final bool hasMore;
  final bool loadingMore;
  final AppFailure? failure;
  final AppFailure? moreFailure;
  final AuditFilter filter;

  bool get isFirstLoad => status != AdminListStatus.success && items.isEmpty;

  AuditLogState copyWith({
    AdminListStatus? status,
    List<AuditEntry>? items,
    bool? hasMore,
    bool? loadingMore,
    AppFailure? Function()? failure,
    AppFailure? Function()? moreFailure,
  }) => AuditLogState(
    status: status ?? this.status,
    items: items ?? this.items,
    hasMore: hasMore ?? this.hasMore,
    loadingMore: loadingMore ?? this.loadingMore,
    failure: failure == null ? this.failure : failure(),
    moreFailure: moreFailure == null ? this.moreFailure : moreFailure(),
    filter: filter,
  );

  @override
  List<Object?> get props => [status, items, hasMore, loadingMore, failure, moreFailure, filter];
}

/// Audit trail for the superadmin (HU-28 · COU-208, COU-209): offset pages,
/// filters by entity and entity id, no stale answers (generations).
class AuditLogCubit extends Cubit<AuditLogState> {
  AuditLogCubit(this._admin, {this.debounce = const Duration(milliseconds: 400)}) : super(const AuditLogState());

  final AdminRepository _admin;
  final Duration debounce;
  Timer? _timer;
  int _generation = 0;

  /// Entity ids are text in the API (uuid, number); longer input is a typo.
  static const entityIdMax = 64;

  Future<void> load() async {
    _timer?.cancel();
    final generation = ++_generation;
    emit(
      state.copyWith(status: AdminListStatus.loading, loadingMore: false, failure: () => null, moreFailure: () => null),
    );
    try {
      final page = await _admin.listAuditLog(filter: state.filter);
      if (_isStale(generation)) return;
      emit(state.copyWith(status: AdminListStatus.success, items: page.items, hasMore: page.hasMore));
    } on AppFailure catch (failure) {
      if (_isStale(generation)) return;
      emit(state.copyWith(status: AdminListStatus.failure, failure: () => adminFailure(failure)));
    }
  }

  /// Entity chip: applied at once.
  Future<void> filterByEntity(String? entity) => _apply(AuditFilter(entity: entity, entityId: state.filter.entityId));

  /// Entity id field: debounced while typing; empty clears it.
  void filterByEntityId(String text) {
    final trimmed = text.trim();
    final id = trimmed.isEmpty ? null : trimmed.substring(0, trimmed.length.clamp(0, entityIdMax));
    if (id == state.filter.entityId) return;
    _timer?.cancel();
    _timer = Timer(debounce, () => unawaited(_apply(AuditFilter(entity: state.filter.entity, entityId: id))));
  }

  Future<void> clearFilters() => _apply(const AuditFilter());

  Future<void> _apply(AuditFilter filter) async {
    _timer?.cancel();
    if (filter == state.filter && state.status == AdminListStatus.success) return;
    ++_generation;
    emit(AuditLogState(status: AdminListStatus.loading, filter: filter));
    await load();
  }

  Future<void> loadMore({bool retry = false}) async {
    if (!state.hasMore || state.loadingMore || state.status != AdminListStatus.success) return;
    if (state.moreFailure != null && !retry) return;
    final generation = _generation;
    emit(state.copyWith(loadingMore: true, moreFailure: () => null));
    try {
      final page = await _admin.listAuditLog(filter: state.filter, offset: state.items.length);
      if (_isStale(generation)) return;
      // New entries shift the offsets: keep each id once.
      final known = {for (final entry in state.items) entry.auditId};
      emit(
        state.copyWith(
          items: [...state.items, ...page.items.where((e) => !known.contains(e.auditId))],
          hasMore: page.hasMore,
          loadingMore: false,
        ),
      );
    } on AppFailure catch (failure) {
      if (_isStale(generation)) return;
      emit(state.copyWith(loadingMore: false, moreFailure: () => adminFailure(failure)));
    }
  }

  bool _isStale(int generation) => isClosed || generation != _generation;

  @override
  Future<void> close() {
    _timer?.cancel();
    return super.close();
  }
}
