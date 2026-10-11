import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:countit_app/app/errors/app_failure.dart';
import 'package:countit_app/app/router/app_router.dart';
import 'package:countit_app/app/session/session_cubit.dart';
import 'package:countit_app/app/session/session_state.dart';
import 'package:countit_app/data/dtos/admin.dart';
import 'package:countit_app/data/dtos/profile.dart';
import 'package:countit_app/presentation/admin/cubit/admin_failures.dart';
import 'package:countit_app/presentation/admin/cubit/admin_users_cubit.dart' show AdminListStatus;
import 'package:countit_app/presentation/admin/cubit/audit_log_cubit.dart';
import 'package:countit_app/presentation/admin/view/admin_page.dart';
import 'package:countit_app/presentation/admin/view/audit_log_page.dart';
import 'package:countit_app/shared/utils/dates.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';

import '../../helpers/admin_fixtures.dart';
import '../../helpers/mocks.dart';
import '../../helpers/pump_app.dart';

AuditEntry _entry(int id, {String action = 'role_changed', String entity = 'user', String? actor = 'rubendario'}) =>
    AuditEntry(
      auditId: id,
      occurredAt: DateTime.utc(2026, 10, 4, 15, 30),
      actorId: actor == null ? null : 'u-root',
      actorUsername: actor,
      action: action,
      entity: entity,
      entityId: 'u-carlos',
      details: const {'from': 'user', 'to': 'admin'},
    );

List<AuditEntry> _entries(int count, {int from = 1}) => [for (var i = from; i < from + count; i++) _entry(i)];

