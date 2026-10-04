import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:countit_app/app/errors/app_failure.dart';
import 'package:countit_app/data/dtos/statistics.dart';
import 'package:countit_app/presentation/statistics/cubit/statistics_cubit.dart';
import 'package:countit_app/shared/state/load_state.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../../helpers/mocks.dart';
import '../../helpers/statistics_fixtures.dart';
import '../../helpers/wallet_fixtures.dart';

const _network = AppFailure(kind: FailureKind.network, message: 'No hay conexión.');

void main() {
  late MockAnalysisRepository analysis;
  late MockWalletRepository wallets;

  final wallet4 = walletFixture(id: 4, name: 'Pichincha');
  final wallet5 = walletFixture(id: 5, name: 'Efectivo');
  final d30 = statisticsFixture(range: StatisticsRange.days30);
  final m3 = statisticsFixture(range: StatisticsRange.months3);
  final other = statisticsFixture(walletId: 5, range: StatisticsRange.days30);

  setUp(() {
    analysis = MockAnalysisRepository();
    wallets = MockWalletRepository();
    when(wallets.list).thenAnswer((_) async => [wallet5, wallet4]);
    when(() => analysis.walletStatistics(4, StatisticsRange.days30)).thenAnswer((_) async => d30);
    when(() => analysis.walletStatistics(4, StatisticsRange.months3)).thenAnswer((_) async => m3);
    when(() => analysis.walletStatistics(5, StatisticsRange.days30)).thenAnswer((_) async => other);
  });

  StatisticsCubit build() => StatisticsCubit(analysis, wallets, walletId: 4, initial: wallet4);

  group('StatisticsCubit (COU-93)', () {
    blocTest<StatisticsCubit, StatisticsState>(
      'start loads the selector and the default 30-day statistics',
      build: build,
      act: (cubit) => cubit.start(),
      verify: (cubit) {
        expect(cubit.state.wallets.data, [wallet5, wallet4]);
        expect(cubit.state.wallet, wallet4);
        expect(cubit.state.statistics, LoadState.success(d30));
      },
    );

    test('the wallet passed by the detail names the selector before the list arrives', () {
      final cubit = build();
      addTearDown(cubit.close);
      expect(cubit.state.wallet, wallet4);
    });

    blocTest<StatisticsCubit, StatisticsState>(
      'a range already seen comes from memory, without a new request',
      build: build,
      act: (cubit) async {
        await cubit.start();
        await cubit.selectRange(StatisticsRange.months3);
        await cubit.selectRange(StatisticsRange.days30);
        await cubit.selectRange(StatisticsRange.months3);
      },
      verify: (cubit) {
        expect(cubit.state.statistics, LoadState.success(m3));
        verify(() => analysis.walletStatistics(4, StatisticsRange.days30)).called(1);
        verify(() => analysis.walletStatistics(4, StatisticsRange.months3)).called(1);
      },
    );

    blocTest<StatisticsCubit, StatisticsState>(
      'changing the range never shows the previous range while loading',
      build: build,
      seed: () => StatisticsState(walletId: 4, statistics: LoadState.success(d30)),
      act: (cubit) => cubit.selectRange(StatisticsRange.months3),
      expect: () => [
        const StatisticsState(walletId: 4, range: StatisticsRange.months3, statistics: LoadState.loading()),
        StatisticsState(walletId: 4, range: StatisticsRange.months3, statistics: LoadState.success(m3)),
      ],
    );

    blocTest<StatisticsCubit, StatisticsState>(
      'another wallet: its own statistics for the same range',
      build: build,
      act: (cubit) async {
        await cubit.start();
        await cubit.selectWallet(5);
      },
      verify: (cubit) {
        expect(cubit.state.walletId, 5);
        expect(cubit.state.wallet, wallet5);
        expect(cubit.state.statistics, LoadState.success(other));
      },
    );

    test('a late answer for a range the user left is cached but not shown', () async {
      final slow = Completer<WalletStatistics>();
      when(() => analysis.walletStatistics(4, StatisticsRange.months3)).thenAnswer((_) => slow.future);
      final cubit = build();
      addTearDown(cubit.close);
      await cubit.start();
      final pending = cubit.selectRange(StatisticsRange.months3);
      await cubit.selectRange(StatisticsRange.days30);
      slow.complete(m3);
      await pending;
      expect(cubit.state.range, StatisticsRange.days30);
      expect(cubit.state.statistics, LoadState.success(d30));
      await cubit.selectRange(StatisticsRange.months3);
      expect(cubit.state.statistics, LoadState.success(m3));
      verify(() => analysis.walletStatistics(4, StatisticsRange.months3)).called(1);
    });

    blocTest<StatisticsCubit, StatisticsState>(
      'refresh asks again and keeps the figures on screen meanwhile',
      build: build,
      seed: () => StatisticsState(walletId: 4, statistics: LoadState.success(d30)),
      act: (cubit) => cubit.refresh(),
      expect: () => [
        StatisticsState(walletId: 4, statistics: LoadState.loading(previous: d30)),
        StatisticsState(walletId: 4, statistics: LoadState.success(d30)),
      ],
    );

    blocTest<StatisticsCubit, StatisticsState>(
      'a failed refresh keeps the figures with the error',
      setUp: () => when(() => analysis.walletStatistics(4, StatisticsRange.days30)).thenThrow(_network),
      build: build,
      seed: () => StatisticsState(walletId: 4, statistics: LoadState.success(d30)),
      act: (cubit) => cubit.refresh(),
      skip: 1,
      expect: () => [StatisticsState(walletId: 4, statistics: LoadState.failure(_network, previous: d30))],
    );

    blocTest<StatisticsCubit, StatisticsState>(
      'a failed first load is an error without data; retry succeeds',
      setUp: () {
        var calls = 0;
        when(() => analysis.walletStatistics(4, StatisticsRange.days30)).thenAnswer((_) async {
          if (calls++ == 0) throw _network;
          return d30;
        });
      },
      build: () => StatisticsCubit(analysis, wallets, walletId: 4),
      act: (cubit) async {
        await cubit.start();
        expect(cubit.state.statistics, const LoadState<WalletStatistics>.failure(_network));
        await cubit.refresh();
      },
      verify: (cubit) => expect(cubit.state.statistics, LoadState.success(d30)),
    );

    blocTest<StatisticsCubit, StatisticsState>(
      'the selector survives a failed wallet list with the wallet it knows',
      setUp: () => when(wallets.list).thenThrow(_network),
      build: build,
      act: (cubit) => cubit.loadWallets(),
      verify: (cubit) {
        expect(cubit.state.wallets.status, LoadStatus.failure);
        expect(cubit.state.wallet, wallet4);
      },
    );
  });

  group('«Estadísticas» tab (no wallet given)', () {
    setUpAll(() => registerFallbackValue(StatisticsRange.days30));

    blocTest<StatisticsCubit, StatisticsState>(
      'starts on the first own wallet once the list arrives',
      setUp: () {
        final shared = walletFixture(id: 9, name: 'De Lucía', isOwner: false);
        when(wallets.list).thenAnswer((_) async => [shared, wallet5, wallet4]);
      },
      build: () => StatisticsCubit(analysis, wallets),
      act: (cubit) => cubit.start(),
      verify: (cubit) {
        expect(cubit.state.walletId, 5);
        expect(cubit.state.statistics, LoadState.success(other));
      },
    );

    blocTest<StatisticsCubit, StatisticsState>(
      'without wallets there is nothing to ask',
      setUp: () => when(wallets.list).thenAnswer((_) async => []),
      build: () => StatisticsCubit(analysis, wallets),
      act: (cubit) => cubit.start(),
      verify: (cubit) {
        expect(cubit.state.walletId, isNull);
        expect(cubit.state.wallets.data, isEmpty);
        verifyNever(() => analysis.walletStatistics(any(), any()));
      },
    );

    blocTest<StatisticsCubit, StatisticsState>(
      'refresh after the list failed tries the whole start again',
      setUp: () {
        var calls = 0;
        when(wallets.list).thenAnswer((_) async => calls++ == 0 ? throw _network : [wallet4]);
      },
      build: () => StatisticsCubit(analysis, wallets),
      act: (cubit) async {
        await cubit.start();
        expect(cubit.state.wallets.failure, _network);
        await cubit.refresh();
      },
      verify: (cubit) => expect(cubit.state.statistics, LoadState.success(d30)),
    );
  });
}
