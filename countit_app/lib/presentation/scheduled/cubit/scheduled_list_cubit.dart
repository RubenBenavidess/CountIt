import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../app/errors/app_failure.dart';
import '../../../data/dtos/scheduled_transaction.dart';
import '../../../data/repositories/scheduled_transaction_repository.dart';
import '../../../shared/state/load_state.dart';

/// Running rules first (soonest next run first), paused ones after them.
List<ScheduledTransaction> sortRules(Iterable<ScheduledTransaction> rules) {
  final sorted = rules.toList();
  sorted.sort((a, b) {
    if (a.isPaused != b.isPaused) return a.isPaused ? 1 : -1;
    final byDate = (a.nextRunDate ?? DateTime(9999)).compareTo(b.nextRunDate ?? DateTime(9999));
    return byDate != 0 ? byDate : a.scheduledTransactionId.compareTo(b.scheduledTransactionId);
  });
  return List.unmodifiable(sorted);
}

class ScheduledListState extends Equatable {
  const ScheduledListState({this.rules = const LoadState.initial(), this.usage});

  /// The wallet's active rules, [sortRules] order.
  final LoadState<List<ScheduledTransaction>> rules;

  /// The caller's own rules in every wallet (plan quota); null while unknown
  /// or when it could not be loaded (the backend still enforces the quota).
  final ScheduledUsage? usage;

  ScheduledListState copyWith({LoadState<List<ScheduledTransaction>>? rules, ScheduledUsage? usage}) =>
      ScheduledListState(rules: rules ?? this.rules, usage: usage ?? this.usage);

  @override
  List<Object?> get props => [rules, usage];
}

/// HU-16/HU-20: the scheduled rules of one wallet (COU-88, COU-156) and how
/// much of the plan quota the caller already uses.
///
/// Like the other lists, [load] keeps what is on screen while reloading and
/// after a failure.
class ScheduledListCubit extends Cubit<ScheduledListState> {
  ScheduledListCubit(this._scheduled, {required this.walletId, required this.userId})
    : super(const ScheduledListState());

  final ScheduledTransactionRepository _scheduled;
  final int walletId;

  /// The signed-in user (quota owner); null skips the usage query.
  final String? userId;
  Future<void>? _inFlight;

  /// Loads (or reloads) the list and the usage; concurrent calls share one request.
  Future<void> load() => _inFlight ??= _load().whenComplete(() => _inFlight = null);

  Future<void> _load() async {
    emit(state.copyWith(rules: state.rules.reloading()));
    final usage = _usage();
    try {
      final rules = await _scheduled.listByWallet(walletId);
      if (isClosed) return;
      emit(ScheduledListState(rules: LoadState.success(sortRules(rules)), usage: await usage ?? state.usage));
    } on AppFailure catch (failure) {
      await usage;
      if (!isClosed) emit(state.copyWith(rules: LoadState.failure(failure, previous: state.rules.data)));
    }
  }

  /// Never fails the screen: without it the create button just skips the
  /// local quota check.
  Future<ScheduledUsage?> _usage() async {
    final id = userId;
    if (id == null) return null;
    try {
      return await _scheduled.usageOf(id);
    } on AppFailure {
      return null;
    }
  }
}
