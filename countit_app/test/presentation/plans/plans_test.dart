import 'dart:async';

import 'package:countit_app/app/errors/app_failure.dart';
import 'package:countit_app/app/router/app_router.dart';
import 'package:countit_app/app/session/session_cubit.dart';
import 'package:countit_app/app/session/session_state.dart';
import 'package:countit_app/data/dtos/profile.dart';
import 'package:countit_app/presentation/home/view/home_page.dart';
import 'package:countit_app/presentation/plans/view/my_plan_page.dart';
import 'package:countit_app/presentation/plans/view/plan_upsell_host.dart';
import 'package:countit_app/presentation/plans/view/plans_page.dart';
import 'package:countit_app/presentation/profile/view/profile_page.dart';
import 'package:countit_app/shared/utils/dates.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';

import '../../helpers/mocks.dart';
import '../../helpers/pump_app.dart';

const _proLimits = {
  'max_wallets': 999,
  'max_budgets_per_wallet': 999,
  'max_daily_transactions': 999,
  'max_scheduled_transactions': 50,
  'max_families': 10,
  'max_family_users': 999,
  'family_feature': 1,
  'advanced_statistics': 1,
  'wallet_projection': 1,
};

UserPlan _pro(DateTime validUntil) => UserPlan(
  planId: 3,
  name: 'Contador Profesional',
  limits: _proLimits,
  monthlyPriceCents: 499,
  validUntil: validUntil,
);

final _regular = UserPlan(
  planId: 1,
  name: 'Regular',
  monthlyPriceCents: 0,
  validUntil: DateTime(2028, 10, 4),
  limits: const {'max_wallets': 3, 'family_feature': 0, 'advanced_statistics': 0, 'wallet_projection': 0},
);

Profile _profile(UserPlan plan) => Profile(
  userId: 'u1',
  username: 'demo_ana',
  email: 'ana@correo.ec',
  firstName: 'Ana',
  role: UserRole.user,
  timezone: 'America/Guayaquil',
  plan: plan,
);

DateTime get _today => Dates.userToday('America/Guayaquil');

