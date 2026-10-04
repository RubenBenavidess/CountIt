import 'package:bloc_test/bloc_test.dart';
import 'package:countit_app/app/errors/app_failure.dart';
import 'package:countit_app/app/session/session_cubit.dart';
import 'package:countit_app/data/dtos/profile.dart';
import 'package:countit_app/data/dtos/scheduled_transaction.dart';
import 'package:countit_app/data/remote/api_client.dart';
import 'package:countit_app/presentation/scheduled/cubit/scheduled_list_cubit.dart';
import 'package:countit_app/presentation/scheduled/view/scheduled_form_page.dart';
import 'package:countit_app/presentation/scheduled/view/scheduled_list_page.dart';
import 'package:countit_app/presentation/transactions/view/widgets/transaction_tile.dart';
import 'package:countit_app/shared/state/load_state.dart';
import 'package:countit_app/shared/utils/dates.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';

import '../../helpers/mocks.dart';
import '../../helpers/pump_app.dart';
import '../../helpers/scheduled_fixtures.dart';
import '../../helpers/transaction_fixtures.dart';
import '../../helpers/wallet_fixtures.dart';

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
const _reauthRequired = AppFailure(
  kind: FailureKind.reauthRequired,
  message: 'Confirma tu contraseña para continuar',
  key: 'reauth_required',
  status: 403,
);
const _network = AppFailure(kind: FailureKind.network, message: 'No hay conexión.');

const _profile = Profile(
  userId: 'u1',
  username: 'mariaq',
  email: 'maria@correo.ec',
  role: UserRole.user,
  timezone: 'America/Guayaquil',
  plan: UserPlan(planId: 1, name: 'Regular', limits: {'max_scheduled_transactions': 3}),
);

