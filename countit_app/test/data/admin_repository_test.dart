import 'package:countit_app/app/errors/app_failure.dart';
import 'package:countit_app/data/dtos/profile.dart';
import 'package:countit_app/data/repositories/admin_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../helpers/admin_fixtures.dart';
import '../helpers/mocks.dart';

void main() {
  late MockApiClient api;
  late SupabaseAdminRepository admin;

  setUp(() {
    api = MockApiClient();
    admin = SupabaseAdminRepository(api);
  });

  void rpcReturns(Object? json) =>
      when(() => api.rpc<dynamic>(any(), params: any(named: 'params'))).thenAnswer((_) async => json);

  group('listUsers (admin_list_users · COU-184)', () {
    test('asks one row more than the page to know if there is another', () async {
      rpcReturns([for (var i = 0; i < 31; i++) adminUserJson(id: 'u$i', username: 'user$i')]);
      final page = await admin.listUsers(search: '  carlos ', offset: 30);
      expect(page.items, hasLength(30));
      expect(page.hasMore, isTrue);
      verify(() => api.rpc<dynamic>('admin_list_users', params: {'p_search': 'carlos', 'p_limit': 31, 'p_offset': 30}))
          .called(1);
    });

    test('a short page is the last; an empty search is not sent', () async {
      rpcReturns([adminUserJson(role: 'superadmin', plan: null, validUntil: null)]);
      final page = await admin.listUsers(search: '   ');
      expect(page.hasMore, isFalse);
      final user = page.items.single;
      expect(user.role, UserRole.superadmin);
      expect(user.planName, isNull);
      expect(user.displayName, 'Carlos Pérez');
      verify(() => api.rpc<dynamic>('admin_list_users', params: {'p_limit': 31, 'p_offset': 0})).called(1);
    });

    test('parses the row', () async {
      rpcReturns([adminUserJson()]);
      final user = (await admin.listUsers()).items.single;
      expect(user, adminUser());
    });

    test('an unexpected answer is a server failure', () async {
      rpcReturns({'oops': true});
      await expectLater(
        admin.listUsers(),
        throwsA(isA<AppFailure>().having((f) => f.kind, 'kind', FailureKind.server)),
      );
    });
  });

  test('setUserPlan: date as yyyy-MM-dd and what the downgrade enforced (COU-203)', () async {
    rpcReturns({
      'user_id': 'u-carlos',
      'user_plan_id': 9,
      'plan_id': 1,
      'plan': 'Regular',
      'valid_from': '2026-10-04',
      'valid_until': '2026-11-04',
      'enforced': {'memberships_ended': 2, 'member_rules_ended': 0, 'rules_paused': 1},
    });
    final result = await admin.setUserPlan('u-carlos', planId: 1, validUntil: DateTime(2026, 11, 4));
    expect(result.planName, 'Regular');
    expect(result.validUntil, DateTime(2026, 11, 4));
    expect(result.membershipsEnded, 2);
    expect(result.rulesPaused, 1);
    expect(result.enforcedAnything, isTrue);
    verify(
      () => api.rpc<dynamic>(
        'admin_set_user_plan',
        params: {'p_user_id': 'u-carlos', 'p_plan_id': 1, 'p_valid_until': '2026-11-04'},
      ),
    ).called(1);
  });

  test('setUserRole sends the role name and returns the saved role (COU-204)', () async {
    rpcReturns({'user_id': 'u-carlos', 'username': 'demo_carlos', 'role': 'admin'});
    expect(await admin.setUserRole('u-carlos', UserRole.admin), UserRole.admin);
    verify(() => api.rpc<dynamic>('admin_set_user_role', params: {'p_user_id': 'u-carlos', 'p_role': 'admin'}))
        .called(1);
  });
}
