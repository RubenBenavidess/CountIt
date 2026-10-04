import 'dart:async';

import 'package:countit_app/app/errors/app_failure.dart';
import 'package:countit_app/data/dtos/statistics.dart';
import 'package:countit_app/presentation/statistics/view/statistics_page.dart';
import 'package:countit_app/shared/utils/dates.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../../helpers/mocks.dart';
import '../../helpers/pump_app.dart';
import '../../helpers/statistics_fixtures.dart';
import '../../helpers/wallet_fixtures.dart';

const _network = AppFailure(kind: FailureKind.network, message: 'No hay conexión.');

void main() {
  late MockAnalysisRepository analysis;
  late MockWalletRepository wallets;

  setUpAll(() async {
    await Dates.init();
    registerFallbackValue(StatisticsRange.days30);
  });

  setUp(() {
    analysis = MockAnalysisRepository();
    wallets = MockWalletRepository();
    when(wallets.list)
        .thenAnswer((_) async => [walletFixture(id: 5, name: 'Efectivo'), walletFixture(id: 4, name: 'Pichincha')]);
  });

  Future<void> pumpPage(WidgetTester tester) async {
    tester.view.physicalSize = const Size(420, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpApp(
      StatisticsPage(walletId: 4, initial: walletFixture(id: 4, name: 'Pichincha')),
      wallets: wallets,
      analysis: analysis,
    );
  }

  group('StatisticsPage (COU-93, COU-173)', () {
    testWidgets('loading: announced spinner, selectors already usable', (tester) async {
      final pending = Completer<WalletStatistics>();
      when(() => analysis.walletStatistics(any(), any())).thenAnswer((_) => pending.future);
      await pumpPage(tester);
      expect(find.bySemanticsLabel('Cargando estadísticas'), findsOneWidget);
      expect(find.text('Pichincha'), findsOneWidget);
      expect(find.text('30 días'), findsOneWidget);
      pending.complete(statisticsFixture());
      await tester.pumpAndSettle();
    });

    testWidgets('error: the safe message and «Reintentar» loads again', (tester) async {
      var calls = 0;
      when(() => analysis.walletStatistics(4, StatisticsRange.days30)).thenAnswer((_) async {
        if (calls++ == 0) throw _network;
        return statisticsFixture(range: StatisticsRange.days30);
      });
      await pumpPage(tester);
      await tester.pumpAndSettle();
      expect(find.text('No hay conexión.'), findsOneWidget);
      await tester.tap(find.text('Reintentar'));
      await tester.pumpAndSettle();
      expect(find.text('No hay conexión.'), findsNothing);
      expect(find.text('Balance del periodo'), findsOneWidget);
    });

    testWidgets('empty range: a note instead of zeros, growth still shown', (tester) async {
      when(() => analysis.walletStatistics(4, StatisticsRange.days30))
          .thenAnswer((_) async => statisticsFixture(range: StatisticsRange.days30, empty: true));
      await pumpPage(tester);
      await tester.pumpAndSettle();
      expect(find.textContaining('Sin movimientos en este periodo'), findsOneWidget);
      expect(find.text('Balance del periodo'), findsNothing);
      expect(find.text('ESTE MES VS. EL ANTERIOR'), findsOneWidget);
      expect(find.text('Gastos por presupuesto'), findsNothing);
    });

    testWidgets('totals with signs, growth read as words', (tester) async {
      when(() => analysis.walletStatistics(4, StatisticsRange.days30))
          .thenAnswer((_) async => statisticsFixture(range: StatisticsRange.days30));
      await pumpPage(tester);
      await tester.pumpAndSettle();
      expect(find.text(r'+ $900,00'), findsWidgets);
      expect(find.text('− \$165,75'), findsOneWidget);
      expect(find.text(r'+ $734,25'), findsOneWidget);
      expect(find.text('20 sept – 4 oct 2026 · por día'), findsOneWidget);
      expect(find.bySemanticsLabel('Ingresos: subieron 12,5 %'), findsOneWidget);
      expect(find.bySemanticsLabel('Gastos: bajaron 3 %'), findsOneWidget);
    });

    testWidgets('changing the range asks the API for that range', (tester) async {
      when(() => analysis.walletStatistics(any(), any()))
          .thenAnswer((i) async => statisticsFixture(range: i.positionalArguments[1] as StatisticsRange));
      await pumpPage(tester);
      await tester.pumpAndSettle();
      await tester.tap(find.text('1 año'));
      await tester.pumpAndSettle();
      verify(() => analysis.walletStatistics(4, StatisticsRange.year1)).called(1);
    });

    testWidgets('changing the wallet asks the API for that wallet', (tester) async {
      when(() => analysis.walletStatistics(any(), any()))
          .thenAnswer((i) async => statisticsFixture(walletId: i.positionalArguments[0] as int));
      await pumpPage(tester);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Pichincha'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Efectivo').last);
      await tester.pumpAndSettle();
      verify(() => analysis.walletStatistics(5, StatisticsRange.days30)).called(1);
    });
  });

  group('distribution gating (COU-169)', () {
    testWidgets('Contador/Pro: expenses and incomes by budget, each row one sentence', (tester) async {
      when(() => analysis.walletStatistics(4, StatisticsRange.days30))
          .thenAnswer((_) async => statisticsFixture(range: StatisticsRange.days30));
      await pumpPage(tester);
      await tester.pumpAndSettle();
      expect(find.text('Gastos por presupuesto'), findsOneWidget);
      expect(find.text('Ingresos por presupuesto'), findsOneWidget);
      expect(find.bySemanticsLabel('Supermercado: − \$120,50, 72,7 % del total'), findsOneWidget);
      expect(find.byKey(const ValueKey('distribution-locked')), findsNothing);
    });

    testWidgets('Regular: no distribution from the API → locked card that opens the plans', (tester) async {
      when(() => analysis.walletStatistics(4, StatisticsRange.days30))
          .thenAnswer((_) async => statisticsFixture(range: StatisticsRange.days30, advanced: false));
      await pumpPage(tester);
      await tester.pumpAndSettle();
      expect(find.text('Gastos por presupuesto'), findsNothing);
      expect(find.byKey(const ValueKey('distribution-locked')), findsOneWidget);
      await tester.tap(find.text('Ver planes'));
      await tester.pumpAndSettle();
      expect(find.text(distributionNotInPlanTitle), findsOneWidget);
    });
  });
}
