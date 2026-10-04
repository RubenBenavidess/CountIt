import 'package:bloc_test/bloc_test.dart';
import 'package:countit_app/app/errors/app_failure.dart';
import 'package:countit_app/app/router/app_router.dart';
import 'package:countit_app/app/session/session_cubit.dart';
import 'package:countit_app/data/dtos/budget.dart';
import 'package:countit_app/data/dtos/profile.dart';
import 'package:countit_app/data/dtos/scheduled_transaction.dart';
import 'package:countit_app/data/dtos/transaction.dart';
import 'package:countit_app/presentation/budgets/view/widgets/budget_selector_field.dart';
import 'package:countit_app/presentation/transactions/cubit/transaction_form_cubit.dart';
import 'package:countit_app/presentation/transactions/view/transaction_form_page.dart';
import 'package:countit_app/shared/state/submit_cubit.dart';
import 'package:countit_app/shared/utils/dates.dart';
import 'package:countit_app/shared/widgets/app_banner.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';

import '../../helpers/budget_fixtures.dart';
import '../../helpers/date_picker.dart';
import '../../helpers/mocks.dart';
import '../../helpers/pump_app.dart';
import '../../helpers/transaction_fixtures.dart';

const _profile = Profile(
  userId: 'u1',
  username: 'mariaq',
  email: 'maria@correo.ec',
  firstName: 'María',
  role: UserRole.user,
  timezone: 'America/Guayaquil',
  plan: UserPlan(planId: 1, name: 'Regular', limits: {'max_daily_transactions': 15}),
);

AppFailure _failure(String key, String message, {int status = 400, FailureKind kind = FailureKind.validation}) =>
    AppFailure(kind: kind, message: message, key: key, status: status);

final _invalidAmount = _failure('invalid_amount', 'El monto admite como máximo 2 decimales');
final _futureDate = _failure('future_date', 'Para fechas futuras programa la transacción');
final _typeMismatch = _failure(
  'budget_type_mismatch',
  'Este presupuesto es de gastos: solo admite transacciones de gasto',
);
final _dailyQuota = _failure(
  'daily_transaction_limit_exceeded',
  'Alcanzaste el límite de 15 transacciones por día de tu plan',
  status: 409,
  kind: FailureKind.conflict,
);
final _notFound = _failure(
  'transaction_not_found',
  'Transacción no encontrada',
  status: 404,
  kind: FailureKind.notFound,
);
const _network = AppFailure(kind: FailureKind.network, message: 'No hay conexión.');

final _budgets = [
  budgetFixture(id: 1, name: 'Comida'),
  budgetFixture(id: 2, name: 'Transporte'),
  budgetFixture(id: 3, name: 'Sueldo', type: BudgetType.income),
];