void main() {
  late MockAdminRepository admin;
  late MockAuthRepository auth;

  setUpAll(() async {
    await Dates.init();
    registerFallbackValue(const AuditFilter());
  });

  setUp(() {
    final view = TestWidgetsFlutterBinding.instance.platformDispatcher.views.first
      ..physicalSize = const Size(1200, 2600)
      ..devicePixelRatio = 3;
    addTearDown(view.reset);
    admin = MockAdminRepository();
    auth = MockAuthRepository();
    when(() => auth.sessionChanges).thenAnswer((_) => const Stream.empty());
  });

  group('AuditLogCubit (COU-208, COU-209)', () {
    blocTest<AuditLogCubit, AuditLogState>(
      'loads, then pages by offset without repeating entries',
      setUp: () {
        when(() => admin.listAuditLog(filter: const AuditFilter()))
            .thenAnswer((_) async => Paged(_entries(50), hasMore: true));
        when(() => admin.listAuditLog(filter: const AuditFilter(), offset: 50))
            .thenAnswer((_) async => Paged([_entry(50), ..._entries(2, from: 51)], hasMore: false));
      },
      build: () => AuditLogCubit(admin),
      act: (cubit) async {
        await cubit.load();
        await cubit.loadMore();
      },
      verify: (cubit) {
        expect(cubit.state.items.map((e) => e.auditId), [for (var i = 1; i <= 52; i++) i]);
        expect(cubit.state.hasMore, isFalse);
      },
    );

    test('entity chip at once; entity id debounced; an older answer is dropped', () async {
      final slow = Completer<Paged<AuditEntry>>();
      when(() => admin.listAuditLog(filter: const AuditFilter())).thenAnswer((_) => slow.future);
      when(() => admin.listAuditLog(filter: const AuditFilter(entity: 'bank')))
          .thenAnswer((_) async => Paged([_entry(9, action: 'bank_created', entity: 'bank')], hasMore: false));
      when(
        () => admin.listAuditLog(
          filter: const AuditFilter(entity: 'bank', entityId: '14'),
        ),
      ).thenAnswer((_) async => const Paged([], hasMore: false));
      final cubit = AuditLogCubit(admin, debounce: const Duration(milliseconds: 20));
      unawaited(cubit.load());
      await cubit.filterByEntity('bank');
      slow.complete(Paged(_entries(3), hasMore: false));
      await Future<void>.delayed(Duration.zero);
      expect(cubit.state.items.single.auditId, 9);

      cubit
        ..filterByEntityId('1')
        ..filterByEntityId(' 14 ');
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(cubit.state.filter, const AuditFilter(entity: 'bank', entityId: '14'));
      expect(cubit.state.items, isEmpty);
      verifyNever(
        () => admin.listAuditLog(
          filter: const AuditFilter(entity: 'bank', entityId: '1'),
        ),
      );
      await cubit.close();
    });

    blocTest<AuditLogCubit, AuditLogState>(
      'a 403 is neutral',
      setUp: () => when(() => admin.listAuditLog(filter: any(named: 'filter'))).thenThrow(
        const AppFailure(kind: FailureKind.forbidden, message: 'Acceso denegado', key: 'forbidden', status: 403),
      ),
      build: () => AuditLogCubit(admin),
      act: (cubit) => cubit.load(),
      verify: (cubit) {
        expect(cubit.state.status, AdminListStatus.failure);
        expect(cubit.state.failure!.message, adminForbiddenMessage);
      },
    );
  });

  group('audit screen', () {
    Future<void> pumpAt(WidgetTester tester, UserRole role, String location) async {
      final session = SessionCubit(auth: auth, profiles: MockProfileRepository())
        ..emit(SessionState.authenticated(adminProfile(role)));
      addTearDown(session.close);
      await tester.pumpApp(
        const SizedBox.shrink(),
        auth: auth,
        admin: admin,
        session: session,
        router: GoRouter(
          initialLocation: location,
          routes: [
            GoRoute(
              path: AppRoutes.admin,
              builder: (context, state) => const AdminPage(),
              routes: [GoRoute(path: 'audit', builder: (context, state) => const AuditLogPage())],
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('the hub shows «Auditoría» to the superadmin only', (tester) async {
      await pumpAt(tester, UserRole.admin, AppRoutes.admin);
      expect(find.byKey(const ValueKey('admin-audit')), findsNothing);
      expect(find.byKey(const ValueKey('admin-users')), findsOneWidget);
      await pumpAt(tester, UserRole.superadmin, AppRoutes.admin);
      expect(find.byKey(const ValueKey('admin-audit')), findsOneWidget);
    });

    testWidgets('an admin never gets the audit screen built', (tester) async {
      await pumpAt(tester, UserRole.admin, AppRoutes.auditLog);
      expect(find.text('Sin acceso'), findsOneWidget);
      verifyZeroInteractions(admin);
    });

    testWidgets('scrolling away and back rebuilds the entries without a PageStorage clash', (tester) async {
      // The list stores its scroll offset (a double) under PageStorageKey('audit-log');
      // each ExpansionTile must store its expanded flag under its own key.
      when(() => admin.listAuditLog(filter: const AuditFilter()))
          .thenAnswer((_) async => Paged(_entries(40), hasMore: false));
      await pumpAt(tester, UserRole.superadmin, AppRoutes.auditLog);
      final list = find.byKey(const PageStorageKey('audit-log'));
      await tester.drag(list, const Offset(0, -3000));
      await tester.pumpAndSettle();
      await tester.drag(list, const Offset(0, 3000));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.byKey(const ValueKey('audit-1')), findsOneWidget);
    });

    testWidgets('entries in Spanish with who, when and what; details on demand; filters', (tester) async {
      when(() => admin.listAuditLog(filter: const AuditFilter())).thenAnswer(
        (_) async => Paged([_entry(2), _entry(1, action: 'plans_expired', entity: 'job', actor: null)], hasMore: false),
      );
      when(() => admin.listAuditLog(filter: const AuditFilter(entity: 'user')))
          .thenAnswer((_) async => Paged([_entry(2)], hasMore: false));
      when(
        () => admin.listAuditLog(
          filter: const AuditFilter(entity: 'user', entityId: 'nadie'),
        ),
      ).thenAnswer((_) async => const Paged([], hasMore: false));
      await pumpAt(tester, UserRole.superadmin, AppRoutes.auditLog);
      expect(find.text('Rol cambiado'), findsOneWidget);
      expect(find.text('Planes vencidos'), findsOneWidget);
      expect(find.text('@rubendario · 4 oct 2026, 10:30\nUsuarios · u-carlos'), findsOneWidget);
      expect(find.textContaining('Sistema · 4 oct 2026'), findsOneWidget);

      expect(find.textContaining('to: admin', findRichText: true), findsNothing);
      await tester.tap(find.text('Rol cambiado'));
      await tester.pumpAndSettle();
      expect(find.textContaining('to: admin', findRichText: true), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('audit-entity-user')));
      await tester.pumpAndSettle();
      expect(find.text('Planes vencidos'), findsNothing);

      await tester.enterText(find.byType(TextField), 'nadie');
      await tester.pump(const Duration(milliseconds: 450));
      await tester.pumpAndSettle();
      expect(find.text('Nada con estos filtros.'), findsOneWidget);
      verify(
        () => admin.listAuditLog(
          filter: const AuditFilter(entity: 'user', entityId: 'nadie'),
        ),
      ).called(1);
    });
  });
}
