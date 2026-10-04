import 'package:bloc_test/bloc_test.dart';
import 'package:countit_app/app/errors/app_failure.dart';
import 'package:countit_app/app/router/app_router.dart';
import 'package:countit_app/data/dtos/budget.dart';
import 'package:countit_app/data/remote/api_client.dart';
import 'package:countit_app/presentation/transactions/view/transaction_detail_page.dart';
import 'package:countit_app/shared/state/delete_cubit.dart';
import 'package:countit_app/shared/utils/dates.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';

import '../../helpers/mocks.dart';
import '../../helpers/pump_app.dart';
import '../../helpers/transaction_fixtures.dart';

const _notFound = AppFailure(
  kind: FailureKind.notFound,
  message: 'Transacción no encontrada',
  key: 'transaction_not_found',
  status: 404,
);
const _reauthRequired = AppFailure(
  kind: FailureKind.reauthRequired,
  message: 'Confirma tu contraseña para continuar',
  key: 'reauth_required',
  status: 403,
);
const _network = AppFailure(kind: FailureKind.network, message: 'No hay conexión.');

void main() {
  late MockTransactionRepository transactions;
  late MockAuthRepository auth;

  final transaction = transactionFixture(
    id: 7,
    name: 'Mercado',
    amount: 45.2,
    date: DateTime(2026, 10, 1),
    budgetId: 1,
    budgetName: 'Comida',
    budgetIcon: BudgetIcon.food,
    authorName: 'Usuario eliminado',
  );

  setUpAll(Dates.init);

  setUp(() {
    transactions = MockTransactionRepository();
    auth = MockAuthRepository();
    when(() => auth.sessionChanges).thenAnswer((_) => const Stream.empty());
  });

  /// Wallet stand-in → detail; returns what the detail pops.
  Future<List<Object?>> pumpDetail(WidgetTester tester, {bool canManage = true}) async {
    tester.view.physicalSize = const Size(420, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final results = <Object?>[];
    final router = GoRouter(
      initialLocation: AppRoutes.home,
      routes: [
        GoRoute(
          path: AppRoutes.home,
          builder: (context, state) => Scaffold(
            body: TextButton(
              onPressed: () async => results.add(
                await context.push<Object?>(
                  AppRoutes.transaction(4, 7),
                  extra: TransactionDetailArgs(transaction, canManage: canManage),
                ),
              ),
              child: const Text('WALLET'),
            ),
          ),
        ),
        GoRoute(
          path: '${AppRoutes.wallets}/:id/transactions/:transactionId',
          builder: (context, state) => TransactionDetailPage(walletId: 4, args: state.extra! as TransactionDetailArgs),
        ),
        GoRoute(
          path: '${AppRoutes.wallets}/:id/transactions/:transactionId/edit',
          builder: (context, state) => Scaffold(
            body: TextButton(onPressed: () => context.pop(true), child: const Text('EDIT FORM')),
          ),
        ),
      ],
    );
    await tester.pumpApp(const SizedBox(), auth: auth, transactions: transactions, router: router);
    await tester.tap(find.text('WALLET'));
    await tester.pumpAndSettle();
    return results;
  }

  Future<void> tapButton(WidgetTester tester, String label) async {
    final button = find.widgetWithText(FilledButton, label);
    await tester.ensureVisible(button);
    await tester.pumpAndSettle();
    await tester.tap(button);
    await tester.pumpAndSettle();
  }

  /// «Eliminar movimiento» and confirm. Pumps frames instead of settling:
  /// the button spins while the password sheet is open.
  Future<void> confirmDelete(WidgetTester tester) async {
    await tapButton(tester, 'Eliminar movimiento');
    expect(find.text('¿Eliminar «Mercado»?'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Eliminar'));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> tapInSheet(WidgetTester tester, String label) async {
    await tester.tap(find.widgetWithText(FilledButton, label).last);
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  group('detail (COU-241)', () {
    testWidgets('amount with sign, date, budget and author (also «Usuario eliminado»)', (tester) async {
      await pumpDetail(tester);
      expect(find.text('Mercado'), findsOneWidget);
      expect(find.text('− \$45,20'), findsOneWidget);
      expect(find.text('Jueves, 1 de octubre de 2026'), findsOneWidget);
      expect(find.text('Comida'), findsOneWidget);
      expect(find.text('Usuario eliminado'), findsOneWidget);
      expect(find.text('Editar movimiento'), findsOneWidget);
      expect(find.text('Eliminar movimiento'), findsOneWidget);
    });

    testWidgets('read-only for whoever may not manage it', (tester) async {
      await pumpDetail(tester, canManage: false);
      expect(find.text('Eliminar movimiento'), findsNothing);
      expect(find.text('Editar movimiento'), findsNothing);
      expect(find.textContaining('Solo quien lo registró'), findsOneWidget);
    });

    testWidgets('editing reloads the detail and tells the wallet to reload', (tester) async {
      when(() => transactions.getById(7)).thenAnswer((_) async => transactionFixture(id: 7, name: 'Mercado grande'));
      final results = await pumpDetail(tester);
      await tapButton(tester, 'Editar movimiento');
      await tester.tap(find.text('EDIT FORM'));
      await tester.pumpAndSettle();
      expect(find.text('Mercado grande'), findsOneWidget);
      await tester.tap(find.byTooltip('Volver'));
      await tester.pumpAndSettle();
      expect(results, [true]);
    });

    testWidgets('leaving without changes does not ask the wallet to reload', (tester) async {
      final results = await pumpDetail(tester);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(results, [false]);
    });

    testWidgets('deleted elsewhere while editing: leaves with a message', (tester) async {
      when(() => transactions.getById(7)).thenThrow(_notFound);
      final results = await pumpDetail(tester);
      await tapButton(tester, 'Editar movimiento');
      await tester.tap(find.text('EDIT FORM'));
      await tester.pumpAndSettle();
      expect(results, [true]);
      expect(find.text('Transacción no encontrada'), findsOneWidget);
    });
  });

  group('delete with reauthentication (COU-240, COU-244)', () {
    /// Behaves like [ApiClient.run]: on reauth_required asks [onReauth] and retries once.
    void deleteNeedsReauth({required List<int> calls}) {
      when(() => transactions.delete(7, onReauth: any(named: 'onReauth'))).thenAnswer((invocation) async {
        calls.add(7);
        final prompt = invocation.namedArguments[#onReauth] as ReauthPrompt?;
        if (prompt == null || !await prompt()) throw _reauthRequired;
        calls.add(7);
      });
    }

    testWidgets('within the safe-mode window: deletes at once and returns to the wallet', (tester) async {
      when(() => transactions.delete(7, onReauth: any(named: 'onReauth'))).thenAnswer((_) async {});
      final results = await pumpDetail(tester);
      await confirmDelete(tester);
      await tester.pumpAndSettle();
      expect(find.text('Confirma que eres tú'), findsNothing);
      expect(results, [true]);
      expect(find.text('Eliminamos «Mercado»'), findsOneWidget);
    });

    testWidgets('reauth_required: asks for the password, retries and deletes', (tester) async {
      final calls = <int>[];
      deleteNeedsReauth(calls: calls);
      when(() => auth.reauthenticate('Quito2026')).thenAnswer((_) async => DateTime(2026, 10, 3, 12, 5));
      final results = await pumpDetail(tester);
      await confirmDelete(tester);
      expect(find.text('Confirma que eres tú'), findsOneWidget);
      expect(find.textContaining('Para eliminar «Mercado» escribe tu contraseña'), findsOneWidget);

      await tester.enterText(find.byType(EditableText), 'Quito2026');
      await tapInSheet(tester, 'Eliminar movimiento');
      await tester.pumpAndSettle();
      verify(() => auth.reauthenticate('Quito2026')).called(1);
      expect(calls, [7, 7], reason: 'first attempt plus the retry');
      expect(results, [true]);
    });

    testWidgets('cancelling the password sheet deletes nothing and shows no error', (tester) async {
      final calls = <int>[];
      deleteNeedsReauth(calls: calls);
      final results = await pumpDetail(tester);
      await confirmDelete(tester);
      await tapInSheet(tester, 'Cancelar');
      await tester.pumpAndSettle();
      expect(calls, [7], reason: 'no retry');
      expect(results, isEmpty, reason: 'still on the detail');
      expect(find.byType(SnackBar), findsNothing);
      verifyNever(() => auth.reauthenticate(any()));
    });

    testWidgets('cancelling the confirmation does not call the API', (tester) async {
      await pumpDetail(tester);
      await tapButton(tester, 'Eliminar movimiento');
      await tester.tap(find.widgetWithText(FilledButton, 'Cancelar'));
      await tester.pumpAndSettle();
      verifyNever(() => transactions.delete(any(), onReauth: any(named: 'onReauth')));
    });

    testWidgets('404 on delete: treated as already deleted', (tester) async {
      when(() => transactions.delete(7, onReauth: any(named: 'onReauth'))).thenThrow(_notFound);
      final results = await pumpDetail(tester);
      await confirmDelete(tester);
      await tester.pumpAndSettle();
      expect(results, [true]);
    });

    testWidgets('other errors stay on the detail with the message', (tester) async {
      when(() => transactions.delete(7, onReauth: any(named: 'onReauth'))).thenThrow(_network);
      final results = await pumpDetail(tester);
      await confirmDelete(tester);
      await tester.pumpAndSettle();
      expect(results, isEmpty);
      expect(find.text('No hay conexión.'), findsOneWidget);
    });
  });

  group('DeleteCubit', () {
    blocTest<DeleteCubit, DeleteState>(
      'deletes once (double taps are ignored)',
      build: () => DeleteCubit(({onReauth}) async {}),
      act: (cubit) => Future.wait([cubit.delete(), cubit.delete()]),
      expect: () => [const DeleteState(status: DeleteStatus.deleting), const DeleteState(status: DeleteStatus.deleted)],
    );

    blocTest<DeleteCubit, DeleteState>(
      'reauth cancelled: back to idle without a failure',
      build: () => DeleteCubit(({onReauth}) async => throw _reauthRequired),
      act: (cubit) => cubit.delete(),
      expect: () => [const DeleteState(status: DeleteStatus.deleting), const DeleteState()],
    );
  });
}
