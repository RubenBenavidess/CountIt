import 'package:bloc_test/bloc_test.dart';
import 'package:countit_app/app/errors/app_failure.dart';
import 'package:countit_app/app/router/app_router.dart';
import 'package:countit_app/app/session/session_cubit.dart';
import 'package:countit_app/data/dtos/budget.dart';
import 'package:countit_app/data/dtos/profile.dart';
import 'package:countit_app/data/remote/api_client.dart';
import 'package:countit_app/presentation/budgets/cubit/budget_delete_cubit.dart';
import 'package:countit_app/presentation/budgets/cubit/budget_form_cubit.dart';
import 'package:countit_app/presentation/budgets/view/budget_form_page.dart';
import 'package:countit_app/shared/state/submit_cubit.dart';
import 'package:countit_app/shared/utils/dates.dart';
import 'package:countit_app/shared/widgets/app_banner.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';

import '../../helpers/budget_fixtures.dart';
import '../../helpers/mocks.dart';
import '../../helpers/pump_app.dart';

const _profile = Profile(
  userId: 'u1',
  username: 'mariaq',
  email: 'maria@correo.ec',
  firstName: 'María',
  role: UserRole.user,
  timezone: 'America/Guayaquil',
  plan: UserPlan(planId: 1, name: 'Regular', limits: {'max_budgets_per_wallet': 3}),
);

AppFailure _failure(String key, String message, {int status = 409, FailureKind kind = FailureKind.conflict}) =>
    AppFailure(kind: kind, message: message, key: key, status: status);

final _nameTaken = _failure('budget_name_taken', 'Ya existe un presupuesto con ese nombre en esta billetera');
final _typeLocked = _failure(
  'budget_type_locked',
  'No puedes cambiar el tipo de un presupuesto que ya tiene movimientos',
);
final _quota = _failure('budget_limit_exceeded', 'Alcanzaste el límite de presupuestos de tu plan');
final _notFound = _failure('budget_not_found', 'Presupuesto no encontrado', status: 404, kind: FailureKind.notFound);
const _network = AppFailure(kind: FailureKind.network, message: 'No hay conexión.');
const _reauthRequired = AppFailure(
  kind: FailureKind.reauthRequired,
  message: 'Confirma tu contraseña para continuar',
  key: 'reauth_required',
  status: 403,
);

