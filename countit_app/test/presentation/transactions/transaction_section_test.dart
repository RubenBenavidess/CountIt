import 'dart:async';

import 'package:countit_app/app/errors/app_failure.dart';
import 'package:countit_app/app/theme/tokens.dart';
import 'package:countit_app/data/dtos/budget.dart';
import 'package:countit_app/data/dtos/transaction.dart';
import 'package:countit_app/presentation/transactions/cubit/transaction_list_cubit.dart';
import 'package:countit_app/presentation/transactions/view/transaction_section.dart';
import 'package:countit_app/presentation/transactions/view/widgets/transaction_tile.dart';
import 'package:countit_app/shared/utils/dates.dart';
import 'package:countit_app/shared/widgets/load_more_listener.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../../helpers/mocks.dart';
import '../../helpers/pump_app.dart';
import '../../helpers/transaction_fixtures.dart';

const _network = AppFailure(kind: FailureKind.network, message: 'No hay conexión.');

void main() {
  late MockTransactionRepository transactions;

  setUpAll(() async {
    await Dates.init();
    registerFallbackValue(TransactionCursor(date: DateTime(2026), transactionId: 0));
  });

  setUp(() => transactions = MockTransactionRepository());

  /// The section inside a scroll view like the wallet detail's.
  Future<TransactionListCubit> pumpSection(WidgetTester tester, {bool showAuthor = false}) async {
    final cubit = TransactionListCubit(transactions, walletId: 4);
    addTearDown(cubit.close);
    unawaited(cubit.load());
    await tester.pumpApp(
      BlocProvider.value(
        value: cubit,
        child: LoadMoreListener(
          onLoadMore: cubit.loadMore,
          child: CustomScrollView(
            slivers: [
              SliverPadding(
                padding: const EdgeInsets.all(AppSpacing.screen),
                sliver: TransactionSection(showAuthor: showAuthor),
              ),
            ],
          ),
        ),
      ),
      transactions: transactions,
    );
    await tester.pumpAndSettle();
    return cubit;
  }

  group('rows and day headers (COU-231)', () {
    testWidgets('headers by day; signs and amounts; budget or «Sin presupuesto»', (tester) async {
      final today = Dates.userToday(null);
      when(() => transactions.list(4)).thenAnswer(
        (_) async => TransactionPage([
          transactionFixture(id: 3, name: 'Sueldo', type: TransactionType.income, amount: 800, date: today),
          transactionFixture(
            id: 2,
            name: 'Almuerzo',
            amount: 12.5,
            date: today.subtract(const Duration(days: 1)),
            budgetId: 1,
            budgetName: 'Comida',
            budgetIcon: BudgetIcon.food,
          ),
          transactionFixture(id: 1, name: 'Taxi', amount: 3, date: DateTime(2025, 9, 30)),
        ]),
      );
      await pumpSection(tester);
      expect(find.text('Hoy'), findsOneWidget);
      expect(find.text('Ayer'), findsOneWidget);
      expect(find.text('Martes, 30 de septiembre de 2025'), findsOneWidget);
      expect(find.text(r'+ $800,00'), findsOneWidget);
      expect(find.text('− \$12,50'), findsOneWidget);
      expect(find.text('Comida'), findsOneWidget);
      expect(find.text('Sin presupuesto'), findsNWidgets(2));
      expect(find.text('María Quishpe', findRichText: true), findsNothing, reason: 'author only in shared wallets');
    });

    testWidgets('shared wallets show the author; rows announce type, signed amount, date and author', (tester) async {
      final handle = tester.ensureSemantics();
      when(() => transactions.list(4)).thenAnswer(
        (_) async => TransactionPage([
          transactionFixture(
            id: 1,
            name: 'Mercado',
            amount: 45.2,
            date: DateTime(2026, 10, 1),
            budgetId: 1,
            budgetName: 'Comida',
            authorName: 'Usuario eliminado',
          ),
        ]),
      );
      await pumpSection(tester, showAuthor: true);
      expect(find.text('Comida · Usuario eliminado'), findsOneWidget);
      expect(
        find.bySemanticsLabel(
          'Gasto Mercado, menos \$45,20, jueves, 1 de octubre de 2026, Presupuesto Comida, '
          'Registrado por Usuario eliminado',
        ),
        findsOneWidget,
      );
      expect(tester.getSize(find.byType(TransactionTile)).height, greaterThanOrEqualTo(48));
      handle.dispose();
    });
  });

  group('states (COU-235)', () {
    testWidgets('empty wallet', (tester) async {
      when(() => transactions.list(4)).thenAnswer((_) async => const TransactionPage([]));
      await pumpSection(tester);
      expect(find.textContaining('Aún no hay movimientos'), findsOneWidget);
    });

    testWidgets('first load fails: message and retry', (tester) async {
      var calls = 0;
      when(() => transactions.list(4)).thenAnswer((_) async {
        if (calls++ == 0) throw _network;
        return TransactionPage([transactionFixture(name: 'Taxi')]);
      });
      await pumpSection(tester);
      expect(find.text('No hay conexión.'), findsOneWidget);
      await tester.tap(find.text('Reintentar'));
      await tester.pumpAndSettle();
      expect(find.text('Taxi'), findsOneWidget);
    });
  });

  group('infinite scroll (COU-232)', () {
    List<Transaction> page(int from, int count) => [
      for (var i = 0; i < count; i++) transactionFixture(id: from - i, name: 'Movimiento ${from - i}'),
    ];

    testWidgets('scrolling near the end loads the next page once', (tester) async {
      final first = page(100, 30);
      final cursor = TransactionCursor.after(first.last);
      when(() => transactions.list(4)).thenAnswer((_) async => TransactionPage(first, next: cursor));
      when(() => transactions.list(4, after: cursor)).thenAnswer((_) async => TransactionPage(page(70, 5)));
      await pumpSection(tester);
      expect(find.text('Movimiento 66'), findsNothing);

      await tester.scrollUntilVisible(find.text('Movimiento 66'), 400);
      await tester.pumpAndSettle();
      expect(find.text('Movimiento 66'), findsOneWidget);
      verify(() => transactions.list(4, after: cursor)).called(1);
      expect(find.byKey(const ValueKey('transactions-footer')), findsNothing, reason: 'last page loaded');
    });

    testWidgets('a failed page shows a retry row at the end', (tester) async {
      final first = page(100, 30);
      final cursor = TransactionCursor.after(first.last);
      var calls = 0;
      when(() => transactions.list(4)).thenAnswer((_) async => TransactionPage(first, next: cursor));
      when(() => transactions.list(4, after: cursor)).thenAnswer((_) async {
        if (calls++ == 0) throw _network;
        return TransactionPage(page(70, 1));
      });
      await pumpSection(tester);
      await tester.scrollUntilVisible(find.text('No pudimos cargar más movimientos.'), 400);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Reintentar'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.text('Movimiento 70'), 400);
      expect(find.text('Movimiento 70'), findsOneWidget);
    });
  });
}
