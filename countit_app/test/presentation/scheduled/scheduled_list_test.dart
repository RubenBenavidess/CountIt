import 'package:bloc_test/bloc_test.dart';
import 'package:countit_app/app/errors/app_failure.dart';
import 'package:countit_app/app/router/app_router.dart';
import 'package:countit_app/app/session/session_cubit.dart';
import 'package:countit_app/data/dtos/profile.dart';
import 'package:countit_app/data/dtos/scheduled_transaction.dart';
import 'package:countit_app/data/dtos/transaction.dart';
import 'package:countit_app/presentation/scheduled/cubit/scheduled_list_cubit.dart';
import 'package:countit_app/presentation/scheduled/view/scheduled_form_page.dart';
import 'package:countit_app/presentation/scheduled/view/scheduled_list_page.dart';
import 'package:countit_app/presentation/scheduled/view/widgets/scheduled_quota_card.dart';
import 'package:countit_app/presentation/scheduled/view/widgets/scheduled_tile.dart';
import 'package:countit_app/shared/state/load_state.dart';
import 'package:countit_app/shared/utils/dates.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';

import '../../helpers/mocks.dart';
import '../../helpers/pump_app.dart';
import '../../helpers/scheduled_fixtures.dart';
import '../../helpers/wallet_fixtures.dart';

const _network = AppFailure(kind: FailureKind.network, message: 'No hay conexión.');

Profile _profile({int quota = 3}) => Profile(
  userId: 'u1',
  username: 'mariaq',
  email: 'maria@correo.ec',
  role: UserRole.user,
  timezone: 'America/Guayaquil',
  plan: UserPlan(planId: 1, name: 'Regular', limits: {'max_scheduled_transactions': quota}),
);

