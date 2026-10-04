import 'package:bloc_test/bloc_test.dart';
import 'package:countit_app/app/errors/app_failure.dart';
import 'package:countit_app/app/router/app_router.dart';
import 'package:countit_app/app/session/session_cubit.dart';
import 'package:countit_app/data/dtos/budget.dart';
import 'package:countit_app/data/dtos/profile.dart';
import 'package:countit_app/data/dtos/scheduled_transaction.dart';
import 'package:countit_app/data/dtos/transaction.dart';
import 'package:countit_app/presentation/scheduled/cubit/scheduled_form_cubit.dart';
import 'package:countit_app/presentation/scheduled/view/scheduled_form_page.dart';
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
import '../../helpers/scheduled_fixtures.dart';

const _profile = Profile(
  userId: 'u1',
  username: 'mariaq',
  email: 'maria@correo.ec',
  role: UserRole.user,
  timezone: 'America/Guayaquil',
  plan: UserPlan(planId: 1, name: 'Regular', limits: {'max_scheduled_transactions': 3}),
);

AppFailure _failure(String key, String message, {int status = 400, FailureKind kind = FailureKind.validation}) =>
    AppFailure(kind: kind, message: message, key: key, status: status);

final _quota = _failure(
  'scheduled_transaction_limit_exceeded',
  'Alcanzaste el límite de 3 transacciones programadas de tu plan',
  status: 409,
  kind: FailureKind.conflict,
);
final _notFound = _failure(
  'scheduled_transaction_not_found',
  'Transacción programada no encontrada',
  status: 404,
  kind: FailureKind.notFound,
);
const _network = AppFailure(kind: FailureKind.network, message: 'No hay conexión.');

final _budgets = [
  budgetFixture(id: 1, name: 'Vivienda'),
  budgetFixture(id: 3, name: 'Sueldo', type: BudgetType.income),
];

