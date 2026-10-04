import 'package:countit_app/app/errors/app_failure.dart';
import 'package:countit_app/app/router/app_router.dart';
import 'package:countit_app/data/dtos/family.dart';
import 'package:countit_app/data/dtos/scheduled_transaction.dart';
import 'package:countit_app/data/dtos/transaction.dart';
import 'package:countit_app/data/dtos/wallet.dart';
import 'package:countit_app/data/remote/api_client.dart';
import 'package:countit_app/presentation/budgets/view/budget_form_page.dart';
import 'package:countit_app/presentation/transactions/view/transaction_detail_page.dart';
import 'package:countit_app/presentation/wallets/view/wallet_detail_page.dart';
import 'package:countit_app/shared/utils/dates.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';

import '../../helpers/budget_fixtures.dart';
import '../../helpers/family_fixtures.dart';
import '../../helpers/mocks.dart';
import '../../helpers/pump_app.dart';
import '../../helpers/transaction_fixtures.dart';
import '../../helpers/wallet_fixtures.dart';

const _notFound = AppFailure(
  kind: FailureKind.notFound,
  message: 'Billetera no encontrada',
  key: 'wallet_not_found',
  status: 404,
);
const _reauthRequired = AppFailure(
  kind: FailureKind.reauthRequired,
  message: 'Confirma tu contraseña para continuar',
  key: 'reauth_required',
  status: 403,
);
const _network = AppFailure(kind: FailureKind.network, message: 'No hay conexión.');

String _editLabel(BudgetEditArgs args) => 'EDIT BUDGET ${args.budget.name} canDelete=${args.canDelete}';

