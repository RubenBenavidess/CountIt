import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../app/errors/app_failure.dart';
import '../../../data/dtos/statistics.dart';
import '../../../data/dtos/wallet.dart';
import '../../../data/repositories/analysis_repository.dart';
import '../../../data/repositories/wallet_repository.dart';
import '../../../shared/state/load_state.dart';

class StatisticsState extends Equatable {
  const StatisticsState({
    required this.walletId,
    this.range = StatisticsRange.days30,
    this.wallets = const LoadState.initial(),
    this.statistics = const LoadState.initial(),
  });

  /// The wallet on screen.
  final int walletId;
  final StatisticsRange range;

  /// Wallets the selector offers (own and shared, as the home lists them).
  final LoadState<List<Wallet>> wallets;

  /// Statistics of [walletId] for [range]; while another pair loads there
  /// is no data (a chart of the previous range would mislead).
  final LoadState<WalletStatistics> statistics;

  /// The selected wallet when the list knows it.
  Wallet? get wallet {
    for (final wallet in wallets.data ?? const <Wallet>[]) {
      if (wallet.walletId == walletId) return wallet;
    }
    return null;
  }

  StatisticsState copyWith({
    int? walletId,
    StatisticsRange? range,
    LoadState<List<Wallet>>? wallets,
    LoadState<WalletStatistics>? statistics,
  }) => StatisticsState(
    walletId: walletId ?? this.walletId,
    range: range ?? this.range,
    wallets: wallets ?? this.wallets,
    statistics: statistics ?? this.statistics,
  );

  @override
  List<Object?> get props => [walletId, range, wallets, statistics];
}

/// HU-26 (COU-93, COU-173): statistics of one wallet with a wallet and range
/// selector.
///
/// Answers are memoised per (wallet, range) for the life of the screen, so
/// going back to a range already seen is instant and costs no request;
/// [refresh] (pull-to-refresh, «Reintentar») asks the API again. An answer
/// that arrives after the user moved to another pair is cached but not shown.
class StatisticsCubit extends Cubit<StatisticsState> {
  StatisticsCubit(
    this._analysis,
    this._wallets, {
    required int walletId,
    StatisticsRange range = StatisticsRange.days30,
    Wallet? initial,
  }) : super(
         StatisticsState(
           walletId: walletId,
           range: range,
           // The wallet the detail screen passed names the selector at once.
           wallets: initial == null ? const LoadState.initial() : LoadState.loading(previous: [initial]),
         ),
       );

  final AnalysisRepository _analysis;
  final WalletRepository _wallets;
  final _cache = <(int, StatisticsRange), WalletStatistics>{};
  final _inFlight = <(int, StatisticsRange), Future<void>>{};

  /// First load: the wallets of the selector and the statistics, together.
  Future<void> start() => Future.wait([loadWallets(), _show(state)]);

  /// The selector never blocks the screen: on failure it keeps offering the
  /// wallet it already knows.
  Future<void> loadWallets() async {
    emit(state.copyWith(wallets: state.wallets.reloading()));
    try {
      final wallets = await _wallets.list();
      if (!isClosed) emit(state.copyWith(wallets: LoadState.success(wallets)));
    } on AppFailure catch (failure) {
      if (!isClosed) emit(state.copyWith(wallets: LoadState.failure(failure, previous: state.wallets.data)));
    }
  }

  Future<void> selectWallet(int walletId) =>
      walletId == state.walletId ? Future.value() : _show(state.copyWith(walletId: walletId));

  Future<void> selectRange(StatisticsRange range) =>
      range == state.range ? Future.value() : _show(state.copyWith(range: range));

  /// Asks the API again for the pair on screen (keeps it visible meanwhile).
  Future<void> refresh() {
    _cache.remove((state.walletId, state.range));
    return _show(state, refreshing: true);
  }

  /// Emits [next] (the new selection) together with its statistics state in
  /// one go, so no frame pairs a range with another range's figures.
  Future<void> _show(StatisticsState next, {bool refreshing = false}) {
    final key = (next.walletId, next.range);
    final cached = _cache[key];
    if (cached != null) {
      emit(next.copyWith(statistics: LoadState.success(cached)));
      return Future.value();
    }
    final current = next.statistics.data;
    final keep = refreshing && current != null && current.walletId == key.$1 && current.range == key.$2;
    emit(next.copyWith(statistics: keep ? next.statistics.reloading() : const LoadState.loading()));
    // A block body: `remove` returns this very future and whenComplete would wait for itself.
    return _inFlight[key] ??= _fetch(key).whenComplete(() {
      _inFlight.remove(key);
    });
  }

  Future<void> _fetch((int, StatisticsRange) key) async {
    try {
      final statistics = await _analysis.walletStatistics(key.$1, key.$2);
      _cache[key] = statistics;
      if (!isClosed && _isCurrent(key)) emit(state.copyWith(statistics: LoadState.success(statistics)));
    } on AppFailure catch (failure) {
      if (isClosed || !_isCurrent(key)) return;
      final previous = state.statistics.data;
      emit(
        state.copyWith(
          statistics: LoadState.failure(
            failure,
            previous: previous != null && previous.walletId == key.$1 && previous.range == key.$2 ? previous : null,
          ),
        ),
      );
    }
  }

  bool _isCurrent((int, StatisticsRange) key) => key == (state.walletId, state.range);
}
