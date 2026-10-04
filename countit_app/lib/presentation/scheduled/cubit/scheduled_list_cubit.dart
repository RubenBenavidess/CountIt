import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../app/errors/app_failure.dart';
import '../../../data/dtos/scheduled_transaction.dart';
import '../../../data/repositories/scheduled_transaction_repository.dart';
import '../../../shared/state/delete_cubit.dart';
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

/// What a pause or resume did, for a one-off message (snackbar, plans sheet).
enum ScheduledToggleOutcome { paused, resumed, ended, missing, failed }

class ScheduledToggleResult extends Equatable {
  const ScheduledToggleResult(this.seq, this.outcome, {required this.name, this.failure});

  /// Grows with every result, so two equal outcomes in a row still notify.
  final int seq;
  final ScheduledToggleOutcome outcome;
  final String name;

  /// Set with [ScheduledToggleOutcome.failed] (a 409 quota opens the plans).
  final AppFailure? failure;

  @override
  List<Object?> get props => [seq, outcome, name, failure];
}

class ScheduledListState extends Equatable {
  const ScheduledListState({
    this.rules = const LoadState.initial(),
    this.usage,
    this.toggling = const {},
    this.lastToggle,
  });

  /// The wallet's active rules, [sortRules] order.
  final LoadState<List<ScheduledTransaction>> rules;

  /// The caller's own rules in every wallet (plan quota); null while unknown
  /// or when it could not be loaded (the backend still enforces the quota).
  final ScheduledUsage? usage;

  /// Rules whose pause or resume is on its way (their switch is disabled).
  final Set<int> toggling;

  final ScheduledToggleResult? lastToggle;

  ScheduledListState copyWith({
    LoadState<List<ScheduledTransaction>>? rules,
    ScheduledUsage? usage,
    Set<int>? toggling,
    ScheduledToggleResult? lastToggle,
  }) => ScheduledListState(
    rules: rules ?? this.rules,
    usage: usage ?? this.usage,
    toggling: toggling ?? this.toggling,
    lastToggle: lastToggle ?? this.lastToggle,
  );

  @override
  List<Object?> get props => [rules, usage, toggling, lastToggle];
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
      final fresh = await usage;
      if (isClosed) return;
      emit(state.copyWith(rules: LoadState.success(sortRules(rules)), usage: fresh));
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

  /// HU-20 (COU-153): pauses a running rule or resumes a paused one. The
  /// API skips the paused period, may end a rule with nothing left to run
  /// and answers 409 when resuming finds no free slot in the plan.
  Future<void> togglePause(ScheduledTransaction rule) async {
    final id = rule.scheduledTransactionId;
    if (state.toggling.contains(id)) return;
    final pause = !rule.isPaused;
    emit(state.copyWith(toggling: {...state.toggling, id}));
    try {
      final fresh = await _scheduled.setPaused(id, paused: pause);
      if (isClosed) return;
      final ended = !fresh.isActive;
      _finish(
        id,
        ended ? ScheduledToggleOutcome.ended : (pause ? ScheduledToggleOutcome.paused : ScheduledToggleOutcome.resumed),
        rule.name,
        replace: ended ? null : rule.mergeRule(fresh),
        usage: _usageAfter(rule, pausedNow: fresh.isPaused, ended: ended),
      );
    } on AppFailure catch (failure) {
      if (isClosed) return;
      if (failure.kind == FailureKind.notFound) {
        // Ended or deleted elsewhere: it leaves the list.
        _finish(id, ScheduledToggleOutcome.missing, rule.name, usage: _usageAfter(rule, ended: true));
      } else {
        _finish(id, ScheduledToggleOutcome.failed, rule.name, keep: true, failure: failure);
      }
    }
  }

  /// The caller's usage after toggling one of their own rules (no new query).
  ScheduledUsage? _usageAfter(ScheduledTransaction rule, {bool? pausedNow, bool ended = false}) {
    final usage = state.usage;
    if (usage == null || rule.userId == null || rule.userId != userId) return usage;
    final wasRunning = !rule.isPaused;
    final total = usage.total - (ended ? 1 : 0);
    var running = usage.running - (wasRunning ? 1 : 0);
    if (!ended && pausedNow == false) running += 1;
    return ScheduledUsage(total: total, running: running);
  }

  void _finish(
    int id,
    ScheduledToggleOutcome outcome,
    String name, {
    ScheduledTransaction? replace,
    bool keep = false,
    ScheduledUsage? usage,
    AppFailure? failure,
  }) {
    final current = state.rules.data ?? const <ScheduledTransaction>[];
    final rules = keep
        ? current
        : sortRules([
            for (final r in current)
              if (r.scheduledTransactionId != id) r else ?replace,
          ]);
    final toggling = {...state.toggling}..remove(id);
    emit(
      ScheduledListState(
        rules: keep ? state.rules : LoadState.success(rules),
        usage: usage ?? state.usage,
        toggling: toggling,
        lastToggle: ScheduledToggleResult((state.lastToggle?.seq ?? 0) + 1, outcome, name: name, failure: failure),
      ),
    );
  }
}

/// HU-20: `delete_scheduled_transaction` 🔒 from the edit screen (COU-154).
/// The transactions it already generated are kept.
class ScheduledDeleteCubit extends DeleteCubit {
  ScheduledDeleteCubit(ScheduledTransactionRepository scheduled, {required int scheduledTransactionId})
    : super(({onReauth}) => scheduled.delete(scheduledTransactionId, onReauth: onReauth));
}
