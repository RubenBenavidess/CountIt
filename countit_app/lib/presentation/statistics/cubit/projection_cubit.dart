import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../app/errors/app_failure.dart';
import '../../../data/dtos/projection.dart';
import '../../../data/repositories/analysis_repository.dart';
import '../../../shared/state/load_state.dart';

class ProjectionState extends Equatable {
  const ProjectionState({this.until, this.projection = const LoadState.initial(), this.locked = false});

  /// Date chosen by the user; null lets the API pick (last occurrence of
  /// the rules, at most a year, or 30 days without rules).
  final DateTime? until;
  final LoadState<WalletProjection> projection;

  /// The plan has no `wallet_projection` (known locally or answered 403
  /// `feature_not_in_plan` by the API): the screen offers the plans.
  final bool locked;

  ProjectionState copyWith({
    DateTime? until,
    bool clearUntil = false,
    LoadState<WalletProjection>? projection,
    bool? locked,
  }) => ProjectionState(
    until: clearUntil ? null : (until ?? this.until),
    projection: projection ?? this.projection,
    locked: locked ?? this.locked,
  );

  @override
  List<Object?> get props => [until, projection, locked];
}

/// HU-25 (COU-99, COU-172): projected balance of one wallet.
///
/// [allowed] is the local gating hint (`Profile.allows`): when the known
/// plan lacks the feature no request is made. The API still decides: a 403
/// `feature_not_in_plan` locks the screen too (e.g. the plan just expired).
/// Answers are memoised per date for the life of the screen.
class ProjectionCubit extends Cubit<ProjectionState> {
  ProjectionCubit(this._analysis, {required this.walletId, required bool allowed})
    : super(ProjectionState(locked: !allowed));

  final AnalysisRepository _analysis;
  final int walletId;
  final _cache = <DateTime?, WalletProjection>{};
  final _inFlight = <DateTime?, Future<void>>{};

  Future<void> load() => _show(state);

  /// [until] null goes back to the automatic horizon.
  Future<void> selectUntil(DateTime? until) =>
      until == state.until ? Future.value() : _show(state.copyWith(until: until, clearUntil: until == null));

  /// Asks the API again for the date on screen (keeps it visible meanwhile).
  Future<void> refresh() {
    _cache.remove(state.until);
    return _show(state, refreshing: true);
  }

  Future<void> _show(ProjectionState next, {bool refreshing = false}) {
    if (next.locked) {
      emit(next);
      return Future.value();
    }
    final key = next.until;
    final cached = _cache[key];
    if (cached != null) {
      emit(next.copyWith(projection: LoadState.success(cached)));
      return Future.value();
    }
    final keep = refreshing && next.projection.data != null;
    emit(next.copyWith(projection: keep ? next.projection.reloading() : const LoadState.loading()));
    // A block body: `remove` returns this very future and whenComplete would wait for itself.
    return _inFlight[key] ??= _fetch(key).whenComplete(() {
      _inFlight.remove(key);
    });
  }

  Future<void> _fetch(DateTime? until) async {
    try {
      final projection = await _analysis.walletProjection(walletId, until: until);
      _cache[until] = projection;
      if (!isClosed && state.until == until) emit(state.copyWith(projection: LoadState.success(projection)));
    } on AppFailure catch (failure) {
      if (isClosed) return;
      if (failure.kind == FailureKind.featureNotInPlan) {
        emit(state.copyWith(locked: true, projection: const LoadState.initial()));
        return;
      }
      if (state.until != until) return;
      emit(state.copyWith(projection: LoadState.failure(failure, previous: state.projection.data)));
    }
  }
}