void main() {
  late MockBudgetRepository budgets;
  late MockAuthRepository auth;
  late MockProfileRepository profiles;

  setUpAll(() async {
    await Dates.init();
    registerFallbackValue(BudgetInput(name: '', limitCents: 0, startDate: DateTime(2026)));
  });

  setUp(() {
    budgets = MockBudgetRepository();
    auth = MockAuthRepository();
    profiles = MockProfileRepository();
    when(() => auth.sessionChanges).thenAnswer((_) => const Stream.empty());
    when(() => auth.hasSession).thenReturn(true);
    when(() => profiles.fetchMyProfile()).thenAnswer((_) async => _profile);
  });

  DateTime today() => Dates.userToday('America/Guayaquil');

  /// Wallet stand-in with a button that opens the form; returns what it pops.
  Future<List<Object?>> pumpForm(WidgetTester tester, {Budget? initial, bool canDelete = false}) async {
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
          builder: (context, state) => BudgetFormPage(walletId: 4, initial: initial, canDelete: canDelete),
        ),
      ],
    );
    await tester.pumpApp(const SizedBox(), auth: auth, budgets: budgets, session: session, router: router);
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

  Future<void> fillBasics(WidgetTester tester, {String name = 'Comida', String limit = '150,5'}) async {
    await tester.enterText(field('Nombre'), name);
    await tester.enterText(field('Límite'), limit);
    await tester.pumpAndSettle();
  }

  Future<void> tapChip(WidgetTester tester, String label) async {
    await tester.tap(find.widgetWithText(ChoiceChip, label));
    await tester.pumpAndSettle();
  }

  group('BudgetValidators (COU-223)', () {
    test('name: required and at most 50', () {
      expect(BudgetValidators.name('  '), 'Este campo no puede quedar vacío');
      expect(BudgetValidators.name('a' * 51), 'Máximo de caracteres alcanzado (50) en el nombre');
      expect(BudgetValidators.name('Comida'), isNull);
    });

    test('limit: required, positive, 2 decimals and below the API bound', () {
      expect(BudgetValidators.limit(''), 'Este campo no puede quedar vacío');
      expect(BudgetValidators.limit('0'), startsWith('El monto debe ser mayor que 0'));
      expect(BudgetValidators.limit('1000000000000'), startsWith('El monto debe ser mayor que 0'));
      expect(BudgetValidators.limit('abc'), 'Ingresa un monto válido, con hasta 2 decimales');
      expect(BudgetValidators.limit('1234,56'), isNull);
      expect(BudgetValidators.limitCents('1.234,56'), 123456);
      expect(BudgetValidators.limitCents('0'), isNull);
    });

    test('end date only for period none, never before the start', () {
      final start = DateTime(2026, 10, 10);
      expect(BudgetValidators.endDate(BudgetPeriod.monthly, start, null), isNull);
      expect(BudgetValidators.endDate(BudgetPeriod.none, start, null), 'Este campo no puede quedar vacío');
      expect(
        BudgetValidators.endDate(BudgetPeriod.none, start, DateTime(2026, 10, 9)),
        'La fecha de fin no puede ser anterior a la de inicio',
      );
      expect(BudgetValidators.endDate(BudgetPeriod.none, start, start), isNull);
    });
  });

  group('BudgetFormCubit (COU-224, COU-225)', () {
    final input = BudgetInput(name: 'Comida', limitCents: 100, startDate: DateTime(2026, 10));

    blocTest<BudgetFormCubit, SubmitState>(
      'creates in its wallet',
      setUp: () => when(() => budgets.create(4, input)).thenAnswer((_) async => 9),
      build: () => BudgetFormCubit(budgets, walletId: 4),
      act: (cubit) => cubit.save(input),
      expect: () => [
        const SubmitState(status: SubmitStatus.submitting),
        const SubmitState(status: SubmitStatus.success),
      ],
      verify: (_) => verifyNever(() => budgets.update(any(), any())),
    );

    blocTest<BudgetFormCubit, SubmitState>(
      'updates when editing; errors become the failure state',
      setUp: () => when(() => budgets.update(7, input)).thenThrow(_nameTaken),
      build: () => BudgetFormCubit(budgets, walletId: 4, budgetId: 7),
      act: (cubit) => cubit.save(input),
      expect: () => [
        const SubmitState(status: SubmitStatus.submitting),
        SubmitState(status: SubmitStatus.failure, failure: _nameTaken),
      ],
    );
  });

  group('create (COU-221..COU-224, COU-228)', () {
    testWidgets('defaults: expense, monthly from today, no icon, no end date', (tester) async {
      await pumpForm(tester);
      expect(find.text('Nuevo presupuesto'), findsOneWidget);
      expect(tester.widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'Gasto')).selected, isTrue);
      expect(tester.widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'Mensual')).selected, isTrue);
      expect(find.text('Se renueva cada mes, el mismo día de la fecha de inicio.'), findsOneWidget);
      expect(find.text(Dates.date(today())), findsOneWidget);
      expect(find.text('Fecha de fin'), findsNothing);
      expect(find.text('Ícono (opcional) · Sin ícono'), findsOneWidget);
    });

    testWidgets('empty save shows the field errors and sends nothing', (tester) async {
      await pumpForm(tester);
      await tapButton(tester, 'Crear presupuesto');
      expect(find.text('Este campo no puede quedar vacío'), findsNWidgets(2));
      verifyNever(() => budgets.create(any(), any()));
    });

    testWidgets('a zero limit is rejected on the spot', (tester) async {
      await pumpForm(tester);
      await fillBasics(tester, limit: '0');
      expect(find.textContaining('El monto debe ser mayor que 0'), findsOneWidget);
      await tapButton(tester, 'Crear presupuesto');
      verifyNever(() => budgets.create(any(), any()));
    });

    testWidgets('sends every field and pops with true', (tester) async {
      when(() => budgets.create(any(), any())).thenAnswer((_) async => 9);
      final results = await pumpForm(tester);
      await tapChip(tester, 'Ingreso');
      expect(find.text('Meta'), findsOneWidget, reason: 'income budgets have a goal');
      await tester.enterText(field('Nombre'), ' Sueldo ');
      await tester.enterText(field('Meta'), '1200');
      await tapChip(tester, 'Semanal');
      await tester.tap(find.byKey(const ValueKey('budget-icon-salary')));
      await tester.pumpAndSettle();
      expect(find.text('Ícono (opcional) · Sueldo'), findsOneWidget);
      await tapButton(tester, 'Crear presupuesto');
      verify(
        () => budgets.create(
          4,
          BudgetInput(
            name: 'Sueldo',
            limitCents: 120000,
            startDate: today(),
            type: BudgetType.income,
            period: BudgetPeriod.weekly,
            icon: BudgetIcon.salary,
          ),
        ),
      ).called(1);
      expect(results, [true]);
      expect(find.text('Creamos el presupuesto «Sueldo»'), findsOneWidget);
    });

    testWidgets('tapping the selected icon clears it', (tester) async {
      await pumpForm(tester);
      final food = find.byKey(const ValueKey('budget-icon-food'));
      await tester.tap(food);
      await tester.pumpAndSettle();
      expect(find.text('Ícono (opcional) · Comida'), findsOneWidget);
      await tester.tap(food);
      await tester.pumpAndSettle();
      expect(find.text('Ícono (opcional) · Sin ícono'), findsOneWidget);
    });

    testWidgets('without renewal the end date is required', (tester) async {
      await pumpForm(tester);
      await fillBasics(tester);
      await tapChip(tester, 'Sin renovación');
      expect(find.text('Fecha de fin'), findsOneWidget);
      expect(find.text('Cuenta solo los movimientos entre la fecha de inicio y la de fin.'), findsOneWidget);
      final handle = tester.ensureSemantics();
      await tapButton(tester, 'Crear presupuesto');
      expect(find.text('Este campo no puede quedar vacío'), findsOneWidget);
      expect(
        find.bySemanticsLabel('Fecha de fin: Selecciona una fecha. Este campo no puede quedar vacío'),
        findsOneWidget,
        reason: 'screen readers hear the error too',
      );
      verifyNever(() => budgets.create(any(), any()));
      handle.dispose();
    });
  });

  group('server errors (COU-228)', () {
    Future<void> submitWith(WidgetTester tester, AppFailure failure) async {
      when(() => budgets.create(any(), any())).thenThrow(failure);
      await pumpForm(tester);
      await fillBasics(tester);
      await tapButton(tester, 'Crear presupuesto');
    }

    testWidgets('budget_name_taken shows under the name', (tester) async {
      await submitWith(tester, _nameTaken);
      expect(find.text(_nameTaken.message), findsOneWidget);
      expect(find.byType(AppBanner), findsNothing);
    });

    testWidgets('budget_limit_exceeded opens the plan sheet', (tester) async {
      await submitWith(tester, _quota);
      expect(find.text('Alcanzaste el límite de tu plan'), findsOneWidget);
      expect(find.text(_quota.message), findsOneWidget);
    });

    testWidgets('other errors go to the banner and clear when editing', (tester) async {
      await submitWith(tester, _network);
      expect(find.widgetWithText(AppBanner, 'No hay conexión.'), findsOneWidget);
      await tester.enterText(field('Nombre'), 'Comida 2');
      await tester.pumpAndSettle();
      expect(find.byType(AppBanner), findsNothing);
    });
  });

  group('edit (COU-225)', () {
    final budget = budgetFixture(id: 7, limit: 150.5, startDate: DateTime(2026, 9, 1));

    testWidgets('prefilled; save stays disabled until something changes', (tester) async {
      await pumpForm(tester, initial: budget);
      expect(find.text('Editar presupuesto'), findsOneWidget);
      expect(find.text('Comida'), findsWidgets);
      expect(find.text('150,50'), findsOneWidget);
      expect(find.text('1 sept 2026'), findsOneWidget);
      final save = find.widgetWithText(FilledButton, 'Guardar cambios');
      expect(tester.widget<FilledButton>(save).onPressed, isNull);
    });

    testWidgets('sends the full state: clearing the icon sends null', (tester) async {
      when(() => budgets.update(any(), any())).thenAnswer((_) async {});
      final results = await pumpForm(tester, initial: budget);
      await tester.tap(find.byKey(const ValueKey('budget-icon-food')));
      await tester.pumpAndSettle();
      await tapButton(tester, 'Guardar cambios');
      verify(() => budgets.update(7, BudgetInput(name: 'Comida', limitCents: 15050, startDate: DateTime(2026, 9, 1))))
          .called(1);
      expect(results, [true]);
    });

    testWidgets('budget_type_locked shows under the type', (tester) async {
      when(() => budgets.update(any(), any())).thenThrow(_typeLocked);
      await pumpForm(tester, initial: budget);
      await tapChip(tester, 'Ingreso');
      await tapButton(tester, 'Guardar cambios');
      expect(find.text(_typeLocked.message), findsOneWidget);
      expect(find.byType(AppBanner), findsNothing);
    });

    testWidgets('deleted meanwhile: back to the wallet, which reloads', (tester) async {
      when(() => budgets.update(any(), any())).thenThrow(_notFound);
      final results = await pumpForm(tester, initial: budget);
      await tester.enterText(field('Nombre'), 'Comida casa');
      await tapButton(tester, 'Guardar cambios');
      expect(find.text('WALLET'), findsOneWidget);
      expect(find.text('Presupuesto no encontrado'), findsOneWidget);
      expect(results, [true]);
    });

    testWidgets('leaving with changes asks before discarding', (tester) async {
      await pumpForm(tester, initial: budget);
      await tester.enterText(field('Nombre'), 'Otra cosa');
      await tester.pumpAndSettle();
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('¿Descartar los cambios?'), findsOneWidget);
      await tester.tap(find.text('Descartar'));
      await tester.pumpAndSettle();
      expect(find.text('WALLET'), findsOneWidget);
    });
  });

  group('BudgetDeleteCubit (COU-226)', () {
    blocTest<BudgetDeleteCubit, BudgetDeleteState>(
      'deletes once',
      setUp: () => when(() => budgets.delete(7, onReauth: any(named: 'onReauth'))).thenAnswer((_) async {}),
      build: () => BudgetDeleteCubit(budgets, budgetId: 7),
      act: (cubit) => Future.wait([cubit.delete(), cubit.delete()]),
      expect: () => [
        const BudgetDeleteState(status: BudgetDeleteStatus.deleting),
        const BudgetDeleteState(status: BudgetDeleteStatus.deleted),
      ],
      verify: (_) => verify(() => budgets.delete(7, onReauth: any(named: 'onReauth'))).called(1),
    );

    blocTest<BudgetDeleteCubit, BudgetDeleteState>(
      'reauth cancelled: back to idle without a failure',
      setUp: () => when(() => budgets.delete(7, onReauth: any(named: 'onReauth'))).thenThrow(_reauthRequired),
      build: () => BudgetDeleteCubit(budgets, budgetId: 7),
      act: (cubit) => cubit.delete(),
      expect: () => [const BudgetDeleteState(status: BudgetDeleteStatus.deleting), const BudgetDeleteState()],
    );
  });

  group('delete with reauthentication (COU-226, COU-229)', () {
    final budget = budgetFixture(id: 7, name: 'Mercado');

    /// Behaves like [ApiClient.run]: on reauth_required asks [onReauth] and retries once.
    void deleteNeedsReauth({required List<int> calls}) {
      when(() => budgets.delete(7, onReauth: any(named: 'onReauth'))).thenAnswer((invocation) async {
        calls.add(7);
        if (calls.length > 1) return;
        final prompt = invocation.namedArguments[#onReauth] as ReauthPrompt?;
        if (prompt == null || !await prompt()) throw _reauthRequired;
        calls.add(7);
      });
    }

    /// Taps «Eliminar presupuesto» and confirms the dialog. Pumps frames
    /// instead of settling: the button spins while the password sheet is open.
    Future<void> confirmDelete(WidgetTester tester) async {
      await tapButton(tester, 'Eliminar presupuesto');
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

    testWidgets('hidden for whoever may not delete (only owner or author)', (tester) async {
      await pumpForm(tester, initial: budget);
      expect(find.text('Eliminar presupuesto'), findsNothing);
    });

    testWidgets('reauth_required: asks for the password, retries and returns to the wallet', (tester) async {
      final calls = <int>[];
      deleteNeedsReauth(calls: calls);
      when(() => auth.reauthenticate('Quito2026')).thenAnswer((_) async => DateTime(2026, 10, 3, 12, 5));
      final results = await pumpForm(tester, initial: budget, canDelete: true);
      await confirmDelete(tester);
      expect(find.text('Confirma que eres tú'), findsOneWidget);
      expect(find.textContaining('Para eliminar «Mercado» escribe tu contraseña'), findsOneWidget);

      await tester.enterText(find.byType(EditableText).last, 'Quito2026');
      await tapInSheet(tester, 'Eliminar presupuesto');
      await tester.pumpAndSettle();
      verify(() => auth.reauthenticate('Quito2026')).called(1);
      expect(calls, [7, 7], reason: 'first attempt plus the retry');
      expect(find.text('WALLET'), findsOneWidget);
      expect(find.text('Eliminamos «Mercado»'), findsOneWidget);
      expect(results, [true]);
    });

    testWidgets('cancelling the password sheet deletes nothing and shows no error', (tester) async {
      final calls = <int>[];
      deleteNeedsReauth(calls: calls);
      await pumpForm(tester, initial: budget, canDelete: true);
      await confirmDelete(tester);
      await tapInSheet(tester, 'Cancelar');
      await tester.pumpAndSettle();
      expect(calls, [7], reason: 'no retry');
      expect(find.text('Editar presupuesto'), findsOneWidget);
      expect(find.byType(SnackBar), findsNothing);
      verifyNever(() => auth.reauthenticate(any()));
    });

    testWidgets('cancelling the confirmation does not call the API', (tester) async {
      await pumpForm(tester, initial: budget, canDelete: true);
      await tapButton(tester, 'Eliminar presupuesto');
      await tester.tap(find.widgetWithText(FilledButton, 'Cancelar'));
      await tester.pumpAndSettle();
      verifyNever(() => budgets.delete(any(), onReauth: any(named: 'onReauth')));
    });

    testWidgets('404 on delete: treated as already deleted', (tester) async {
      when(() => budgets.delete(7, onReauth: any(named: 'onReauth'))).thenThrow(_notFound);
      final results = await pumpForm(tester, initial: budget, canDelete: true);
      await confirmDelete(tester);
      await tester.pumpAndSettle();
      expect(find.text('WALLET'), findsOneWidget);
      expect(results, [true]);
    });

    testWidgets('other errors stay on the form with the message', (tester) async {
      when(() => budgets.delete(7, onReauth: any(named: 'onReauth'))).thenThrow(_network);
      await pumpForm(tester, initial: budget, canDelete: true);
      await confirmDelete(tester);
      await tester.pumpAndSettle();
      expect(find.text('Editar presupuesto'), findsOneWidget);
      expect(find.text('No hay conexión.'), findsOneWidget);
    });
  });
}
