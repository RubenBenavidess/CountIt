import 'package:countit_app/app/errors/app_failure.dart';
import 'package:countit_app/data/dtos/bank.dart';
import 'package:countit_app/data/dtos/json_parsing.dart';
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

  group('banks (HU-27 · COU-205…COU-207)', () {
    final bankJson = {
      'bank_id': 15,
      'name': 'Banco Nuevo',
      'country_code': 'EC',
      'color': '#00843D',
      'is_active': true,
      'created_at': '2026-10-04T15:00:00Z',
      'updated_at': '2026-10-04T15:00:00Z',
    };

    test('listBanks keeps inactive banks (admins see every bank)', () async {
      when(
        () => api.select(
          any(),
          columns: any(named: 'columns'),
          query: any(named: 'query'),
        ),
      ).thenAnswer(
        (_) async => [
          {'bank_id': 1, 'name': 'Banco Pichincha', 'country_code': 'EC', 'is_active': true, 'color': '#FFDD00'},
          {'bank_id': 2, 'name': 'Produbanco', 'country_code': 'EC', 'is_active': false, 'color': null},
        ],
      );
      final banks = await admin.listBanks();
      expect(banks.map((b) => (b.name, b.isActive)), [('Banco Pichincha', true), ('Produbanco', false)]);
      expect(banks.first.color, 0xFFFFDD00);
      verify(() => api.select('v_banks', query: any(named: 'query'))).called(1);
    });

    test('create sends the colour as #RRGGBB', () async {
      rpcReturns(bankJson);
      final bank = await admin.createBank(const BankInput(name: 'Banco Nuevo', countryCode: 'EC', color: 0xFF00843D));
      expect(bank.bankId, 15);
      expect(bank.color, 0xFF00843D);
      verify(
        () => api.rpc<dynamic>(
          'admin_create_bank',
          params: {'p_name': 'Banco Nuevo', 'p_country_code': 'EC', 'p_color': '#00843D'},
        ),
      ).called(1);
    });

    test('update without colour omits p_color (the API then removes it)', () async {
      rpcReturns({...bankJson, 'color': null});
      final bank = await admin.updateBank(15, const BankInput(name: 'Banco Nuevo', countryCode: 'EC'));
      expect(bank.color, isNull);
      verify(
        () => api.rpc<dynamic>(
          'admin_update_bank',
          params: {'p_bank_id': 15, 'p_name': 'Banco Nuevo', 'p_country_code': 'EC'},
        ),
      ).called(1);
    });

    test('setBankActive returns the saved bank', () async {
      rpcReturns({...bankJson, 'is_active': false});
      final bank = await admin.setBankActive(15, active: false);
      expect(bank.isActive, isFalse);
      verify(() => api.rpc<dynamic>('admin_set_bank_active', params: {'p_bank_id': 15, 'p_active': false})).called(1);
    });

    test('hex helper round-trips', () {
      expect(toHexColor(0xFF0072BC), '#0072BC');
      expect(parseHexColor(toHexColor(0xFF0072BC)), 0xFF0072BC);
      expect(toHexColor(null), isNull);
    });
  });
}
