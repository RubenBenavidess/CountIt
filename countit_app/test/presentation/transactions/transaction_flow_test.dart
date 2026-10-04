import 'package:countit_app/app/errors/app_failure.dart';
import 'package:countit_app/app/router/app_router.dart';
import 'package:countit_app/app/session/session_cubit.dart';
import 'package:countit_app/data/dtos/budget.dart';
import 'package:countit_app/data/dtos/profile.dart';
import 'package:countit_app/data/dtos/transaction.dart';
import 'package:countit_app/data/dtos/wallet.dart';
import 'package:countit_app/data/remote/api_client.dart';
import 'package:countit_app/data/repositories/budget_repository.dart';
import 'package:countit_app/data/repositories/transaction_repository.dart';
import 'package:countit_app/data/repositories/wallet_repository.dart';
import 'package:countit_app/shared/utils/dates.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../../helpers/budget_fixtures.dart';
import '../../helpers/mocks.dart';
import '../../helpers/pump_app.dart';
import '../../helpers/wallet_fixtures.dart';

/// COU-245: wallet, budget and transaction working together through the real
/// router and screens, over an in-memory backend that keeps the balance and
/// the budget's spending consistent like the database triggers do.

const _profile = Profile(
  userId: 'u1',
  username: 'mariaq',
  email: 'maria@correo.ec',
  firstName: 'María',
  role: UserRole.user,
  timezone: 'America/Guayaquil',
);

const _reauthRequired = AppFailure(
  kind: FailureKind.reauthRequired,
  message: 'Confirma tu contraseña para continuar',
  key: 'reauth_required',
  status: 403,
);

class _Backend {
  final rows = <Transaction>[];
  var nextId = 1;
  var reauthGranted = false;

  int sum(bool Function(Transaction t) test) => rows.where(test).fold(0, (total, t) => total + t.amountCents);
}

class _Wallets implements WalletRepository {
  _Wallets(this._db);

  final _Backend _db;

  Wallet _wallet() {
    final income = _db.sum((t) => t.isIncome) / 100;
    final expenses = _db.sum((t) => !t.isIncome) / 100;
    return walletFixture(
      id: 4,
      name: 'Hogar',
      initialBalance: 100,
      balance: 100 + income - expenses,
      totalIncome: income,
      totalExpenses: expenses,
      monthIncome: income,
      monthExpenses: expenses,
    );
  }

  @override
  Future<List<Wallet>> list() async => [_wallet()];

  @override
  Future<Wallet> getById(int walletId) async => _wallet();

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

class _Budgets implements BudgetRepository {
  _Budgets(this._db);

  final _Backend _db;

  @override
  Future<List<Budget>> listByWallet(int walletId) async => [
    budgetFixture(id: 1, walletId: 4, name: 'Comida', limit: 100, spent: _db.sum((t) => t.budgetId == 1) / 100),
  ];

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

class _Transactions implements TransactionRepository {
  _Transactions(this._db);

  final _Backend _db;

  @override
  Future<TransactionPage> list(
    int walletId, {
    TransactionFilter filter = const TransactionFilter(),
    TransactionCursor? after,
    int limit = TransactionRepository.pageSize,
  }) async => TransactionPage(_db.rows.reversed.toList());

  @override
  Future<int> create(int walletId, TransactionInput input) async {
    final id = _db.nextId++;
    _db.rows.add(
      Transaction(
        transactionId: id,
        walletId: walletId,
        name: input.name,
        type: input.type,
        amountCents: input.amountCents,
        date: input.date,
        budgetId: input.budgetId,
        budgetName: input.budgetId == 1 ? 'Comida' : null,
        userId: 'u1',
        authorName: 'María',
      ),
    );
    return id;
  }

  /// Like the API in safe mode: `reauth_required` until the password is
  /// confirmed, retried once by `ApiClient.run`.
  @override
  Future<void> delete(int transactionId, {ReauthPrompt? onReauth}) async {
    if (!_db.reauthGranted) {
      if (onReauth == null || !await onReauth()) throw _reauthRequired;
      _db.reauthGranted = true;
    }
    _db.rows.removeWhere((t) => t.transactionId == transactionId);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

void main() {
  setUpAll(Dates.init);

  testWidgets('register a movement with a budget, then delete it with the password', (tester) async {
    tester.view.physicalSize = const Size(420, 2600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final db = _Backend();
    final auth = MockAuthRepository();
    final profiles = MockProfileRepository();
    when(() => auth.sessionChanges).thenAnswer((_) => const Stream.empty());
    when(() => auth.hasSession).thenReturn(true);
    when(() => auth.reauthenticate('Quito2026')).thenAnswer((_) async => DateTime(2026, 10, 3, 12, 5));
    when(() => profiles.fetchMyProfile()).thenAnswer((_) async => _profile);
    final session = SessionCubit(auth: auth, profiles: profiles);
    addTearDown(session.close);
    await session.restore();
    final router = buildRouter(session: session, config: testConfig);
    addTearDown(router.dispose);

    await tester.pumpApp(
      const SizedBox(),
      auth: auth,
      profiles: profiles,
      wallets: _Wallets(db),
      budgets: _Budgets(db),
      transactions: _Transactions(db),
      session: session,
      router: router,
    );
    await tester.pumpAndSettle();

    // Home → wallet: empty wallet with its budget.
    await tester.tap(find.text('Hogar').first);
    await tester.pumpAndSettle();
    expect(find.text(r'$0,00 de $100,00'), findsOneWidget);
    expect(find.textContaining('Aún no hay movimientos'), findsOneWidget);

    // Register an expense in «Comida».
    await tester.tap(find.byKey(const ValueKey('transaction-new')));
    await tester.pumpAndSettle();
    Finder field(String label) => find.descendant(
      of: find.ancestor(of: find.text(label), matching: find.byType(Column)).first,
      matching: find.byType(EditableText),
    );
    await tester.enterText(field('Descripción'), 'Almuerzo');
    await tester.enterText(field('Monto'), '12,5');
    await tester.tap(find.byType(DropdownButtonFormField<int?>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Comida').last);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Registrar movimiento'));
    await tester.pumpAndSettle();

    // Back on the wallet: balance, budget and list reflect it.
    expect(find.text(r'$87,50'), findsWidgets);
    expect(find.text(r'$12,50 de $100,00'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Almuerzo'), 300);
    expect(find.text('Comida · María'), findsNothing, reason: 'personal wallet: no author line');
    expect(find.text('− \$12,50'), findsWidgets);

    // Detail → delete → password → back to the restored wallet.
    await tester.tap(find.text('Almuerzo'));
    await tester.pumpAndSettle();
    expect(find.text('Comida'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Eliminar movimiento'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Eliminar'));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.text('Confirma que eres tú'), findsOneWidget);
    await tester.enterText(find.byType(EditableText), 'Quito2026');
    await tester.tap(find.widgetWithText(FilledButton, 'Eliminar movimiento').last);
    await tester.pumpAndSettle();

    expect(db.rows, isEmpty);
    expect(find.text('Eliminamos «Almuerzo»'), findsOneWidget);
    expect(find.text('Almuerzo'), findsNothing);
    expect(find.text(r'$0,00 de $100,00'), findsOneWidget);
    expect(find.text(r'$100,00'), findsWidgets);
  });
}