void main() {
  late MockAuthRepository auth;
  late MockProfileRepository profiles;

  setUpAll(Dates.init);

  setUp(() {
    // A phone-sized portrait screen, tall enough for the whole plan card.
    final view = TestWidgetsFlutterBinding.instance.platformDispatcher.views.first
      ..physicalSize = const Size(1200, 3200)
      ..devicePixelRatio = 3;
    addTearDown(view.reset);
    auth = MockAuthRepository();
    profiles = MockProfileRepository();
    when(() => auth.sessionChanges).thenAnswer((_) => const Stream.empty());
  });

  SessionCubit sessionWith(Profile profile) {
    final session = SessionCubit(auth: auth, profiles: profiles)..emit(SessionState.authenticated(profile));
    addTearDown(session.close);
    return session;
  }

  GoRouter routerAt(String location) => GoRouter(
    initialLocation: location,
    routes: [
      GoRoute(path: AppRoutes.home, builder: (context, state) => const HomePage()),
      GoRoute(path: AppRoutes.profile, builder: (context, state) => const ProfilePage()),
      GoRoute(path: AppRoutes.myPlan, builder: (context, state) => const MyPlanPage()),
      GoRoute(path: AppRoutes.plans, builder: (context, state) => const PlansPage()),
    ],
  );

  group('Mi plan (COU-113)', () {
    testWidgets('paid plan: price, validity, limits and features', (tester) async {
      final until = DateTime(_today.year + 1, _today.month, 1);
      await tester.pumpApp(const MyPlanPage(), auth: auth, session: sessionWith(_profile(_pro(until))));
      expect(find.text('Contador Profesional'), findsOneWidget);
      expect(find.text(r'$4,99 al mes'), findsOneWidget);
      expect(find.text('Gestión ilimitada con vistas analíticas.'), findsOneWidget);
      expect(find.text('Vence el ${Dates.date(until)}'), findsOneWidget);
      expect(find.text('Billeteras'), findsOneWidget);
      expect(find.text('Programadas activas'), findsOneWidget);
      expect(find.text('50'), findsOneWidget);
      expect(find.bySemanticsLabel('Proyección de saldo: incluida'), findsOneWidget);
      expect(find.byKey(const ValueKey('plan-expiry-banner')), findsNothing);
    });

    testWidgets('free plan: «Gratis», no validity pill and how to change plan', (tester) async {
      await tester.pumpApp(const MyPlanPage(), auth: auth, session: sessionWith(_profile(_regular)));
      expect(find.text('Gratis'), findsOneWidget);
      expect(find.textContaining('Vence'), findsNothing);
      expect(find.bySemanticsLabel('Billeteras compartidas: no incluida'), findsOneWidget);
      expect(find.textContaining('Los planes los asigna un administrador'), findsOneWidget);
    });

    testWidgets('pull to refresh reloads the profile (a superadmin may have changed the plan)', (tester) async {
      final until = DateTime(_today.year + 1, 1, 1);
      when(profiles.fetchMyProfile).thenAnswer((_) async => _profile(_regular));
      await tester.pumpApp(const MyPlanPage(), auth: auth, session: sessionWith(_profile(_pro(until))));
      await tester.fling(find.text('Contador Profesional'), const Offset(0, 400), 1000);
      await tester.pumpAndSettle();
      verify(profiles.fetchMyProfile).called(1);
      expect(find.text('Regular'), findsOneWidget);
    });
  });

  group('expiry notice (COU-117)', () {
    testWidgets('expiring in 2 days: banner and warning pill', (tester) async {
      final until = _today.add(const Duration(days: 2));
      await tester.pumpApp(const MyPlanPage(), auth: auth, session: sessionWith(_profile(_pro(until))));
      expect(find.byKey(const ValueKey('plan-expiry-banner')), findsOneWidget);
      expect(
        find.text(
          'Tu plan Contador Profesional vence en 2 días, el ${Dates.date(until)}. '
          'Después pasarás al plan Regular y se aplicarán sus límites.',
        ),
        findsOneWidget,
      );
      expect(find.text('Vence en 2 días'), findsOneWidget);
    });

    testWidgets('ends today and expired have their own wording', (tester) async {
      await tester.pumpApp(const MyPlanPage(), auth: auth, session: sessionWith(_profile(_pro(_today))));
      expect(find.textContaining('termina hoy'), findsOneWidget);
      expect(find.text('Vence hoy'), findsOneWidget);

      final yesterday = _today.subtract(const Duration(days: 1));
      await tester.pumpApp(const MyPlanPage(), auth: auth, session: sessionWith(_profile(_pro(yesterday))));
      expect(find.textContaining('venció el ${Dates.date(yesterday)}'), findsOneWidget);
      expect(find.text('Vencido'), findsOneWidget);
    });

    testWidgets('home shows the notice with a link to «Mi plan»', (tester) async {
      final wallets = MockWalletRepository();
      when(wallets.list).thenAnswer((_) async => const []);
      final until = _today.add(const Duration(days: 1));
      await tester.pumpApp(
        const SizedBox.shrink(),
        auth: auth,
        wallets: wallets,
        session: sessionWith(_profile(_pro(until))),
        router: routerAt(AppRoutes.home),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('vence mañana'), findsOneWidget);
      await tester.tap(find.text('Ver mi plan'));
      await tester.pumpAndSettle();
      expect(find.byType(MyPlanPage), findsOneWidget);
    });

    testWidgets('home without a notice for a plan far from expiring', (tester) async {
      final wallets = MockWalletRepository();
      when(wallets.list).thenAnswer((_) async => const []);
      await tester.pumpApp(
        const SizedBox.shrink(),
        auth: auth,
        wallets: wallets,
        session: sessionWith(_profile(_regular)),
        router: routerAt(AppRoutes.home),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('plan-expiry-banner')), findsNothing);
    });
  });

  group('plans screen (COU-124)', () {
    testWidgets('profile card → Mi plan → Comparar planes: three plans, the current one marked', (tester) async {
      await tester.pumpApp(
        const SizedBox.shrink(),
        auth: auth,
        session: sessionWith(_profile(_regular)),
        router: routerAt(AppRoutes.profile),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('profile-plan-card')));
      await tester.pumpAndSettle();
      expect(find.byType(MyPlanPage), findsOneWidget);
      await tester.tap(find.text('Comparar planes'));
      await tester.pumpAndSettle();
      expect(find.byType(PlansPage), findsOneWidget);
      expect(find.byKey(const ValueKey('plan-offer-1')), findsOneWidget);
      expect(find.text('Tu plan'), findsOneWidget);
      expect(find.bySemanticsLabel('Regular, tu plan actual'), findsOneWidget);
      await tester.scrollUntilVisible(find.byKey(const ValueKey('plan-offer-3')), 300);
      expect(find.text(r'$4,99 al mes'), findsOneWidget);
    });
  });

  group('global 403 feature_not_in_plan (COU-183, COU-61)', () {
    const failure = AppFailure(
      kind: FailureKind.featureNotInPlan,
      message: 'Tu plan no incluye la proyección de billeteras',
      key: 'feature_not_in_plan',
      status: 403,
    );

    testWidgets('opens one plans sheet over any screen, with a link to the plans', (tester) async {
      final wallets = MockWalletRepository();
      when(wallets.list).thenAnswer((_) async => const []);
      final notices = StreamController<AppFailure>.broadcast();
      addTearDown(notices.close);
      await tester.pumpApp(
        const SizedBox.shrink(),
        auth: auth,
        wallets: wallets,
        session: sessionWith(_profile(_regular)),
        router: routerAt(AppRoutes.home),
        planNotices: notices.stream,
      );
      await tester.pumpAndSettle();
      notices
        ..add(failure)
        ..add(failure);
      await tester.pumpAndSettle();
      expect(find.text(featureNotInPlanTitle), findsOneWidget, reason: 'one sheet, even for two answers');
      expect(find.text(failure.message), findsOneWidget);
      expect(find.text('TU PLAN: REGULAR'), findsOneWidget);

      await tester.tap(find.text('Ver planes'));
      await tester.pumpAndSettle();
      expect(find.byType(PlansPage), findsOneWidget);
      expect(find.text(featureNotInPlanTitle), findsNothing);

      // Closed: the next answer opens it again.
      notices.add(failure);
      await tester.pumpAndSettle();
      expect(find.text(featureNotInPlanTitle), findsOneWidget);
      await tester.tap(find.text('Entendido'));
      await tester.pumpAndSettle();
      expect(find.text(featureNotInPlanTitle), findsNothing);
    });
  });
}