void main() {
  late MockScheduledTransactionRepository scheduled;

  setUpAll(Dates.init);

  setUp(() => scheduled = MockScheduledTransactionRepository());

  group('sortRules', () {
    test('running rules by next run, paused ones last', () {
      final rules = sortRules([
        scheduledFixture(id: 1, isPaused: true, nextRunDate: DateTime(2026, 10, 6)),
        scheduledFixture(id: 2, nextRunDate: DateTime(2026, 12, 1)),
        scheduledFixture(id: 3, nextRunDate: DateTime(2026, 10, 20)),
      ]);
      expect(rules.map((r) => r.scheduledTransactionId), [3, 2, 1]);
    });
  });

  group('ScheduledListCubit (COU-88)', () {
    final rules = [scheduledFixture(id: 1), scheduledFixture(id: 2, nextRunDate: DateTime(2026, 12, 1))];
    const usage = ScheduledUsage(total: 2, running: 2);

    blocTest<ScheduledListCubit, ScheduledListState>(
      'loads the rules of its wallet and the caller\'s usage',
      setUp: () {
        when(() => scheduled.listByWallet(4)).thenAnswer((_) async => rules);
        when(() => scheduled.usageOf('u1')).thenAnswer((_) async => usage);
      },
      build: () => ScheduledListCubit(scheduled, walletId: 4, userId: 'u1'),
      act: (cubit) => cubit.load(),
      expect: () => [
        const ScheduledListState(rules: LoadState.loading()),
        ScheduledListState(rules: LoadState.success(rules), usage: usage),
      ],
    );

    blocTest<ScheduledListCubit, ScheduledListState>(
      'a failed usage query never fails the list',
      setUp: () {
        when(() => scheduled.listByWallet(4)).thenAnswer((_) async => rules);
        when(() => scheduled.usageOf('u1')).thenThrow(_network);
      },
      build: () => ScheduledListCubit(scheduled, walletId: 4, userId: 'u1'),
      act: (cubit) => cubit.load(),
      expect: () => [
        const ScheduledListState(rules: LoadState.loading()),
        ScheduledListState(rules: LoadState.success(rules)),
      ],
    );

    blocTest<ScheduledListCubit, ScheduledListState>(
      'a failed reload keeps the rules on screen',
      setUp: () {
        when(() => scheduled.listByWallet(4)).thenThrow(_network);
        when(() => scheduled.usageOf('u1')).thenAnswer((_) async => usage);
      },
      build: () => ScheduledListCubit(scheduled, walletId: 4, userId: 'u1'),
      seed: () => ScheduledListState(rules: LoadState.success(rules), usage: usage),
      act: (cubit) => cubit.load(),
      expect: () => [
        ScheduledListState(
          rules: LoadState.loading(previous: rules),
          usage: usage,
        ),
        ScheduledListState(
          rules: LoadState.failure(_network, previous: rules),
          usage: usage,
        ),
      ],
    );

    blocTest<ScheduledListCubit, ScheduledListState>(
      'without a user it skips the usage query',
      setUp: () => when(() => scheduled.listByWallet(4)).thenAnswer((_) async => const []),
      build: () => ScheduledListCubit(scheduled, walletId: 4, userId: null),
      act: (cubit) => cubit.load(),
      verify: (_) => verifyNever(() => scheduled.usageOf(any())),
    );
  });

  group('ScheduledQuota (COU-156)', () {
    test('creating counts every active rule, resuming only the running ones', () {
      const quota = ScheduledQuota(limit: 3, usage: ScheduledUsage(total: 3, running: 2));
      expect(quota.canCreate, isFalse);
      expect(quota.canResume, isTrue);
      expect(quota.limitMessage, 'Alcanzaste el límite de 3 transacciones programadas de tu plan');
    });

    test('unknown usage or an unlimited plan never block (the backend decides)', () {
      expect(const ScheduledQuota(limit: 3).canCreate, isTrue);
      expect(const ScheduledQuota(usage: ScheduledUsage(total: 80, running: 80)).canCreate, isTrue);
      final unlimited = ScheduledQuota.of(
        const UserPlan(planId: 3, name: 'Profesional', limits: {'max_scheduled_transactions': 999}),
        const ScheduledUsage(total: 60, running: 60),
      );
      expect(unlimited.limit, isNull);
      expect(unlimited.canCreate, isTrue);
    });
  });

  group('ScheduledListPage (COU-88, COU-156)', () {
    late MockAuthRepository auth;
    late MockProfileRepository profiles;

    setUp(() {
      auth = MockAuthRepository();
      profiles = MockProfileRepository();
      when(() => auth.sessionChanges).thenAnswer((_) => const Stream.empty());
      when(() => auth.hasSession).thenReturn(true);
      when(() => profiles.fetchMyProfile()).thenAnswer((_) async => _profile());
    });

    Future<void> pumpPage(WidgetTester tester, {bool shared = false}) async {
      tester.view.physicalSize = const Size(420, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final session = SessionCubit(auth: auth, profiles: profiles);
      addTearDown(session.close);
      await session.restore();
      await tester.pumpApp(
        ScheduledListPage(
          wallet: walletFixture(id: 4, name: 'Pichincha', memberCount: shared ? 2 : 0),
        ),
        auth: auth,
        profiles: profiles,
        scheduled: scheduled,
        session: session,
      );
      await tester.pumpAndSettle();
    }

    testWidgets('rules with frequency, next run, pause badge and amount', (tester) async {
      when(() => scheduled.listByWallet(4)).thenAnswer(
        (_) async => [
          scheduledFixture(id: 1, name: 'Arriendo', nextRunDate: DateTime(2026, 11, 5)),
          scheduledFixture(
            id: 2,
            name: 'Sueldo',
            type: TransactionType.income,
            amount: 900,
            periodicity: Periodicity.weeks,
            interval: 2,
            isPaused: true,
          ),
        ],
      );
      when(() => scheduled.usageOf('u1')).thenAnswer((_) async => const ScheduledUsage(total: 2, running: 1));
      await pumpPage(tester);

      expect(find.byType(ScheduledTile), findsNWidgets(2));
      expect(find.text('Arriendo'), findsOneWidget);
      expect(find.text('Cada mes · Próxima: 5 nov 2026'), findsOneWidget);
      expect(find.text(r'− $300,00'), findsOneWidget);
      expect(find.text('Pausada'), findsOneWidget);
      expect(find.text('Cada 2 semanas'), findsOneWidget);
      expect(find.text(r'+ $900,00'), findsOneWidget);
      // Screen readers hear the frequency, the next run and the pause.
      expect(
        find.bySemanticsLabel(RegExp(r'Gasto programado Arriendo, menos \$300,00, Cada mes, próxima ejecución jueves')),
        findsOneWidget,
      );
      expect(find.bySemanticsLabel(RegExp('Ingreso programado Sueldo.*Cada 2 semanas, pausada')), findsOneWidget);
      // Quota of the plan.
      expect(find.text('Usas 2 de 3 programadas de tu plan Regular'), findsOneWidget);
    });

    testWidgets('shared wallets show who scheduled each rule', (tester) async {
      when(() => scheduled.listByWallet(4)).thenAnswer((_) async => [scheduledFixture(authorName: 'Carlos')]);
      when(() => scheduled.usageOf('u1')).thenAnswer((_) async => const ScheduledUsage(total: 0, running: 0));
      await pumpPage(tester, shared: true);
      expect(find.text('Sin presupuesto · Carlos'), findsOneWidget);
    });

    testWidgets('empty state explains what scheduling does', (tester) async {
      when(() => scheduled.listByWallet(4)).thenAnswer((_) async => const []);
      when(() => scheduled.usageOf('u1')).thenAnswer((_) async => const ScheduledUsage(total: 0, running: 0));
      await pumpPage(tester);
      expect(find.text('Sin movimientos programados'), findsOneWidget);
      expect(find.byType(ScheduledTile), findsNothing);
    });

    testWidgets('error with retry', (tester) async {
      var calls = 0;
      when(() => scheduled.listByWallet(4)).thenAnswer((_) async {
        if (calls++ == 0) throw _network;
        return [scheduledFixture()];
      });
      when(() => scheduled.usageOf('u1')).thenAnswer((_) async => const ScheduledUsage(total: 1, running: 1));
      await pumpPage(tester);
      expect(find.text('No hay conexión.'), findsOneWidget);
      await tester.tap(find.text('Reintentar'));
      await tester.pumpAndSettle();
      expect(find.byType(ScheduledTile), findsOneWidget);
    });

    testWidgets('a full quota says so and that pausing frees nothing', (tester) async {
      when(() => scheduled.listByWallet(4)).thenAnswer((_) async => [scheduledFixture()]);
      when(() => scheduled.usageOf('u1')).thenAnswer((_) async => const ScheduledUsage(total: 3, running: 2));
      await pumpPage(tester);
      expect(find.text('Usas 3 de 3 programadas de tu plan Regular'), findsOneWidget);
      expect(find.text('Límite'), findsOneWidget);
      expect(find.byType(ScheduledQuotaCard), findsOneWidget);
      expect(find.textContaining('pausar no libera cupo'), findsOneWidget);
    });
  });

  group('ScheduledListPage navigation and gating (COU-151, COU-152, COU-156)', () {
    late MockAuthRepository auth;
    late MockProfileRepository profiles;

    setUp(() {
      auth = MockAuthRepository();
      profiles = MockProfileRepository();
      when(() => auth.sessionChanges).thenAnswer((_) => const Stream.empty());
      when(() => auth.hasSession).thenReturn(true);
      when(() => profiles.fetchMyProfile()).thenAnswer((_) async => _profile());
    });

    /// The list with stand-ins for the form routes, which pop `true`.
    Future<void> pumpRouted(WidgetTester tester, {bool owner = true}) async {
      tester.view.physicalSize = const Size(420, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final session = SessionCubit(auth: auth, profiles: profiles);
      addTearDown(session.close);
      await session.restore();
      final wallet = walletFixture(id: 4, isOwner: owner, memberCount: 1);
      final router = GoRouter(
        initialLocation: AppRoutes.scheduled(4),
        routes: [
          GoRoute(
            path: AppRoutes.scheduled(4),
            builder: (context, state) => ScheduledListPage(wallet: wallet),
          ),
          GoRoute(
            path: AppRoutes.newScheduled(4),
            builder: (context, state) => Scaffold(
              body: TextButton(onPressed: () => context.pop(true), child: const Text('NEW RULE')),
            ),
          ),
          GoRoute(
            path: '${AppRoutes.wallets}/4/scheduled/:ruleId/edit',
            builder: (context, state) => Scaffold(
              body: TextButton(
                onPressed: () => context.pop(true),
                child: Text('EDIT ${(state.extra! as ScheduledEditArgs).rule.name}'),
              ),
            ),
          ),
        ],
      );
      await tester.pumpApp(
        const SizedBox(),
        auth: auth,
        profiles: profiles,
        scheduled: scheduled,
        session: session,
        router: router,
      );
      await tester.pumpAndSettle();
    }

    testWidgets('with room in the plan «Programar» opens the form and the list reloads', (tester) async {
      when(() => scheduled.listByWallet(4)).thenAnswer((_) async => const []);
      when(() => scheduled.usageOf('u1')).thenAnswer((_) async => const ScheduledUsage(total: 1, running: 1));
      await pumpRouted(tester);
      await tester.tap(find.byKey(const ValueKey('scheduled-new')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('NEW RULE'));
      await tester.pumpAndSettle();
      verify(() => scheduled.listByWallet(4)).called(2);
    });

    testWidgets('a full quota shows the plans instead of the form', (tester) async {
      when(() => scheduled.listByWallet(4)).thenAnswer((_) async => [scheduledFixture()]);
      when(() => scheduled.usageOf('u1')).thenAnswer((_) async => const ScheduledUsage(total: 3, running: 1));
      await pumpRouted(tester);
      await tester.tap(find.byKey(const ValueKey('scheduled-new')));
      await tester.pumpAndSettle();
      expect(find.text('Alcanzaste el límite de 3 transacciones programadas de tu plan'), findsOneWidget);
      expect(find.text('NEW RULE'), findsNothing);
    });

    testWidgets('the author or the owner opens the edit form; others only read', (tester) async {
      when(() => scheduled.listByWallet(4)).thenAnswer(
        (_) async => [
          scheduledFixture(id: 1, name: 'Mía', userId: 'u1'),
          scheduledFixture(id: 2, name: 'De Carlos', userId: 'u2', nextRunDate: DateTime(2026, 12, 1)),
        ],
      );
      when(() => scheduled.usageOf('u1')).thenAnswer((_) async => const ScheduledUsage(total: 1, running: 1));
      await pumpRouted(tester, owner: false);
      await tester.tap(find.text('De Carlos'));
      await tester.pumpAndSettle();
      expect(find.text('EDIT De Carlos'), findsNothing);
      await tester.tap(find.text('Mía'));
      await tester.pumpAndSettle();
      expect(find.text('EDIT Mía'), findsOneWidget);
    });
  });
}
