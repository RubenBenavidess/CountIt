import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:countit_app/app/errors/app_failure.dart';
import 'package:countit_app/data/dtos/admin.dart';
import 'package:countit_app/data/dtos/profile.dart';
import 'package:countit_app/presentation/admin/cubit/admin_failures.dart';
import 'package:countit_app/presentation/admin/cubit/admin_user_cubit.dart';
import 'package:countit_app/presentation/admin/cubit/admin_users_cubit.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../../helpers/admin_fixtures.dart';
import '../../helpers/mocks.dart';
import '../../helpers/plan_fixtures.dart';

const _network = AppFailure(kind: FailureKind.network, message: 'No hay conexión.');
const _forbidden = AppFailure(kind: FailureKind.forbidden, message: 'Acceso denegado', key: 'forbidden', status: 403);

void main() {
  late MockAdminRepository admin;

  setUp(() => admin = MockAdminRepository());

  group('AdminUsersCubit (COU-201)', () {
    final first = adminUsers(30);
    final second = adminUsers(5, from: 31);

    blocTest<AdminUsersCubit, AdminUsersState>(
      'loads the first page',
      setUp: () => when(() => admin.listUsers(search: '')).thenAnswer((_) async => Paged(first, hasMore: true)),
      build: () => AdminUsersCubit(admin),
      act: (cubit) => cubit.load(),
      expect: () => [
        const AdminUsersState(status: AdminListStatus.loading),
        AdminUsersState(status: AdminListStatus.success, items: first, hasMore: true),
      ],
    );

    blocTest<AdminUsersCubit, AdminUsersState>(
      'load more appends the next page by offset, each user once',
      setUp: () =>
          when(() => admin.listUsers(search: '', offset: 30))
              .thenAnswer((_) async => Paged([first.last, ...second], hasMore: false)),
      build: () => AdminUsersCubit(admin),
      seed: () => AdminUsersState(status: AdminListStatus.success, items: first, hasMore: true),
      act: (cubit) async {
        await cubit.loadMore();
        await cubit.loadMore(); // at the end: ignored
      },
      expect: () => [
        AdminUsersState(status: AdminListStatus.success, items: first, hasMore: true, loadingMore: true),
        AdminUsersState(status: AdminListStatus.success, items: [...first, ...second]),
      ],
      verify: (_) => verify(() => admin.listUsers(search: '', offset: 30)).called(1),
    );

    blocTest<AdminUsersCubit, AdminUsersState>(
      'a failed «load more» waits for an explicit retry',
      setUp: () => when(() => admin.listUsers(search: '', offset: 30)).thenThrow(_network),
      build: () => AdminUsersCubit(admin),
      seed: () => AdminUsersState(status: AdminListStatus.success, items: first, hasMore: true),
      act: (cubit) async {
        await cubit.loadMore();
        await cubit.loadMore(); // scrolling again does not hammer the server
        await cubit.loadMore(retry: true);
      },
      verify: (cubit) {
        verify(() => admin.listUsers(search: '', offset: 30)).called(2);
        expect(cubit.state.moreFailure, _network);
        expect(cubit.state.items, first);
      },
    );

    test('search is debounced: only the last term goes out, older answers are dropped', () async {
      final slow = Completer<Paged<AdminUser>>();
      when(() => admin.listUsers(search: '')).thenAnswer((_) => slow.future);
      when(() => admin.listUsers(search: 'car')).thenAnswer((_) async => Paged([adminUser()], hasMore: false));
      final cubit = AdminUsersCubit(admin, debounce: const Duration(milliseconds: 20));
      unawaited(cubit.load());
      cubit
        ..search('c')
        ..search('ca')
        ..search('car ');
      expect(cubit.state.items, isEmpty, reason: 'rows of the previous term are cleared');
      await Future<void>.delayed(const Duration(milliseconds: 60));
      slow.complete(Paged(first, hasMore: true)); // late answer for the old term
      await Future<void>.delayed(Duration.zero);
      expect(cubit.state.search, 'car');
      expect(cubit.state.items, [adminUser()]);
      verifyNever(() => admin.listUsers(search: 'c'));
      verifyNever(() => admin.listUsers(search: 'ca'));
      await cubit.close();
    });

    blocTest<AdminUsersCubit, AdminUsersState>(
      'a user changed in the detail is replaced in place',
      build: () => AdminUsersCubit(admin),
      seed: () => AdminUsersState(status: AdminListStatus.success, items: [adminUser()]),
      act: (cubit) => cubit.replace(adminUser(role: UserRole.admin)),
      expect: () => [
        AdminUsersState(
          status: AdminListStatus.success,
          items: [adminUser(role: UserRole.admin)],
        ),
      ],
    );
  });

  group('AdminUserCubit (COU-203)', () {
    final today = DateTime(2026, 10, 4);
    final contador = planOffer(2);
    final nowUtc = DateTime.utc(2026, 10, 4, 15);

    test('valid until must be after today (user zone and server UTC)', () {
      expect(AdminUserCubit.validateValidUntil(null, today, nowUtc: nowUtc), isNotNull);
      expect(AdminUserCubit.validateValidUntil(today, today, nowUtc: nowUtc), isNotNull);
      expect(AdminUserCubit.validateValidUntil(DateTime(2026, 10, 5), today, nowUtc: nowUtc), isNull);
      // 21:00 in Guayaquil is already the 5th in UTC: the 5th is not accepted by the API.
      final lateUtc = DateTime.utc(2026, 10, 5, 2);
      expect(AdminUserCubit.firstValidUntil(today, nowUtc: lateUtc), DateTime(2026, 10, 6));
    });

    blocTest<AdminUserCubit, AdminUserState>(
      'plan change: busy, then the user with the new plan and what was enforced',
      setUp: () => when(() => admin.setUserPlan('u-carlos', planId: 2, validUntil: DateTime(2099, 1, 1)))
          .thenAnswer((_) async => PlanAssignment(planId: 2, planName: 'Contador', validUntil: DateTime(2099, 1, 1))),
      build: () => AdminUserCubit(admin, user: adminUser()),
      act: (cubit) => cubit.changePlan(contador, DateTime(2099, 1, 1), today: DateTime.now()),
      expect: () => [
        AdminUserState(user: adminUser(), busy: AdminUserAction.plan),
        AdminUserState(
          user: adminUser(plan: 'Contador', validUntil: DateTime(2099, 1, 1)),
          done: AdminUserAction.plan,
          assignment: PlanAssignment(planId: 2, planName: 'Contador', validUntil: DateTime(2099, 1, 1)),
        ),
      ],
    );

    blocTest<AdminUserCubit, AdminUserState>(
      'a past date is refused locally, without a request',
      build: () => AdminUserCubit(admin, user: adminUser()),
      act: (cubit) => cubit.changePlan(contador, DateTime(2020, 1, 1), today: DateTime.now()),
      expect: () => [isA<AdminUserState>().having((s) => s.failure?.kind, 'kind', FailureKind.validation)],
      verify: (_) => verifyZeroInteractions(admin),
    );

    test('a 403 is shown neutrally and reloads our profile (the role may have changed)', () async {
      when(() => admin.setUserPlan('u-carlos', planId: 2, validUntil: any(named: 'validUntil'))).thenThrow(_forbidden);
      var reloads = 0;
      final cubit = AdminUserCubit(admin, user: adminUser(), onForbidden: () => reloads++);
      expect(await cubit.changePlan(contador, DateTime(2099, 1, 1), today: DateTime.now()), isFalse);
      expect(cubit.state.failure!.message, adminForbiddenMessage);
      expect(cubit.state.user.planId, adminUser().planId);
      expect(reloads, 1);
      await cubit.close();
    });
  });
}
