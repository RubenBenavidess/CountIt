import 'package:countit_app/data/dtos/plan_catalog.dart';
import 'package:countit_app/data/dtos/profile.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // Shape of api.get_my_profile() in CountIt-Backend-Dev.
  final json = <String, dynamic>{
    'user_id': '7f9c',
    'username': 'demo_ana',
    'first_name': 'Ana',
    'last_name': 'Quishpe',
    'email': 'ana@test.com',
    'timezone': 'America/Guayaquil',
    'role': 'superadmin',
    'created_at': '2026-10-03T21:00:00Z',
    'plan': {
      'plan_id': 2,
      'name': 'Contador',
      'monthly_price': 2.99,
      'valid_until': '2027-10-03',
      'limits': {
        'max_wallets': 10,
        'max_daily_transactions': 40,
        'family_feature': 1,
        'wallet_projection': 0,
        'max_budgets_per_wallet': 999,
      },
    },
  };

  test('parses get_my_profile', () {
    final p = Profile.fromJson(json);
    expect(p.displayName, 'Ana Quishpe');
    expect(p.role, UserRole.superadmin);
    expect(p.role.canAdminister, isTrue);
    expect(p.plan!.name, 'Contador');
    expect(p.plan!.validUntil, DateTime(2027, 10, 3));
  });

  test('plan features and quotas (999 = unlimited)', () {
    final plan = Profile.fromJson(json).plan!;
    expect(plan.hasFeature('family_feature'), isTrue);
    expect(plan.hasFeature('wallet_projection'), isFalse);
    expect(plan.hasFeature('advanced_statistics'), isFalse, reason: 'missing limits count as off');
    expect(plan.quota('max_wallets'), 10);
    expect(plan.quota('max_budgets_per_wallet'), isNull);
  });

  test('falls back to the username and the user role', () {
    final p = Profile.fromJson({'user_id': 'x', 'username': 'carlos', 'role': 'unknown'});
    expect(p.displayName, 'carlos');
    expect(p.role, UserRole.user);
    expect(p.plan, isNull);
  });

  group('plan model (COU-34)', () {
    test('monthly_price in cents; paid only above zero', () {
      final plan = Profile.fromJson(json).plan!;
      expect(plan.monthlyPriceCents, 299);
      expect(plan.isPaid, isTrue);
      const regular = UserPlan(planId: 1, name: 'Regular', limits: {}, monthlyPriceCents: 0);
      expect(regular.isPaid, isFalse);
    });

    test('expiry (COU-117): notice from 3 days before, expired after valid_until', () {
      final plan = UserPlan(
        planId: 2,
        name: 'Contador',
        limits: const {},
        monthlyPriceCents: 299,
        validUntil: DateTime(2026, 10, 10),
      );
      expect(plan.expiryOn(DateTime(2026, 10, 6)), PlanExpiry.none);
      expect(plan.expiryOn(DateTime(2026, 10, 7)), const PlanExpiry(PlanExpiryStatus.expiringSoon, daysLeft: 3));
      expect(plan.expiryOn(DateTime(2026, 10, 10)), const PlanExpiry(PlanExpiryStatus.expiringSoon, daysLeft: 0));
      expect(plan.expiryOn(DateTime(2026, 10, 11)), const PlanExpiry(PlanExpiryStatus.expired, daysLeft: -1));
    });

    test('the free plan never expires (the backend only expires paid plans)', () {
      final regular = UserPlan(
        planId: 1,
        name: 'Regular',
        limits: const {},
        monthlyPriceCents: 0,
        validUntil: DateTime(2026, 10, 5),
      );
      expect(regular.expiryOn(DateTime(2026, 10, 9)), PlanExpiry.none);
    });

    test('roles: labels and superadmin', () {
      expect(UserRole.superadmin.isSuperadmin, isTrue);
      expect(UserRole.admin.isSuperadmin, isFalse);
      expect(UserRole.admin.canAdminister, isTrue);
      expect(UserRole.values.map((r) => r.label), ['Usuario', 'Administrador', 'Superadministrador']);
    });

    test('catalogue mirrors the backend seed: Regular free, ids 1..3', () {
      expect(PlanCatalog.all.map((o) => o.planId), [1, 2, 3]);
      expect(PlanCatalog.byId(PlanCatalog.regularId)!.plan.isPaid, isFalse);
      expect(PlanCatalog.byName('Contador Profesional')!.plan.hasFeature(PlanFeatures.walletProjection), isTrue);
      expect(PlanCatalog.byName('Contador')!.plan.quota('max_scheduled_transactions'), 10);
      expect(PlanCatalog.byId(9), isNull);
    });
  });
}