void main() {
  late MockWalletRepository wallets;
  late MockAuthRepository auth;
  late MockBudgetRepository budgets;
  late MockTransactionRepository transactions;
  late MockFamilyRepository families;

  setUpAll(Dates.init);

  setUp(() {
    wallets = MockWalletRepository();
    auth = MockAuthRepository();
    budgets = MockBudgetRepository();
    when(() => budgets.listByWallet(any())).thenAnswer((_) async => const []);
    transactions = MockTransactionRepository();
    when(() => transactions.list(any())).thenAnswer((_) async => const TransactionPage([]));
    when(() => auth.sessionChanges).thenAnswer((_) => const Stream.empty());
    families = noFamilies();
  });

  /// Home → detail of [wallet]; the edit route is a stand-in.
  Future<void> pumpDetail(WidgetTester tester, Wallet wallet) async {
    tester.view.physicalSize = const Size(420, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final router = GoRouter(
      initialLocation: AppRoutes.home,
      routes: [
        GoRoute(
          path: AppRoutes.home,
          builder: (context, state) => Scaffold(
            body: TextButton(
              onPressed: () => context.push(AppRoutes.wallet(wallet.walletId), extra: wallet),
              child: const Text('HOME'),
            ),
          ),
        ),
        GoRoute(
          path: '${AppRoutes.wallets}/:id',
          builder: (context, state) =>
              WalletDetailPage(walletId: int.parse(state.pathParameters['id']!), initial: state.extra as Wallet?),
          routes: [
            GoRoute(
              path: 'edit',
              builder: (context, state) => const Scaffold(body: Text('EDIT FORM')),
            ),
            GoRoute(
              path: 'budgets/new',
              builder: (context, state) => Scaffold(
                body: TextButton(onPressed: () => context.pop(true), child: const Text('NEW BUDGET')),
              ),
            ),
            GoRoute(
              path: 'transactions/new',
              builder: (context, state) => Scaffold(
                body: Column(
                  children: [
                    TextButton(onPressed: () => context.pop(true), child: const Text('NEW TRANSACTION')),
                    TextButton(
                      onPressed: () => context.pop(
                        ScheduledTransactionInput(
                          name: 'Matrícula',
                          type: TransactionType.expense,
                          amountCents: 12000,
                          startDate: DateTime(2030),
                        ),
                      ),
                      child: const Text('FUTURE DATE'),
                    ),
                  ],
                ),
              ),
            ),
            GoRoute(
              path: 'transactions/:transactionId',
              builder: (context, state) {
                final args = state.extra! as TransactionDetailArgs;
                return Scaffold(
                  body: TextButton(
                    onPressed: () => context.pop(false),
                    child: Text('DETAIL ${args.transaction.name} canManage=${args.canManage}'),
                  ),
                );
              },
            ),
            GoRoute(
              path: 'transactions/:transactionId/edit',
              builder: (context, state) => Scaffold(
                body: TextButton(
                  onPressed: () => context.pop(true),
                  child: Text('EDIT TRANSACTION ${(state.extra! as Transaction).name}'),
                ),
              ),
            ),
            GoRoute(
              path: 'scheduled/new',
              builder: (context, state) =>
                  Scaffold(body: Text('SCHEDULE ${(state.extra! as ScheduledTransactionInput).name}')),
            ),
            GoRoute(
              path: 'scheduled',
              builder: (context, state) => Scaffold(body: Text('SCHEDULED ${(state.extra! as Wallet).name}')),
            ),
            GoRoute(
              path: 'members',
              builder: (context, state) => Scaffold(body: Text('MEMBERS ${(state.extra! as Wallet).name}')),
            ),
            GoRoute(
              path: 'budgets/:budgetId/edit',
              builder: (context, state) => Scaffold(
                body: TextButton(
                  onPressed: () => context.pop(false),
                  child: Text(_editLabel(state.extra! as BudgetEditArgs)),
                ),
              ),
            ),
          ],
        ),
      ],
    );
    await tester.pumpApp(
      const SizedBox(),
      auth: auth,
      wallets: wallets,
      budgets: budgets,
      transactions: transactions,
      families: families,
      router: router,
    );
    await tester.tap(find.text('HOME'));
    await tester.pumpAndSettle();
  }

  /// «Eliminar» from the actions menu (owner only).
  Future<void> openDelete(WidgetTester tester) async {
    await tester.tap(find.byTooltip('Acciones'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Eliminar'));
    await tester.pumpAndSettle();
  }

  /// Confirms the «¿Eliminar…?» dialog. Pumps frames instead of settling:
  /// the progress bar runs while the password sheet is open.
  Future<void> confirmDelete(WidgetTester tester) async {
    await openDelete(tester);
    expect(find.textContaining('¿Eliminar «'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Eliminar'));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  /// Taps a button inside the password sheet and lets the flow finish.
  Future<void> tapInSheet(WidgetTester tester, String label) async {
    await tester.tap(find.widgetWithText(FilledButton, label).last);
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  group('budgets in the detail (COU-219, COU-224, COU-225)', () {
    testWidgets('lists the wallet budgets; «Nuevo» opens the form and a save reloads them', (tester) async {
      final wallet = walletFixture(id: 4, isOwner: false, memberCount: 1);
      when(() => wallets.getById(4)).thenAnswer((_) async => wallet);
      when(() => budgets.listByWallet(4)).thenAnswer((_) async => [budgetFixture(name: 'Mercado')]);
      await pumpDetail(tester, wallet);
      expect(find.text('Mercado'), findsOneWidget);

      await tester.tap(find.text('Mercado'));
      await tester.pumpAndSettle();
      expect(
        find.text('EDIT BUDGET Mercado canDelete=false'),
        findsOneWidget,
        reason: 'a member who is not the author may edit but not delete',
      );
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('budget-new')), warnIfMissed: false);
      await tester.pumpAndSettle();
      await tester.tap(find.text('NEW BUDGET'));
      await tester.pumpAndSettle();
      verify(() => budgets.listByWallet(4)).called(2);
    });

    testWidgets('tapping a card edits that budget; cancelling does not reload', (tester) async {
      final wallet = walletFixture(id: 4);
      when(() => wallets.getById(4)).thenAnswer((_) async => wallet);
      when(() => budgets.listByWallet(4)).thenAnswer((_) async => [budgetFixture(name: 'Mercado')]);
      await pumpDetail(tester, wallet);
      await tester.tap(find.text('Mercado'));
      await tester.pumpAndSettle();
      expect(find.text('EDIT BUDGET Mercado canDelete=true'), findsOneWidget, reason: 'the owner may delete');
      await tester.tap(find.text('EDIT BUDGET Mercado canDelete=true'));
      await tester.pumpAndSettle();
      verify(() => budgets.listByWallet(4)).called(1);
    });
  });

  group('detail (COU-195, COU-211)', () {
    testWidgets('loads fresh data: totals, month and opening balance', (tester) async {
      final initial = walletFixture(id: 4, name: 'Ahorros', balance: 10);
      when(() => wallets.getById(4)).thenAnswer((_) async => walletFixture(id: 4, name: 'Ahorros', balance: 25));
      await pumpDetail(tester, initial);
      expect(find.text(r'$25,00'), findsOneWidget);
      expect(find.text('Saldo inicial'), findsOneWidget);
      expect(find.text('Ingresos totales'), findsOneWidget);
      expect(find.text('Gastos del mes'), findsWidgets);
      expect(find.text('Saldo proyectado a fin de mes'), findsNothing);
      expect(find.text('Presupuestos'), findsOneWidget);
      expect(find.text('Movimientos'), findsOneWidget);
    });

    testWidgets('lists the wallet movements (COU-231)', (tester) async {
      final wallet = walletFixture(id: 4);
      when(() => wallets.getById(4)).thenAnswer((_) async => wallet);
      when(() => transactions.list(4)).thenAnswer((_) async => TransactionPage([transactionFixture(name: 'Taxi')]));
      await pumpDetail(tester, wallet);
      await tester.scrollUntilVisible(find.text('Taxi'), 300);
      expect(find.text('Taxi'), findsOneWidget);
    });

    testWidgets('«Movimiento» registers one; a save reloads the wallet, budgets and movements (COU-238)', (
      tester,
    ) async {
      final wallet = walletFixture(id: 4);
      when(() => wallets.getById(4)).thenAnswer((_) async => wallet);
      await pumpDetail(tester, wallet);
      await tester.tap(find.byKey(const ValueKey('transaction-new')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('NEW TRANSACTION'));
      await tester.pumpAndSettle();
      verify(() => wallets.getById(4)).called(2);
      verify(() => budgets.listByWallet(4)).called(2);
      verify(() => transactions.list(4)).called(2);
    });

    testWidgets('tapping a movement opens its detail; only the owner or the author may manage it (COU-241)', (
      tester,
    ) async {
      when(() => transactions.list(4))
          .thenAnswer((_) async => TransactionPage([transactionFixture(name: 'Taxi', userId: 'someone-else')]));
      final owned = walletFixture(id: 4);
      when(() => wallets.getById(4)).thenAnswer((_) async => owned);
      await pumpDetail(tester, owned);
      await tester.scrollUntilVisible(find.text('Taxi'), 300);
      await tester.tap(find.text('Taxi'));
      await tester.pumpAndSettle();
      expect(find.text('DETAIL Taxi canManage=true'), findsOneWidget, reason: 'the wallet owner manages any movement');
    });

    testWidgets('a member sees someone else\'s movement read-only; closing without changes does not reload', (
      tester,
    ) async {
      when(() => transactions.list(4))
          .thenAnswer((_) async => TransactionPage([transactionFixture(name: 'Taxi', userId: 'someone-else')]));
      final shared = walletFixture(id: 4, isOwner: false, memberCount: 1);
      when(() => wallets.getById(4)).thenAnswer((_) async => shared);
      await pumpDetail(tester, shared);
      await tester.scrollUntilVisible(find.text('Taxi'), 300);
      await tester.tap(find.text('Taxi'));
      await tester.pumpAndSettle();
      expect(find.text('DETAIL Taxi canManage=false'), findsOneWidget);
      await tester.tap(find.text('DETAIL Taxi canManage=false'));
      await tester.pumpAndSettle();
      verify(() => transactions.list(4)).called(1);
    });

    testWidgets('projection row only with the plan feature', (tester) async {
      final wallet = walletFixture(id: 4, projectedBalance: 1300);
      when(() => wallets.getById(4)).thenAnswer((_) async => wallet);
      await pumpDetail(tester, wallet);
      expect(find.text('Saldo proyectado a fin de mes'), findsNWidgets(2), reason: 'card and figures');
    });

    testWidgets('owner sees edit and delete; edit opens the form and reloads on return', (tester) async {
      final wallet = walletFixture(id: 4);
      when(() => wallets.getById(4)).thenAnswer((_) async => wallet);
      await pumpDetail(tester, wallet);
      await tester.tap(find.byTooltip('Acciones'));
      await tester.pumpAndSettle();
      expect(find.text('Editar'), findsOneWidget);
      expect(find.text('Eliminar'), findsOneWidget);
      expect(find.text('Miembros'), findsOneWidget);

      await tester.tap(find.text('Editar'));
      await tester.pumpAndSettle();
      expect(find.text('EDIT FORM'), findsOneWidget);
      tester.state<NavigatorState>(find.byType(Navigator).last).pop();
      await tester.pumpAndSettle();
      verify(() => wallets.getById(4)).called(2);
    });

    testWidgets('shared wallet: owner actions are hidden', (tester) async {
      final wallet = walletFixture(id: 4, isOwner: false, ownerName: 'Luis Andrade', memberCount: 1);
      when(() => wallets.getById(4)).thenAnswer((_) async => wallet);
      await pumpDetail(tester, wallet);
      expect(find.text('Compartida contigo por Luis Andrade'), findsOneWidget);
      expect(find.text('Eliminar billetera'), findsNothing);
      expect(find.text('Editar billetera'), findsNothing);
      await tester.tap(find.byTooltip('Acciones'));
      await tester.pumpAndSettle();
      expect(find.text('Editar'), findsNothing);
      expect(find.text('Eliminar'), findsNothing);
      expect(find.text('Miembros'), findsOneWidget);
    });

    testWidgets('missing, someone else\'s or deleted: back home with «Billetera no encontrada»', (tester) async {
      when(() => wallets.getById(9)).thenAnswer((_) async => throw _notFound);
      await pumpDetail(tester, walletFixture(id: 9));
      expect(find.text('HOME'), findsOneWidget);
      expect(find.text('Billetera no encontrada'), findsOneWidget);
    });

    testWidgets('a network error keeps the card and explains in a snackbar', (tester) async {
      when(() => wallets.getById(4)).thenAnswer((_) async => throw _network);
      await pumpDetail(tester, walletFixture(id: 4, name: 'Ahorros'));
      expect(find.text('Saldo inicial'), findsOneWidget);
      expect(find.text('No hay conexión.'), findsOneWidget);
    });
  });

  group('delete with reauthentication (COU-212, COU-216)', () {
    final wallet = walletFixture(id: 4, name: 'Hogar');

    setUp(() => when(() => wallets.getById(4)).thenAnswer((_) async => wallet));

    /// Behaves like [ApiClient.run]: on reauth_required asks [onReauth] and retries once.
    void deleteNeedsReauth({required List<int> calls}) {
      when(() => wallets.delete(4, onReauth: any(named: 'onReauth'))).thenAnswer((invocation) async {
        calls.add(4);
        final prompt = invocation.namedArguments[#onReauth] as ReauthPrompt?;
        if (prompt == null || !await prompt()) throw _reauthRequired;
        calls.add(4);
      });
    }

    testWidgets('within the safe-mode window: deletes at once and returns home', (tester) async {
      when(() => wallets.delete(4, onReauth: any(named: 'onReauth'))).thenAnswer((_) async {});
      await pumpDetail(tester, wallet);
      await confirmDelete(tester);
      verify(() => wallets.delete(4, onReauth: any(named: 'onReauth'))).called(1);
      expect(find.text('Confirma que eres tú'), findsNothing);
      expect(find.text('HOME'), findsOneWidget);
      expect(find.text('Eliminamos «Hogar»'), findsOneWidget);
    });

    testWidgets('reauth_required: asks for the password, then retries and deletes', (tester) async {
      final calls = <int>[];
      deleteNeedsReauth(calls: calls);
      when(() => auth.reauthenticate('Quito2026')).thenAnswer((_) async => DateTime(2026, 10, 3, 12, 5));
      await pumpDetail(tester, wallet);
      await confirmDelete(tester);
      expect(find.text('Confirma que eres tú'), findsOneWidget);
      expect(find.textContaining('Para eliminar «Hogar» escribe tu contraseña'), findsOneWidget);

      await tester.enterText(find.byType(EditableText), 'Quito2026');
      await tapInSheet(tester, 'Eliminar billetera');
      verify(() => auth.reauthenticate('Quito2026')).called(1);
      expect(calls, [4, 4], reason: 'first attempt plus the retry');
      expect(find.text('HOME'), findsOneWidget);
      expect(find.text('Eliminamos «Hogar»'), findsOneWidget);
    });

    testWidgets('cancelling the password sheet deletes nothing and shows no error', (tester) async {
      final calls = <int>[];
      deleteNeedsReauth(calls: calls);
      await pumpDetail(tester, wallet);
      await confirmDelete(tester);
      await tapInSheet(tester, 'Cancelar');
      await tester.pumpAndSettle();
      expect(calls, [4], reason: 'no retry');
      expect(find.text('Saldo inicial'), findsOneWidget, reason: 'still on the detail');
      expect(find.byType(SnackBar), findsNothing);
      verifyNever(() => auth.reauthenticate(any()));
    });

    testWidgets('cancelling the confirmation dialog does not call the API', (tester) async {
      await pumpDetail(tester, wallet);
      await openDelete(tester);
      await tester.tap(find.widgetWithText(FilledButton, 'Cancelar'));
      await tester.pumpAndSettle();
      verifyNever(() => wallets.delete(any(), onReauth: any(named: 'onReauth')));
    });

    testWidgets('404 on delete: treated as already deleted', (tester) async {
      when(() => wallets.delete(4, onReauth: any(named: 'onReauth'))).thenThrow(_notFound);
      await pumpDetail(tester, wallet);
      await confirmDelete(tester);
      expect(find.text('HOME'), findsOneWidget);
      expect(find.text('Eliminamos «Hogar»'), findsOneWidget);
    });

    testWidgets('other errors stay on the detail with the message', (tester) async {
      when(() => wallets.delete(4, onReauth: any(named: 'onReauth'))).thenThrow(_network);
      await pumpDetail(tester, wallet);
      await confirmDelete(tester);
      expect(find.text('Saldo inicial'), findsOneWidget);
      expect(find.text('No hay conexión.'), findsOneWidget);
    });
  });

  testWidgets('«Movimientos programados» opens the wallet\'s rules (COU-88)', (tester) async {
    final wallet = walletFixture(id: 4, name: 'Pichincha');
    when(() => wallets.getById(4)).thenAnswer((_) async => wallet);
    await pumpDetail(tester, wallet);
    expect(find.bySemanticsLabel(RegExp('^Movimientos programados')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('wallet-scheduled')));
    await tester.pumpAndSettle();
    expect(find.text('SCHEDULED Pichincha'), findsOneWidget);
  });

  testWidgets('a future-dated movement continues in the scheduling form (COU-151)', (tester) async {
    final wallet = walletFixture(id: 4, name: 'Pichincha');
    when(() => wallets.getById(4)).thenAnswer((_) async => wallet);
    await pumpDetail(tester, wallet);
    await tester.tap(find.byKey(const ValueKey('transaction-new')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('FUTURE DATE'));
    await tester.pumpAndSettle();
    expect(find.text('SCHEDULE Matrícula'), findsOneWidget);
  });

  group('family (F07)', () {
    testWidgets('«Familia» and the «Miembros» action open the members (COU-92)', (tester) async {
      final wallet = walletFixture(id: 4, name: 'Pichincha', memberCount: 2);
      when(() => wallets.getById(4)).thenAnswer((_) async => wallet);
      await pumpDetail(tester, wallet);
      expect(find.bySemanticsLabel('Familia: Compartida con 2 miembros'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('wallet-members')));
      await tester.pumpAndSettle();
      expect(find.text('MEMBERS Pichincha'), findsOneWidget);

      tester.state<NavigatorState>(find.byType(Navigator).last).pop();
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Acciones'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Miembros'));
      await tester.pumpAndSettle();
      expect(find.text('MEMBERS Pichincha'), findsOneWidget);
    });

    testWidgets('member side: who owns it', (tester) async {
      final wallet = walletFixture(id: 4, isOwner: false, ownerName: 'Luis Andrade', memberCount: 1);
      when(() => wallets.getById(4)).thenAnswer((_) async => wallet);
      await pumpDetail(tester, wallet);
      expect(find.text('De Luis Andrade · 1 miembro'), findsOneWidget);
    });

    testWidgets('the author filter of a shared wallet offers its current members (COU-234 gap)', (tester) async {
      final wallet = walletFixture(id: 4, memberCount: 1);
      when(() => wallets.getById(4)).thenAnswer((_) async => wallet);
      when(() => families.membersOf(4)).thenAnswer(
        (_) async => [
          ownerFixture(),
          memberFixture(),
          memberFixture(userId: 'u3', displayName: 'Invitada', status: FamilyStatus.pending),
        ],
      );
      await pumpDetail(tester, wallet);
      await tester.tap(find.byKey(const ValueKey('transaction-filters')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cualquier miembro'));
      await tester.pumpAndSettle();
      expect(find.text('María Quishpe').last, findsOneWidget);
      expect(find.text('Luis Andrade').last, findsOneWidget);
      expect(find.text('Invitada'), findsNothing, reason: 'pending invitees have no movements');
      verify(() => families.membersOf(4)).called(1);
    });

    testWidgets('a personal wallet never asks for members', (tester) async {
      final wallet = walletFixture(id: 4);
      when(() => wallets.getById(4)).thenAnswer((_) async => wallet);
      await pumpDetail(tester, wallet);
      await tester.tap(find.byKey(const ValueKey('transaction-filters')));
      await tester.pumpAndSettle();
      expect(find.text('Registrado por'), findsNothing);
      verifyNever(() => families.membersOf(any()));
    });
  });
}