Future<void> pumpFrames(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  late MockScheduledTransactionRepository scheduled;
  late MockAuthRepository auth;
  late MockProfileRepository profiles;
  late MockBudgetRepository budgets;

  setUpAll(Dates.init);

  setUp(() {
    scheduled = MockScheduledTransactionRepository();
    auth = MockAuthRepository();
    profiles = MockProfileRepository();
    budgets = MockBudgetRepository();
    when(() => auth.sessionChanges).thenAnswer((_) => const Stream.empty());
    when(() => auth.hasSession).thenReturn(true);
    when(() => profiles.fetchMyProfile()).thenAnswer((_) async => _profile);
    when(() => budgets.listByWallet(any())).thenAnswer((_) async => const []);
  });

  group('ScheduledListCubit.togglePause (COU-153)', () {
    final running = scheduledFixture(id: 1, name: 'Arriendo', budgetName: 'Vivienda', budgetId: 2);
    final paused = scheduledFixture(id: 2, name: 'Gym', isPaused: true, nextRunDate: DateTime(2026, 10, 10));
    const usage = ScheduledUsage(total: 2, running: 1);
    ScheduledListState seed() => ScheduledListState(rules: LoadState.success([running, paused]), usage: usage);

    blocTest<ScheduledListCubit, ScheduledListState>(
      'pausing: busy, then the paused rule moves last, keeps its names and frees a running slot',
      setUp: () => when(() => scheduled.setPaused(1, paused: true)).thenAnswer(
        (_) async => scheduledFixture(id: 1, name: 'Arriendo', budgetId: 2, isPaused: true, authorName: null),
      ),
      build: () => ScheduledListCubit(scheduled, walletId: 4, userId: 'u1'),
      seed: seed,
      act: (cubit) => cubit.togglePause(running),
      expect: () => [
        isA<ScheduledListState>().having((s) => s.toggling, 'toggling', {1}),
        isA<ScheduledListState>()
            .having((s) => s.toggling, 'toggling', isEmpty)
            .having((s) => s.rules.data!.map((r) => (r.scheduledTransactionId, r.isPaused)), 'rules', [
              (2, true),
              (1, true),
            ])
            .having((s) => s.rules.data!.last.budgetName, 'budget name kept', 'Vivienda')
            .having((s) => s.rules.data!.last.authorName, 'author kept', 'María Quishpe')
            .having((s) => s.usage, 'usage', const ScheduledUsage(total: 2, running: 0))
            .having((s) => s.lastToggle?.outcome, 'outcome', ScheduledToggleOutcome.paused),
      ],
    );

    blocTest<ScheduledListCubit, ScheduledListState>(
      'resuming without a free slot (409): the rule stays paused and the failure is reported',
      setUp: () => when(() => scheduled.setPaused(2, paused: false)).thenThrow(_quota),
      build: () => ScheduledListCubit(scheduled, walletId: 4, userId: 'u1'),
      seed: seed,
      act: (cubit) => cubit.togglePause(paused),
      skip: 1,
      expect: () => [
        isA<ScheduledListState>()
            .having((s) => s.rules.data, 'rules', [running, paused])
            .having((s) => s.lastToggle?.failure, 'failure', _quota)
            .having((s) => s.usage, 'usage', usage),
      ],
    );

    blocTest<ScheduledListCubit, ScheduledListState>(
      'resuming a rule with nothing left to run ends it: it leaves the list',
      setUp: () => when(() => scheduled.setPaused(2, paused: false)).thenAnswer(
        (_) async => ScheduledTransaction.fromJson({
          'scheduled_transaction_id': 2,
          'wallet_id': 4,
          'name': 'Gym',
          'type': 'expense',
          'amount': 30,
          'periodicity': 'one_time',
          'start_date': '2026-10-10',
          'is_active': false,
        }),
      ),
      build: () => ScheduledListCubit(scheduled, walletId: 4, userId: 'u1'),
      seed: seed,
      act: (cubit) => cubit.togglePause(paused),
      skip: 1,
      expect: () => [
        isA<ScheduledListState>()
            .having((s) => s.rules.data, 'rules', [running])
            .having((s) => s.usage, 'usage', const ScheduledUsage(total: 1, running: 1))
            .having((s) => s.lastToggle?.outcome, 'outcome', ScheduledToggleOutcome.ended),
      ],
    );

    blocTest<ScheduledListCubit, ScheduledListState>(
      '404: deleted elsewhere, it leaves the list',
      setUp: () => when(() => scheduled.setPaused(1, paused: true)).thenThrow(_notFound),
      build: () => ScheduledListCubit(scheduled, walletId: 4, userId: 'u1'),
      seed: seed,
      act: (cubit) => cubit.togglePause(running),
      skip: 1,
      expect: () => [
        isA<ScheduledListState>()
            .having((s) => s.rules.data, 'rules', [paused])
            .having((s) => s.lastToggle?.outcome, 'outcome', ScheduledToggleOutcome.missing),
      ],
    );

    blocTest<ScheduledListCubit, ScheduledListState>(
      'a second tap while the first is on its way does nothing',
      setUp: () =>
          when(() => scheduled.setPaused(1, paused: true))
              .thenAnswer((_) async => scheduledFixture(id: 1, isPaused: true)),
      build: () => ScheduledListCubit(scheduled, walletId: 4, userId: 'u1'),
      seed: seed,
      act: (cubit) => Future.wait([cubit.togglePause(running), cubit.togglePause(running)]),
      verify: (_) => verify(() => scheduled.setPaused(1, paused: true)).called(1),
    );

    blocTest<ScheduledListCubit, ScheduledListState>(
      'toggling someone else\'s rule (as wallet owner) leaves the caller\'s usage alone',
      setUp: () =>
          when(() => scheduled.setPaused(3, paused: true))
              .thenAnswer((_) async => scheduledFixture(id: 3, userId: 'u2', isPaused: true)),
      build: () => ScheduledListCubit(scheduled, walletId: 4, userId: 'u1'),
      seed: () => ScheduledListState(
        rules: LoadState.success([scheduledFixture(id: 3, userId: 'u2')]),
        usage: usage,
      ),
      act: (cubit) => cubit.togglePause(scheduledFixture(id: 3, userId: 'u2')),
      skip: 1,
      expect: () => [isA<ScheduledListState>().having((s) => s.usage, 'usage', usage)],
    );
  });

  group('pause and resume in the list (COU-153, COU-156)', () {
    Future<void> pumpList(WidgetTester tester, {bool owner = true}) async {
      tester.view.physicalSize = const Size(420, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final session = SessionCubit(auth: auth, profiles: profiles);
      addTearDown(session.close);
      await session.restore();
      await tester.pumpApp(
        ScheduledListPage(wallet: walletFixture(id: 4, isOwner: owner, memberCount: 1)),
        auth: auth,
        profiles: profiles,
        scheduled: scheduled,
        session: session,
      );
      await tester.pumpAndSettle();
    }

    testWidgets('pausing says so and the row shows «Pausada»', (tester) async {
      when(() => scheduled.listByWallet(4)).thenAnswer((_) async => [scheduledFixture(id: 1, name: 'Arriendo')]);
      when(() => scheduled.usageOf('u1')).thenAnswer((_) async => const ScheduledUsage(total: 1, running: 1));
      when(() => scheduled.setPaused(1, paused: true))
          .thenAnswer((_) async => scheduledFixture(id: 1, name: 'Arriendo', isPaused: true));
      await pumpList(tester);
      expect(find.byTooltip('Pausar «Arriendo»'), findsOneWidget);
      expect(tester.getSize(find.byKey(const ValueKey('scheduled-toggle-1'))).height, greaterThanOrEqualTo(44));
      await tester.tap(find.byKey(const ValueKey('scheduled-toggle-1')));
      await tester.pumpAndSettle();
      expect(find.textContaining('Pausamos «Arriendo»'), findsOneWidget);
      expect(find.text('Pausada'), findsOneWidget);
      expect(find.byTooltip('Reanudar «Arriendo»'), findsOneWidget);
    });

    testWidgets('resuming one\'s own rule with every running slot taken shows the plans, no call', (tester) async {
      when(() => scheduled.listByWallet(4))
          .thenAnswer((_) async => [scheduledFixture(id: 2, name: 'Gym', isPaused: true)]);
      when(() => scheduled.usageOf('u1')).thenAnswer((_) async => const ScheduledUsage(total: 3, running: 3));
      await pumpList(tester);
      await tester.tap(find.byKey(const ValueKey('scheduled-toggle-2')));
      await tester.pumpAndSettle();
      expect(find.textContaining('el máximo de tu plan'), findsOneWidget);
      verifyNever(() => scheduled.setPaused(any(), paused: any(named: 'paused')));
    });

    testWidgets('a 409 from the server also shows the plans', (tester) async {
      when(() => scheduled.listByWallet(4))
          .thenAnswer((_) async => [scheduledFixture(id: 2, name: 'Gym', isPaused: true)]);
      when(() => scheduled.usageOf('u1')).thenThrow(_network);
      when(() => scheduled.setPaused(2, paused: false)).thenThrow(_quota);
      await pumpList(tester);
      await tester.tap(find.byKey(const ValueKey('scheduled-toggle-2')));
      await tester.pumpAndSettle();
      expect(find.text(_quota.message), findsOneWidget);
      expect(find.text('Entendido'), findsOneWidget);
    });

    testWidgets('other members\' rules have no pause button for a member', (tester) async {
      when(() => scheduled.listByWallet(4)).thenAnswer((_) async => [scheduledFixture(id: 5, userId: 'u2')]);
      when(() => scheduled.usageOf('u1')).thenAnswer((_) async => const ScheduledUsage(total: 0, running: 0));
      await pumpList(tester, owner: false);
      expect(find.byKey(const ValueKey('scheduled-toggle-5')), findsNothing);
    });
  });

  group('delete with reauthentication (COU-154)', () {
    final rule = scheduledFixture(id: 9, name: 'Arriendo');

    Future<List<Object?>> pumpForm(WidgetTester tester) async {
      tester.view.physicalSize = const Size(420, 2600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final results = <Object?>[];
      final session = SessionCubit(auth: auth, profiles: profiles);
      addTearDown(session.close);
      await session.restore();
      final router = GoRouter(
        initialLocation: '/',
        routes: [
          GoRoute(
            path: '/',
            builder: (context, state) => Scaffold(
              body: TextButton(
                onPressed: () async => results.add(await context.push<Object?>('/edit')),
                child: const Text('LIST'),
              ),
            ),
          ),
          GoRoute(
            path: '/edit',
            builder: (context, state) => ScheduledFormPage(walletId: 4, initial: rule, canDelete: true),
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

    Future<void> confirmDelete(WidgetTester tester) async {
      final button = find.byKey(const ValueKey('scheduled-delete'));
      await tester.ensureVisible(button);
      await tester.pumpAndSettle();
      await tester.tap(button);
      await tester.pumpAndSettle();
      expect(find.textContaining('Los movimientos que ya generó se conservan'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Eliminar'));
      // Frames instead of settling: the button spins while the password sheet is open.
      await pumpFrames(tester);
    }

    Future<void> tapInSheet(WidgetTester tester, String label) async {
      await tester.tap(find.widgetWithText(FilledButton, label).last);
      await pumpFrames(tester);
    }

    void deleteNeedsReauth(List<int> calls) =>
        when(() => scheduled.delete(9, onReauth: any(named: 'onReauth'))).thenAnswer((invocation) async {
          calls.add(9);
          final prompt = invocation.namedArguments[#onReauth] as ReauthPrompt?;
          if (prompt == null || !await prompt()) throw _reauthRequired;
          calls.add(9);
        });

    testWidgets('reauth_required: asks for the password, retries and leaves', (tester) async {
      final calls = <int>[];
      deleteNeedsReauth(calls);
      when(() => auth.reauthenticate('Quito2026')).thenAnswer((_) async => DateTime(2026, 10, 4, 12, 5));
      final results = await pumpForm(tester);
      await confirmDelete(tester);
      expect(find.text('Confirma que eres tú'), findsOneWidget);
      await tester.enterText(find.byType(EditableText).last, 'Quito2026');
      await tapInSheet(tester, 'Eliminar programado');
      await tester.pumpAndSettle();
      verify(() => auth.reauthenticate('Quito2026')).called(1);
      expect(calls, [9, 9]);
      expect(results, [true]);
      expect(find.text('Eliminamos «Arriendo»'), findsOneWidget);
    });

    testWidgets('cancelling the password sheet deletes nothing and stays', (tester) async {
      final calls = <int>[];
      deleteNeedsReauth(calls);
      final results = await pumpForm(tester);
      await confirmDelete(tester);
      await tapInSheet(tester, 'Cancelar');
      await tester.pumpAndSettle();
      expect(calls, [9]);
      expect(results, isEmpty);
      expect(find.byType(SnackBar), findsNothing);
    });

    testWidgets('cancelling the confirmation does not call the API', (tester) async {
      await pumpForm(tester);
      final button = find.byKey(const ValueKey('scheduled-delete'));
      await tester.ensureVisible(button);
      await tester.pumpAndSettle();
      await tester.tap(button);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Cancelar'));
      await tester.pumpAndSettle();
      verifyNever(() => scheduled.delete(any(), onReauth: any(named: 'onReauth')));
    });

    testWidgets('a network error stays on the form with the message', (tester) async {
      when(() => scheduled.delete(9, onReauth: any(named: 'onReauth'))).thenThrow(_network);
      final results = await pumpForm(tester);
      await confirmDelete(tester);
      expect(find.text('No hay conexión.'), findsOneWidget);
      expect(results, isEmpty);
    });
  });

  group('generated transactions (COU-155)', () {
    testWidgets('rows generated by a rule carry the mark and say so', (tester) async {
      await tester.pumpApp(
        Column(
          children: [
            TransactionTile(transaction: transactionFixture(id: 1, name: 'Sueldo', isScheduled: true)),
            TransactionTile(transaction: transactionFixture(id: 2, name: 'Taxi')),
          ],
        ),
      );
      expect(find.byKey(const ValueKey('transaction-scheduled-mark')), findsOneWidget);
      expect(find.bySemanticsLabel(RegExp('Sueldo.*Generado por un movimiento programado')), findsOneWidget);
      expect(find.bySemanticsLabel(RegExp('Taxi.*Generado')), findsNothing);
    });
  });
}