void main() {
  late MockTransactionRepository transactions;
  late MockBudgetRepository budgets;
  late MockAuthRepository auth;
  late MockProfileRepository profiles;

  setUpAll(() async {
    await Dates.init();
    registerFallbackValue(
      TransactionInput(name: '', type: TransactionType.expense, amountCents: 0, date: DateTime(2026)),
    );
  });

  setUp(() {
    transactions = MockTransactionRepository();
    budgets = MockBudgetRepository();
    auth = MockAuthRepository();
    profiles = MockProfileRepository();
    when(() => auth.sessionChanges).thenAnswer((_) => const Stream.empty());
    when(() => auth.hasSession).thenReturn(true);
    when(() => profiles.fetchMyProfile()).thenAnswer((_) async => _profile);
    when(() => budgets.listByWallet(4)).thenAnswer((_) async => _budgets);
  });

  DateTime today() => Dates.userToday('America/Guayaquil');

  /// Wallet stand-in with a button that opens the form; returns what it pops.
  Future<List<Object?>> pumpForm(WidgetTester tester, {Transaction? initial}) async {
    tester.view.physicalSize = const Size(420, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final results = <Object?>[];
    final session = SessionCubit(auth: auth, profiles: profiles);
    addTearDown(session.close);
    await session.restore();
    final router = GoRouter(
      initialLocation: AppRoutes.home,
      routes: [
        GoRoute(
          path: AppRoutes.home,
          builder: (context, state) => Scaffold(
            body: TextButton(
              onPressed: () async => results.add(await context.push<Object?>('/form')),
              child: const Text('WALLET'),
            ),
          ),
        ),
        GoRoute(
          path: '/form',
          builder: (context, state) => TransactionFormPage(walletId: 4, initial: initial),
        ),
      ],
    );
    await tester.pumpApp(
      const SizedBox(),
      auth: auth,
      budgets: budgets,
      transactions: transactions,
      session: session,
      router: router,
    );
    await tester.tap(find.text('WALLET'));
    await tester.pumpAndSettle();
    return results;
  }

  Finder field(String label) => find.descendant(
    of: find.ancestor(of: find.text(label), matching: find.byType(Column)).first,
    matching: find.byType(EditableText),
  );

  Future<void> tapButton(WidgetTester tester, String label) async {
    final button = find.widgetWithText(FilledButton, label);
    await tester.ensureVisible(button);
    await tester.pumpAndSettle();
    await tester.tap(button);
    await tester.pumpAndSettle();
  }

  Future<void> fill(WidgetTester tester, {String name = 'Almuerzo', String amount = '12,5'}) async {
    await tester.enterText(field('Descripción'), name);
    await tester.enterText(field('Monto'), amount);
    await tester.pumpAndSettle();
  }

  Future<void> pickBudget(WidgetTester tester, String label) async {
    await tester.tap(find.byType(DropdownButtonFormField<int?>));
    await tester.pumpAndSettle();
    await tester.tap(find.text(label).last);
    await tester.pumpAndSettle();
  }

  List<String> budgetOptions(WidgetTester tester) => tester
      .widget<DropdownButton<int?>>(find.byType(DropdownButton<int?>))
      .items!
      .map((item) => (item.child as Text).data!)
      .toList();

  group('TransactionValidators (COU-237)', () {
    test('name: required and at most 100', () {
      expect(TransactionValidators.name(' '), 'Este campo no puede quedar vacío');
      expect(TransactionValidators.name('a' * 101), 'Máximo de caracteres alcanzado (100) en el nombre');
      expect(TransactionValidators.name('a' * 100), isNull);
    });

    test('amount: > 0, at most 2 decimals, below the API bound', () {
      expect(TransactionValidators.amount(''), 'Este campo no puede quedar vacío');
      expect(TransactionValidators.amount('0'), startsWith('El monto debe ser mayor que 0'));
      expect(TransactionValidators.amount('1,234'), isNull, reason: '«1,234» groups thousands');
      expect(TransactionValidators.amount('abc'), 'Ingresa un monto válido, con hasta 2 decimales');
      expect(TransactionValidators.amount('1000000000000'), startsWith('El monto debe ser mayor que 0'));
      expect(TransactionValidators.amount('12,50'), isNull);
    });

    test('date: never after the user\'s day', () {
      final day = DateTime(2026, 10, 3);
      expect(TransactionValidators.date(day, today: day), isNull);
      expect(
        TransactionValidators.date(DateTime(2026, 10, 4), today: day),
        'Para fechas futuras programa la transacción',
      );
    });
  });

  group('BudgetSelectorField (COU-236)', () {
    test('«Sin presupuesto» first, then only the budgets of the same type', () {
      final expense = BudgetSelectorField.optionsFor(_budgets, BudgetType.expense);
      expect(expense.map((o) => o.label), ['Sin presupuesto', 'Comida', 'Transporte']);
      expect(expense.first.value, isNull);
      final income = BudgetSelectorField.optionsFor(_budgets, BudgetType.income);
      expect(income.map((o) => o.label), ['Sin presupuesto', 'Sueldo']);
    });

    test('a deleted budget of the edited transaction is still offered', () {
      final options = BudgetSelectorField.optionsFor(_budgets, BudgetType.expense, retired: (id: 9, name: 'Viaje'));
      expect(options.last.label, 'Viaje (eliminado)');
      expect(options.last.value, 9);
    });
  });

  group('TransactionFormCubit', () {
    final input = TransactionInput(name: 'Taxi', type: TransactionType.expense, amountCents: 300, date: DateTime(2026));

    blocTest<TransactionFormCubit, SubmitState>(
      'creates in its wallet',
      setUp: () => when(() => transactions.create(4, input)).thenAnswer((_) async => 1),
      build: () => TransactionFormCubit(transactions, walletId: 4),
      act: (cubit) => cubit.save(input),
      expect: () => [
        const SubmitState(status: SubmitStatus.submitting),
        const SubmitState(status: SubmitStatus.success),
      ],
    );

    blocTest<TransactionFormCubit, SubmitState>(
      'updates when editing; errors are kept for the view',
      setUp: () => when(() => transactions.update(7, input)).thenThrow(_network),
      build: () => TransactionFormCubit(transactions, walletId: 4, transactionId: 7),
      act: (cubit) => cubit.save(input),
      expect: () => [
        const SubmitState(status: SubmitStatus.submitting),
        const SubmitState(status: SubmitStatus.failure, failure: _network),
      ],
    );
  });

  group('register (COU-237, COU-238)', () {
    testWidgets('defaults: expense, today, «Sin presupuesto»; sends every field and pops true', (tester) async {
      when(() => transactions.create(any(), any())).thenAnswer((_) async => 30);
      final results = await pumpForm(tester);
      expect(find.text('Nuevo movimiento'), findsOneWidget);
      expect(find.text(Dates.date(today())), findsOneWidget);
      expect(find.text('Sin presupuesto'), findsOneWidget);

      await fill(tester, name: '  Almuerzo ');
      await pickBudget(tester, 'Comida');
      await tapButton(tester, 'Registrar movimiento');

      verify(
        () => transactions.create(
          4,
          TransactionInput(
            name: 'Almuerzo',
            type: TransactionType.expense,
            amountCents: 1250,
            date: today(),
            budgetId: 1,
          ),
        ),
      ).called(1);
      expect(results, [true]);
      expect(find.text('Registramos «Almuerzo»'), findsOneWidget);
    });

    testWidgets('validations stop the request: empty name, missing or zero amount', (tester) async {
      await pumpForm(tester);
      await tapButton(tester, 'Registrar movimiento');
      expect(find.text('Este campo no puede quedar vacío'), findsNWidgets(2));
      await tester.enterText(field('Monto'), '0');
      await tester.pumpAndSettle();
      expect(find.textContaining('El monto debe ser mayor que 0'), findsOneWidget);
      verifyNever(() => transactions.create(any(), any()));
    });

    testWidgets('the amount field accepts at most 2 decimals', (tester) async {
      await pumpForm(tester);
      await tester.enterText(field('Monto'), '12,345');
      await tester.pumpAndSettle();
      expect(find.text('12,345'), findsNothing, reason: 'the third decimal is rejected while typing');
    });

    testWidgets('the amount leads the form, signed by type: «−\$» for expense, «+\$» for income', (tester) async {
      await pumpForm(tester);
      final amount = tester.getRect(find.text('−\$'));
      expect(amount.top, lessThan(tester.getRect(find.widgetWithText(ChoiceChip, 'Gasto')).top));
      expect(amount.top, lessThan(tester.getRect(field('Descripción')).top));
      await tester.tap(find.widgetWithText(ChoiceChip, 'Ingreso'));
      await tester.pumpAndSettle();
      expect(find.text('−\$'), findsNothing);
      expect(find.text('+\$'), findsOneWidget);
    });

    testWidgets('income shows only income budgets; switching type drops a budget of the other type', (tester) async {
      when(() => transactions.create(any(), any())).thenAnswer((_) async => 30);
      await pumpForm(tester);
      expect(budgetOptions(tester), ['Sin presupuesto', 'Comida', 'Transporte']);
      await pickBudget(tester, 'Comida');
      await tester.tap(find.widgetWithText(ChoiceChip, 'Ingreso'));
      await tester.pumpAndSettle();
      expect(budgetOptions(tester), ['Sin presupuesto', 'Sueldo']);

      await fill(tester, name: 'Sueldo');
      await tapButton(tester, 'Registrar movimiento');
      final sent = verify(() => transactions.create(4, captureAny())).captured.single as TransactionInput;
      expect(sent.type, TransactionType.income);
      expect(sent.budgetId, isNull);
    });

    testWidgets('budgets that fail to load still allow «Sin presupuesto»', (tester) async {
      when(() => budgets.listByWallet(4)).thenThrow(_network);
      await pumpForm(tester);
      expect(find.text('No pudimos cargar los presupuestos.'), findsOneWidget);
      expect(budgetOptions(tester), ['Sin presupuesto']);
    });

    for (final (failure, near) in [(_invalidAmount, 'Monto'), (_typeMismatch, 'Presupuesto')]) {
      testWidgets('${failure.key} shows next to «$near», not in the banner', (tester) async {
        when(() => transactions.create(any(), any())).thenThrow(failure);
        await pumpForm(tester);
        await fill(tester);
        await tapButton(tester, 'Registrar movimiento');
        expect(find.text(failure.message), findsOneWidget);
        expect(find.byType(AppBanner), findsNothing);
      });
    }

    testWidgets('future_date from the server: next to «Fecha» plus an offer to schedule (COU-151)', (tester) async {
      when(() => transactions.create(any(), any())).thenThrow(_futureDate);
      final results = await pumpForm(tester);
      await fill(tester);
      await tapButton(tester, 'Registrar movimiento');
      expect(find.text(_futureDate.message), findsOneWidget);
      expect(find.byKey(const ValueKey('transaction-schedule-offer')), findsOneWidget);
      await tester.tap(find.widgetWithText(TextButton, 'Programar movimiento'));
      await tester.pumpAndSettle();
      final draft = results.single! as ScheduledTransactionInput;
      expect(draft.name, 'Almuerzo');
      expect(draft.amountCents, 1250);
      expect(draft.periodicity, Periodicity.oneTime);
    });

    testWidgets('a future date leads to scheduling instead of registering (COU-151)', (tester) async {
      final results = await pumpForm(tester);
      await fill(tester, name: 'Matrícula', amount: '120');
      await pickBudget(tester, 'Comida');
      final future = today().add(const Duration(days: 3));
      await pickDate(tester, 'Fecha', future);
      expect(find.byKey(const ValueKey('transaction-schedule-offer')), findsOneWidget);
      expect(find.text('Para fechas futuras programa la transacción'), findsNothing);
      await tapButton(tester, 'Continuar para programar');
      verifyNever(() => transactions.create(any(), any()));
      final draft = results.single! as ScheduledTransactionInput;
      expect(draft.name, 'Matrícula');
      expect(draft.amountCents, 12000);
      expect(draft.startDate, DateTime(future.year, future.month, future.day));
      expect(draft.budgetId, 1);
    });

    testWidgets('daily quota (409) offers the plans', (tester) async {
      when(() => transactions.create(any(), any())).thenThrow(_dailyQuota);
      await pumpForm(tester);
      await fill(tester);
      await tapButton(tester, 'Registrar movimiento');
      expect(find.text(_dailyQuota.message), findsOneWidget);
      expect(find.text('Entendido'), findsOneWidget);
    });

    testWidgets('other errors show in the banner and the form stays', (tester) async {
      when(() => transactions.create(any(), any())).thenThrow(_network);
      await pumpForm(tester);
      await fill(tester);
      await tapButton(tester, 'Registrar movimiento');
      expect(find.widgetWithText(AppBanner, 'No hay conexión.'), findsOneWidget);
      expect(find.text('Nuevo movimiento'), findsOneWidget);
    });
  });

  group('edit (COU-239)', () {
    final existing = transactionFixture(
      id: 7,
      name: 'Mercado',
      amount: 45.2,
      date: DateTime(2026, 9, 30),
      budgetId: 9,
      budgetName: 'Viaje',
    );

    testWidgets('prefilled; save stays disabled until something changes; sends the full state', (tester) async {
      when(() => transactions.update(any(), any())).thenAnswer((_) async {});
      final results = await pumpForm(tester, initial: existing);
      expect(find.text('Editar movimiento'), findsOneWidget);
      expect(find.text('Mercado'), findsOneWidget);
      expect(find.text('45,20'), findsOneWidget);
      expect(find.text('Viaje (eliminado)'), findsOneWidget, reason: 'its deleted budget is kept');
      final save = find.widgetWithText(FilledButton, 'Guardar cambios');
      expect(tester.widget<FilledButton>(save).onPressed, isNull);

      await tester.enterText(field('Monto'), '50');
      await tester.pumpAndSettle();
      await tapButton(tester, 'Guardar cambios');
      verify(
        () => transactions.update(
          7,
          TransactionInput(
            name: 'Mercado',
            type: TransactionType.expense,
            amountCents: 5000,
            date: DateTime(2026, 9, 30),
            budgetId: 9,
          ),
        ),
      ).called(1);
      expect(results, [true]);
    });

    testWidgets('choosing «Sin presupuesto» sends a null budget', (tester) async {
      when(() => transactions.update(any(), any())).thenAnswer((_) async {});
      await pumpForm(tester, initial: existing);
      await pickBudget(tester, 'Sin presupuesto');
      await tapButton(tester, 'Guardar cambios');
      final sent = verify(() => transactions.update(7, captureAny())).captured.single as TransactionInput;
      expect(sent.budgetId, isNull);
    });

    testWidgets('deleted meanwhile: back to the wallet, which reloads', (tester) async {
      when(() => transactions.update(any(), any())).thenThrow(_notFound);
      final results = await pumpForm(tester, initial: existing);
      await tester.enterText(field('Descripción'), 'Mercado grande');
      await tester.pumpAndSettle();
      await tapButton(tester, 'Guardar cambios');
      expect(results, [true]);
      expect(find.text('Transacción no encontrada'), findsOneWidget);
    });

    testWidgets('leaving with changes asks before discarding', (tester) async {
      final results = await pumpForm(tester, initial: existing);
      await tester.enterText(field('Descripción'), 'Otra cosa');
      await tester.pumpAndSettle();
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('¿Descartar los cambios?'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Descartar'));
      await tester.pumpAndSettle();
      expect(results, [null]);
    });
  });
}
