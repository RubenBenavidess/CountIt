import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:countit_app/app/errors/app_failure.dart';
import 'package:countit_app/app/theme/app_theme.dart';
import 'package:countit_app/app/theme/tokens.dart';
import 'package:countit_app/data/dtos/budget.dart';
import 'package:countit_app/presentation/budgets/cubit/budget_list_cubit.dart';
import 'package:countit_app/presentation/budgets/view/budget_section.dart';
import 'package:countit_app/presentation/budgets/view/widgets/budget_card.dart';
import 'package:countit_app/presentation/budgets/view/widgets/budget_progress.dart';
import 'package:countit_app/shared/state/load_state.dart';
import 'package:countit_app/shared/utils/dates.dart';
import 'package:countit_app/shared/widgets/app_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../../helpers/budget_fixtures.dart';
import '../../helpers/mocks.dart';
import '../../helpers/pump_app.dart';

const _network = AppFailure(kind: FailureKind.network, message: 'No hay conexión.');
final _today = DateTime(2026, 10, 3);

void main() {
  late MockBudgetRepository budgets;

  setUpAll(Dates.init);

  setUp(() => budgets = MockBudgetRepository());

  group('BudgetListCubit (COU-220)', () {
    final list = [budgetFixture(id: 1), budgetFixture(id: 2, name: 'Transporte')];

    blocTest<BudgetListCubit, LoadState<List<Budget>>>(
      'loads the budgets of its wallet',
      setUp: () => when(() => budgets.listByWallet(4)).thenAnswer((_) async => list),
      build: () => BudgetListCubit(budgets, walletId: 4),
      act: (cubit) => cubit.load(),
      expect: () => [const LoadState<List<Budget>>.loading(), LoadState.success(list)],
    );

    blocTest<BudgetListCubit, LoadState<List<Budget>>>(
      'a failed reload keeps the previous budgets',
      setUp: () => when(() => budgets.listByWallet(4)).thenThrow(_network),
      build: () => BudgetListCubit(budgets, walletId: 4),
      seed: () => LoadState.success(list),
      act: (cubit) => cubit.load(),
      expect: () => [
        LoadState<List<Budget>>.loading(previous: list),
        LoadState<List<Budget>>.failure(_network, previous: list),
      ],
    );

    blocTest<BudgetListCubit, LoadState<List<Budget>>>(
      'concurrent loads share one request',
      setUp: () => when(() => budgets.listByWallet(4)).thenAnswer((_) async => list),
      build: () => BudgetListCubit(budgets, walletId: 4),
      act: (cubit) => Future.wait([cubit.load(), cubit.load()]),
      verify: (_) => verify(() => budgets.listByWallet(4)).called(1),
    );
  });

  group('indicator texts (COU-218)', () {
    test('percentage rounds down and amounts read «x de y»', () {
      final budget = budgetFixture(spent: 99.6);
      expect(budget.percentLabel, '99 %');
      expect(budget.amountsLabel, r'$99,60 de $100,00');
    });

    test('status words and balance per status', () {
      expect(budgetFixture(spent: 40).statusLabel, isNull);
      expect(budgetFixture(spent: 40).balanceLabel, r'Te quedan $60,00');
      expect(budgetFixture(spent: 85).statusLabel, 'Cerca del límite');
      expect(budgetFixture(spent: 130).statusLabel, 'Excedido');
      expect(budgetFixture(spent: 130).balanceLabel, r'Te pasaste por $30,00');
      final income = budgetFixture(type: BudgetType.income, spent: 30);
      expect(income.balanceLabel, r'Faltan $70,00 para la meta');
      expect(budgetFixture(type: BudgetType.income, spent: 120).statusLabel, 'Meta alcanzada');
      expect(budgetFixture(type: BudgetType.income, spent: 120).balanceLabel, r'Superaste la meta por $20,00');
      expect(budgetFixture(type: BudgetType.income, spent: 100).balanceLabel, 'Alcanzaste la meta');
    });

    test('window label: current window, not started and ended', () {
      expect(BudgetCard.windowLabel(budgetFixture(), _today), 'Mensual · 1 oct – 31 oct 2026');
      expect(
        BudgetCard.windowLabel(budgetFixture(startDate: DateTime(2026, 11, 1)), _today),
        'Mensual · empieza el 1 nov 2026',
      );
      final ended = budgetFixture(period: BudgetPeriod.none, endDate: DateTime(2026, 9, 30));
      expect(BudgetCard.windowLabel(ended, _today), 'Finalizó el 30 sept 2026');
    });
  });

  group('BudgetCard (COU-219, COU-227)', () {
    /// Settled: the bar fills with a short animation.
    Future<void> pumpCard(WidgetTester tester, Budget budget, {VoidCallback? onTap}) async {
      await tester.pumpApp(BudgetCard(budget: budget, today: _today, onTap: onTap));
      await tester.pumpAndSettle();
    }

    LinearProgressIndicator bar(WidgetTester tester) =>
        tester.widget<LinearProgressIndicator>(find.byType(LinearProgressIndicator));

    testWidgets('on track: name, window, amounts, percentage and what is left', (tester) async {
      await pumpCard(tester, budgetFixture(spent: 40));
      expect(find.text('Comida'), findsOneWidget);
      expect(find.text('Mensual · 1 oct – 31 oct 2026'), findsOneWidget);
      expect(find.text(r'$40,00 de $100,00'), findsOneWidget);
      expect(find.text('40 %'), findsOneWidget);
      expect(find.text(r'Te quedan $60,00'), findsOneWidget);
      expect(find.text('Cerca del límite'), findsNothing);
      expect(bar(tester).value, closeTo(0.4, 1e-9));
      expect(bar(tester).color, AppColors.lavender);
    });

    testWidgets('80 %: warning word and icon, not only colour', (tester) async {
      await pumpCard(tester, budgetFixture(spent: 80));
      expect(find.text('Cerca del límite'), findsOneWidget);
      expect(find.byIcon(Icons.warning_amber_rounded), findsOneWidget);
      expect(find.text('80 %'), findsOneWidget);
    });

    testWidgets('exceeded: full bar in the expense colour, «Excedido» and the overrun', (tester) async {
      await pumpCard(tester, budgetFixture(spent: 130));
      final context = tester.element(find.byType(BudgetCard));
      expect(find.text('Excedido'), findsOneWidget);
      expect(find.byIcon(Icons.error_outline_rounded), findsOneWidget);
      expect(find.text('130 %'), findsOneWidget);
      expect(find.text(r'Te pasaste por $30,00'), findsOneWidget);
      expect(bar(tester).value, 1);
      expect(bar(tester).color, context.palette.expense);
    });

    testWidgets('income: badge, income colour and goal reached', (tester) async {
      await pumpCard(
        tester,
        budgetFixture(name: 'Sueldo', type: BudgetType.income, icon: BudgetIcon.salary, spent: 100),
      );
      final context = tester.element(find.byType(BudgetCard));
      expect(find.text('Ingreso'), findsOneWidget);
      expect(find.text('Meta alcanzada'), findsOneWidget);
      expect(bar(tester).color, context.palette.income);
    });

    testWidgets('one semantics node tells the whole story; taps reach onTap', (tester) async {
      final handle = tester.ensureSemantics();
      var taps = 0;
      await pumpCard(tester, budgetFixture(spent: 85), onTap: () => taps++);
      expect(
        find.bySemanticsLabel(
          'Presupuesto de gasto Comida. Mensual · 1 oct – 31 oct 2026. '
          r'Gastado $85,00 de $100,00, 85 %. Cerca del límite. Te quedan $15,00',
        ),
        findsOneWidget,
      );
      await tester.tap(find.byType(AppCard));
      expect(taps, 1);
      final size = tester.getSize(find.byType(AppCard));
      expect(size.height, greaterThanOrEqualTo(44));
      handle.dispose();
    });
  });

  group('BudgetSection states (COU-219, COU-220)', () {
    Future<BudgetListCubit> pumpSection(WidgetTester tester) async {
      final cubit = BudgetListCubit(budgets, walletId: 4);
      unawaited(cubit.load());
      addTearDown(cubit.close);
      await tester.pumpApp(
        BlocProvider.value(
          value: cubit,
          child: CustomScrollView(
            slivers: [BudgetSection(onCreate: () {}, onOpen: (_) {})],
          ),
        ),
      );
      return cubit;
    }

    testWidgets('loading, then the list', (tester) async {
      when(() => budgets.listByWallet(4)).thenAnswer((_) async {
        await Future<void>.delayed(const Duration(milliseconds: 50));
        return [budgetFixture(), budgetFixture(id: 2, name: 'Transporte')];
      });
      await pumpSection(tester);
      expect(find.text('Presupuestos'), findsOneWidget);
      expect(find.bySemanticsLabel('Cargando presupuestos'), findsOneWidget);
      await tester.pumpAndSettle(const Duration(milliseconds: 60));
      expect(find.byType(BudgetCard), findsNWidgets(2));
      expect(find.text('Transporte'), findsOneWidget);
    });

    testWidgets('empty', (tester) async {
      when(() => budgets.listByWallet(4)).thenAnswer((_) async => const []);
      await pumpSection(tester);
      await tester.pumpAndSettle();
      expect(find.textContaining('Aún no hay presupuestos'), findsOneWidget);
      expect(find.byType(BudgetCard), findsNothing);
    });

    testWidgets('error with retry', (tester) async {
      when(() => budgets.listByWallet(4)).thenThrow(_network);
      await pumpSection(tester);
      await tester.pumpAndSettle();
      expect(find.text('No hay conexión.'), findsOneWidget);
      when(() => budgets.listByWallet(4)).thenAnswer((_) async => [budgetFixture()]);
      await tester.tap(find.text('Reintentar'));
      await tester.pumpAndSettle();
      expect(find.byType(BudgetCard), findsOneWidget);
    });
  });
}