void main() {
  late MockScheduledTransactionRepository scheduled;
  late MockBudgetRepository budgets;
  late MockAuthRepository auth;
  late MockProfileRepository profiles;

  setUpAll(() async {
    await Dates.init();
    registerFallbackValue(
      ScheduledTransactionInput(name: '', type: TransactionType.expense, amountCents: 0, startDate: DateTime(2026)),
    );
  });

  setUp(() {
    scheduled = MockScheduledTransactionRepository();
    budgets = MockBudgetRepository();
    auth = MockAuthRepository();
    profiles = MockProfileRepository();
    when(() => auth.sessionChanges).thenAnswer((_) => const Stream.empty());
    when(() => auth.hasSession).thenReturn(true);
    when(() => profiles.fetchMyProfile()).thenAnswer((_) async => _profile);
    when(() => budgets.listByWallet(4)).thenAnswer((_) async => _budgets);
  });

  DateTime today() => Dates.userToday('America/Guayaquil');
  DateTime inDays(int days) {
    final t = today();
    return DateTime(t.year, t.month, t.day + days);
  }

  group('ScheduledValidators (COU-89)', () {
    test('start strictly after the user\'s day', () {
      final day = DateTime(2026, 10, 4);
      expect(ScheduledValidators.startDate(day, today: day), 'La fecha programada debe ser posterior a hoy');
      expect(ScheduledValidators.startDate(DateTime(2026, 10, 5), today: day), isNull);
    });

    test('interval: whole number from 1 to 365', () {
      expect(ScheduledValidators.interval(''), 'Este campo no puede quedar vacío');
      expect(ScheduledValidators.interval('0'), 'El intervalo debe estar entre 1 y 365');
      expect(ScheduledValidators.interval('366'), 'El intervalo debe estar entre 1 y 365');
      expect(ScheduledValidators.interval('15'), isNull);
    });

    test('end: optional, never before the start nor the kept next run', () {
      final start = DateTime(2026, 11, 1);
      expect(ScheduledValidators.endDate(Periodicity.months, start: start, end: null), isNull);
      expect(
        ScheduledValidators.endDate(Periodicity.months, start: start, end: DateTime(2026, 10, 31)),
        'La fecha de fin no puede ser anterior a la de inicio',
      );
      expect(
        ScheduledValidators.endDate(
          Periodicity.months,
          start: start,
          end: DateTime(2026, 11, 20),
          nextRun: DateTime(2026, 12, 1),
        ),
        'La fecha de fin no puede ser anterior a la próxima ejecución (01/12/2026)',
      );
      expect(
        ScheduledValidators.endDate(Periodicity.oneTime, start: start, end: DateTime(2020)),
        isNull,
        reason: 'one-time rules have no end',
      );
    });

    test('a started recurring rule cannot become one-time', () {
      final day = DateTime(2026, 10, 4);
      expect(ScheduledValidators.canBecomeOneTime(null, today: day), isTrue);
      expect(
        ScheduledValidators.canBecomeOneTime(scheduledFixture(startDate: DateTime(2026, 9, 1)), today: day),
        isFalse,
      );
      expect(
        ScheduledValidators.canBecomeOneTime(scheduledFixture(startDate: DateTime(2026, 11, 1)), today: day),
        isTrue,
      );
    });
  });

  group('ScheduledFormCubit (COU-151, COU-152)', () {
    final input = ScheduledTransactionInput(
      name: 'Arriendo',
      type: TransactionType.expense,
      amountCents: 30000,
      startDate: DateTime(2026, 11, 5),
      periodicity: Periodicity.months,
    );

    blocTest<ScheduledFormCubit, SubmitState>(
      'create: submitting → success and keeps the saved rule',
      setUp: () => when(() => scheduled.create(4, input)).thenAnswer((_) async => scheduledFixture(id: 9)),
      build: () => ScheduledFormCubit(scheduled, walletId: 4),
      act: (cubit) => cubit.save(input),
      expect: () => [
        const SubmitState(status: SubmitStatus.submitting),
        const SubmitState(status: SubmitStatus.success),
      ],
      verify: (cubit) => expect(cubit.saved?.scheduledTransactionId, 9),
    );

    blocTest<ScheduledFormCubit, SubmitState>(
      'edit: update with the rule id; failures are kept for the form',
      setUp: () => when(() => scheduled.update(9, input)).thenThrow(_quota),
      build: () => ScheduledFormCubit(scheduled, walletId: 4, scheduledTransactionId: 9),
      act: (cubit) => cubit.save(input),
      expect: () => [
        const SubmitState(status: SubmitStatus.submitting),
        SubmitState(status: SubmitStatus.failure, failure: _quota),
      ],
    );
  });

  group('ScheduledFormPage', () {
    Future<List<Object?>> pumpForm(
      WidgetTester tester, {
      ScheduledTransaction? initial,
      ScheduledTransactionInput? draft,
    }) async {
      tester.view.physicalSize = const Size(420, 2600);
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
                child: const Text('LIST'),
              ),
            ),
          ),
          GoRoute(
            path: '/form',
            builder: (context, state) => ScheduledFormPage(walletId: 4, initial: initial, draft: draft),
          ),
        ],
      );
      await tester.pumpApp(
        const SizedBox(),
        auth: auth,
        budgets: budgets,
        scheduled: scheduled,
        session: session,
        router: router,
      );
      await tester.tap(find.text('LIST'));
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

    Future<void> chip(WidgetTester tester, Periodicity periodicity) async {
      final finder = find.byKey(ValueKey('choice-$periodicity'));
      await tester.ensureVisible(finder);
      await tester.tap(finder);
      await tester.pumpAndSettle();
    }

    testWidgets('create: one-time by default, starting tomorrow, sends every field', (tester) async {
      when(() => scheduled.create(any(), any())).thenAnswer((_) async => scheduledFixture(nextRunDate: inDays(1)));
      final results = await pumpForm(tester);
      expect(find.text('Programar movimiento'), findsWidgets);
      await tester.enterText(field('Descripción'), 'Matrícula');
      await tester.enterText(field('Monto'), '120');
      await tester.pumpAndSettle();
      expect(find.textContaining('Se registrará una sola vez'), findsOneWidget);
      expect(find.byKey(const ValueKey('scheduled-interval')), findsNothing, reason: 'no interval for one-time');
      expect(find.byKey(const ValueKey('scheduled-end')), findsNothing);
      await tapButton(tester, 'Programar movimiento');
      final sent = verify(() => scheduled.create(4, captureAny())).captured.single as ScheduledTransactionInput;
      expect(sent.name, 'Matrícula');
      expect(sent.amountCents, 12000);
      expect(sent.periodicity, Periodicity.oneTime);
      expect(sent.startDate, inDays(1));
      expect(results, [true]);
    });

    testWidgets('recurring: interval and optional end, validated before sending', (tester) async {
      when(() => scheduled.create(any(), any())).thenAnswer((_) async => scheduledFixture());
      await pumpForm(tester);
      await tester.enterText(field('Descripción'), 'Netflix');
      await tester.enterText(field('Monto'), '10,99');
      await chip(tester, Periodicity.weeks);
      expect(find.byKey(const ValueKey('scheduled-interval')), findsOneWidget);
      await tester.enterText(
        find.descendant(of: find.byKey(const ValueKey('scheduled-interval')), matching: find.byType(EditableText)),
        '0',
      );
      await tapButton(tester, 'Programar movimiento');
      expect(find.text('El intervalo debe estar entre 1 y 365'), findsOneWidget);
      verifyNever(() => scheduled.create(any(), any()));

      await tester.enterText(
        find.descendant(of: find.byKey(const ValueKey('scheduled-interval')), matching: find.byType(EditableText)),
        '2',
      );
      await tester.pumpAndSettle();
      expect(find.text('semanas'), findsOneWidget);
      final end = inDays(60);
      await pickDate(tester, 'Fecha de fin \\(opcional\\)', end);
      expect(find.textContaining('Se registrará cada 2 semanas'), findsOneWidget);
      await tapButton(tester, 'Programar movimiento');
      final sent = verify(() => scheduled.create(4, captureAny())).captured.single as ScheduledTransactionInput;
      expect(sent.periodicity, Periodicity.weeks);
      expect(sent.interval, 2);
      expect(sent.endDate, end);
    });

    testWidgets('required fields and amount are checked locally', (tester) async {
      await pumpForm(tester);
      await tapButton(tester, 'Programar movimiento');
      expect(find.text('Este campo no puede quedar vacío'), findsNWidgets(2));
      await tester.enterText(field('Monto'), '1,234');
      await tester.enterText(field('Monto'), '0');
      await tester.pumpAndSettle();
      expect(find.textContaining('El monto debe ser mayor que 0'), findsOneWidget);
      verifyNever(() => scheduled.create(any(), any()));
    });

    testWidgets('a draft from the transaction form pre-fills a one-time rule', (tester) async {
      await pumpForm(
        tester,
        draft: ScheduledTransactionInput(
          name: 'Matrícula',
          type: TransactionType.expense,
          amountCents: 12000,
          startDate: inDays(5),
          budgetId: 1,
        ),
      );
      expect(find.text('Matrícula'), findsOneWidget);
      expect(find.text('120,00'), findsOneWidget);
      expect(find.text('Vivienda'), findsOneWidget);
      expect(find.bySemanticsLabel(RegExp('^Fecha: ${Dates.date(inDays(5))}')), findsOneWidget);
    });

    for (final (key, message, near) in [
      ('invalid_interval', 'El intervalo debe estar entre 1 y 365', 'scheduled-interval'),
      ('invalid_date_range', 'La fecha de fin no puede ser anterior a la de inicio', 'scheduled-end'),
    ]) {
      testWidgets('$key from the server shows next to its field, not in the banner', (tester) async {
        when(() => scheduled.create(any(), any())).thenThrow(_failure(key, message));
        await pumpForm(tester);
        await tester.enterText(field('Descripción'), 'Gym');
        await tester.enterText(field('Monto'), '30');
        await chip(tester, Periodicity.months);
        await tapButton(tester, 'Programar movimiento');
        expect(find.descendant(of: find.byKey(ValueKey(near)), matching: find.text(message)), findsOneWidget);
        expect(find.byType(AppBanner), findsNothing);
      });
    }

    testWidgets('quota (409) offers the plans and keeps the form', (tester) async {
      when(() => scheduled.create(any(), any())).thenThrow(_quota);
      await pumpForm(tester);
      await tester.enterText(field('Descripción'), 'Gym');
      await tester.enterText(field('Monto'), '30');
      await tapButton(tester, 'Programar movimiento');
      expect(find.text(_quota.message), findsOneWidget);
      expect(find.text('Entendido'), findsOneWidget);
    });

    testWidgets('other errors show in the banner', (tester) async {
      when(() => scheduled.create(any(), any())).thenThrow(_network);
      await pumpForm(tester);
      await tester.enterText(field('Descripción'), 'Gym');
      await tester.enterText(field('Monto'), '30');
      await tapButton(tester, 'Programar movimiento');
      expect(find.widgetWithText(AppBanner, 'No hay conexión.'), findsOneWidget);
    });

    group('edit (COU-152)', () {
      late ScheduledTransaction started;
      setUp(
        () => started = scheduledFixture(
          id: 9,
          name: 'Arriendo',
          startDate: DateTime(2026, 1, 5),
          nextRunDate: inDays(10),
          budgetId: 1,
          budgetName: 'Vivienda',
        ),
      );

      testWidgets('start fixed, one-time hidden once started, nothing to save until a change', (tester) async {
        await pumpForm(tester, initial: started);
        expect(find.text('Editar programado'), findsOneWidget);
        expect(find.text('La fecha de inicio no se puede cambiar.'), findsOneWidget);
        expect(find.byKey(ValueKey('choice-${Periodicity.oneTime}')), findsNothing);
        expect(find.textContaining('Próxima ejecución:'), findsOneWidget);
        final button = tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Guardar cambios'));
        expect(button.onPressed, isNull);
      });

      testWidgets('sends the whole rule with update; a new cadence says the next run is recalculated', (tester) async {
        when(() => scheduled.update(any(), any())).thenAnswer((_) async => started);
        final results = await pumpForm(tester, initial: started);
        await tester.enterText(field('Monto'), '320');
        await chip(tester, Periodicity.weeks);
        expect(find.textContaining('se recalcula al guardar'), findsOneWidget);
        await tapButton(tester, 'Guardar cambios');
        final sent = verify(() => scheduled.update(9, captureAny())).captured.single as ScheduledTransactionInput;
        expect(sent.amountCents, 32000);
        expect(sent.periodicity, Periodicity.weeks);
        expect(sent.budgetId, 1, reason: 'the replacement resends the budget');
        expect(results, [true]);
      });

      testWidgets('the end cannot fall before the kept next run', (tester) async {
        await pumpForm(tester, initial: started);
        await pickDate(tester, 'Fecha de fin \\(opcional\\)', inDays(3));
        expect(find.textContaining('anterior a la próxima ejecución'), findsOneWidget);
        await tapButton(tester, 'Guardar cambios');
        verifyNever(() => scheduled.update(any(), any()));
      });

      testWidgets('a rule deleted meanwhile (404) leaves the form', (tester) async {
        when(() => scheduled.update(any(), any())).thenThrow(_notFound);
        final results = await pumpForm(tester, initial: started);
        await tester.enterText(field('Monto'), '320');
        await tapButton(tester, 'Guardar cambios');
        expect(find.text('Transacción programada no encontrada'), findsOneWidget);
        expect(results, [true]);
      });
    });
  });
}
