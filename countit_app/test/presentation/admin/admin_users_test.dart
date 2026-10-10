import 'package:countit_app/app/errors/app_failure.dart';
import 'package:countit_app/app/router/app_router.dart';
import 'package:countit_app/app/session/session_cubit.dart';
import 'package:countit_app/app/session/session_state.dart';
import 'package:countit_app/data/dtos/admin.dart';
import 'package:countit_app/data/dtos/profile.dart';
import 'package:countit_app/data/repositories/plan_repository.dart';
import 'package:countit_app/presentation/admin/cubit/admin_failures.dart';
import 'package:countit_app/presentation/admin/view/admin_page.dart';
import 'package:countit_app/presentation/admin/view/admin_user_page.dart';
import 'package:countit_app/presentation/admin/view/admin_users_page.dart';
import 'package:countit_app/shared/utils/dates.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';

import '../../helpers/admin_fixtures.dart';
import '../../helpers/mocks.dart';
import '../../helpers/plan_fixtures.dart';
import '../../helpers/pump_app.dart';

/// The confirm button of the dialog (the screen has a button with the same text).
Finder _inDialog(String label) => find.descendant(of: find.byType(AlertDialog), matching: find.text(label));

void main() {
  late MockAuthRepository auth;
  late MockAdminRepository admin;
  late MockProfileRepository profiles;

  setUpAll(Dates.init);

  setUp(() {
    final view = TestWidgetsFlutterBinding.instance.platformDispatcher.views.first
      ..physicalSize = const Size(1200, 2600)
      ..devicePixelRatio = 3;
    addTearDown(view.reset);
    auth = MockAuthRepository();
    admin = MockAdminRepository();
    profiles = MockProfileRepository();
    when(() => auth.sessionChanges).thenAnswer((_) => const Stream.empty());
  });

  SessionCubit sessionAs(UserRole role) {
    when(profiles.fetchMyProfile).thenAnswer((_) async => adminProfile(role));
    final session = SessionCubit(auth: auth, profiles: profiles)..emit(SessionState.authenticated(adminProfile(role)));
    addTearDown(session.close);
    return session;
  }

  GoRouter router(String location, {Object? extra}) => GoRouter(
    initialLocation: location,
    initialExtra: extra,
    routes: [
      GoRoute(path: AppRoutes.admin, builder: (context, state) => const AdminPage()),
      GoRoute(path: AppRoutes.adminUsers, builder: (context, state) => const AdminUsersPage()),
      GoRoute(
        path: '${AppRoutes.adminUsers}/:userId',
        builder: (context, state) => AdminUserPage(user: state.extra! as AdminUser),
      ),
    ],
  );

  Future<void> pumpAt(
    WidgetTester tester,
    String location,
    UserRole role, {
    Object? extra,
    PlanRepository? plans,
  }) async {
    await tester.pumpApp(
      const SizedBox.shrink(),
      auth: auth,
      admin: admin,
      plans: plans,
      session: sessionAs(role),
      router: router(location, extra: extra),
    );
    await tester.pumpAndSettle();
  }

  group('admin navigation by role (COU-127)', () {
    testWidgets('a user never gets the admin screens built (UI guard)', (tester) async {
      await pumpAt(tester, AppRoutes.admin, UserRole.user);
      expect(find.text('Sin acceso'), findsOneWidget);
      expect(find.byKey(const ValueKey('admin-users')), findsNothing);
      await pumpAt(tester, AppRoutes.adminUsers, UserRole.user);
      expect(find.text('Sin acceso'), findsOneWidget);
      verifyZeroInteractions(admin);
    });

    testWidgets('an admin sees the hub with the users section', (tester) async {
      when(() => admin.listUsers(search: '')).thenAnswer((_) async => Paged([adminUser()], hasMore: false));
      await pumpAt(tester, AppRoutes.admin, UserRole.admin);
      expect(find.text('Administración'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('admin-users')));
      await tester.pumpAndSettle();
      expect(find.byType(AdminUsersPage), findsOneWidget);
      expect(find.text('Carlos Pérez'), findsOneWidget);
    });
  });

  group('users list (COU-201)', () {
    testWidgets('search (debounced) and pages while scrolling', (tester) async {
      when(() => admin.listUsers(search: '')).thenAnswer((_) async => Paged(adminUsers(30), hasMore: true));
      when(() => admin.listUsers(search: '', offset: 30))
          .thenAnswer((_) async => Paged(adminUsers(3, from: 31), hasMore: false));
      when(() => admin.listUsers(search: 'user33'))
          .thenAnswer((_) async => Paged(adminUsers(1, from: 33), hasMore: false));
      await pumpAt(tester, AppRoutes.adminUsers, UserRole.admin);
      expect(find.text('@user01 · delivered+user01@resend.dev'), findsOneWidget);

      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('admin-user-u33')),
        400,
        scrollable: find.descendant(
          of: find.byKey(const PageStorageKey('admin-users')),
          matching: find.byType(Scrollable),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('admin-user-u33')), findsOneWidget);
      verify(() => admin.listUsers(search: '', offset: 30)).called(1);

      await tester.enterText(find.byType(TextField), 'user3');
      await tester.enterText(find.byType(TextField), 'user33');
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
      verifyNever(() => admin.listUsers(search: 'user3'));
      expect(find.byKey(const ValueKey('admin-user-u33')), findsOneWidget);
      expect(find.byKey(const ValueKey('admin-user-u1')), findsNothing);
    });

    testWidgets('no results and a neutral 403', (tester) async {
      when(() => admin.listUsers(search: '')).thenThrow(
        const AppFailure(kind: FailureKind.forbidden, message: 'Acceso denegado', key: 'forbidden', status: 403),
      );
      await pumpAt(tester, AppRoutes.adminUsers, UserRole.admin);
      expect(find.text(adminForbiddenMessage), findsOneWidget);
    });

    testWidgets('empty search result', (tester) async {
      when(() => admin.listUsers(search: '')).thenAnswer((_) async => const Paged([], hasMore: false));
      await pumpAt(tester, AppRoutes.adminUsers, UserRole.admin);
      expect(find.text('Sin resultados'), findsOneWidget);
    });
  });

  group('user detail (COU-202, COU-203)', () {
    testWidgets('an admin sees identity, role and plan, no finances and no actions', (tester) async {
      await pumpAt(tester, AppRoutes.adminUser('u-carlos'), UserRole.admin, extra: adminUser());
      expect(find.text('Carlos Pérez'), findsOneWidget);
      expect(find.text('delivered+demo_carlos@resend.dev'), findsOneWidget);
      expect(find.text('Regular'), findsOneWidget);
      expect(find.textContaining('no se muestran billeteras'), findsOneWidget);
      expect(find.text('Solo un superadministrador puede cambiar planes.'), findsOneWidget);
      expect(find.byKey(const ValueKey('admin-change-plan')), findsNothing);
    });

    testWidgets('nobody changes their own plan', (tester) async {
      await pumpAt(tester, AppRoutes.adminUser('u-me'), UserRole.superadmin, extra: adminUser(id: 'u-me'));
      expect(find.text('No puedes cambiar tu propio plan.'), findsOneWidget);
      expect(find.byKey(const ValueKey('admin-change-plan')), findsNothing);
    });

    testWidgets('superadmin changes the plan after a confirmation with the summary', (tester) async {
      when(() => admin.setUserPlan('u-carlos', planId: 2, validUntil: any(named: 'validUntil')))
          .thenAnswer((invocation) async {
            final until = invocation.namedArguments[#validUntil] as DateTime;
            return PlanAssignment(planId: 2, planName: 'Contador', validUntil: until);
          });
      await pumpAt(tester, AppRoutes.adminUser('u-carlos'), UserRole.superadmin, extra: adminUser());
      await tester.tap(find.byKey(const ValueKey('admin-change-plan')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('plan-choice-2')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Revisar cambio'));
      await tester.pumpAndSettle();
      expect(find.text('¿Cambiar el plan de @demo_carlos?'), findsOneWidget);
      expect(find.textContaining('Regular → Contador, vigente hasta el 4 oct 2028.'), findsOneWidget);
      await tester.tap(_inDialog('Cambiar plan'));
      await tester.pumpAndSettle();
      verify(() => admin.setUserPlan('u-carlos', planId: 2, validUntil: DateTime(2028, 10, 4))).called(1);
      expect(find.text('Plan actualizado: Contador hasta el 4 oct 2028.'), findsOneWidget);
      expect(find.text('Contador'), findsOneWidget);
    });

    testWidgets('without the plan catalogue the change is not offered: an error and nothing sent', (tester) async {
      await pumpAt(
        tester,
        AppRoutes.adminUser('u-carlos'),
        UserRole.superadmin,
        extra: adminUser(),
        plans: FakePlanRepository(
          failure: const AppFailure(kind: FailureKind.network, message: 'Sin conexión'),
        ),
      );
      await tester.tap(find.byKey(const ValueKey('admin-change-plan')));
      await tester.pumpAndSettle();
      expect(find.text('Sin conexión'), findsOneWidget);
      expect(find.byKey(const ValueKey('plan-choice-1')), findsNothing);
      verifyNever(
        () => admin.setUserPlan(
          any(),
          planId: any(named: 'planId'),
          validUntil: any(named: 'validUntil'),
        ),
      );
    });

    testWidgets('a downgrade warns that quotas apply right away; cancelling sends nothing', (tester) async {
      await pumpAt(
        tester,
        AppRoutes.adminUser('u-ana'),
        UserRole.superadmin,
        extra: adminUser(id: 'u-ana', username: 'demo_ana', plan: 'Contador Profesional'),
      );
      await tester.tap(find.byKey(const ValueKey('admin-change-plan')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('plan-choice-1')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Revisar cambio'));
      await tester.pumpAndSettle();
      expect(find.textContaining('se aplican sus límites de inmediato'), findsOneWidget);
      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();
      verifyNever(
        () => admin.setUserPlan(
          any(),
          planId: any(named: 'planId'),
          validUntil: any(named: 'validUntil'),
        ),
      );
    });

    testWidgets('the role is read-only: even a superadmin cannot change it from the app (contract 1.4)', (
      tester,
    ) async {
      await pumpAt(tester, AppRoutes.adminUser('u-carlos'), UserRole.superadmin, extra: adminUser());
      expect(find.text('Rol'), findsOneWidget);
      expect(find.text('Usuario'), findsNWidgets(2), reason: 'title and the role row');
      expect(find.byKey(const ValueKey('admin-role-readonly')), findsOneWidget);
      expect(find.byKey(const ValueKey('admin-change-plan')), findsOneWidget);
      expect(find.text('Cambiar rol'), findsNothing);
    });
  });
}
