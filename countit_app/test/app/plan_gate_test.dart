import 'package:countit_app/app/errors/app_failure.dart';
import 'package:countit_app/app/plans/plan_gate.dart';
import 'package:countit_app/data/dtos/profile.dart';
import 'package:flutter_test/flutter_test.dart';

const _regular = UserPlan(
  planId: 1,
  name: 'Regular',
  monthlyPriceCents: 0,
  limits: {'max_wallets': 3, 'family_feature': 0, 'wallet_projection': 0, 'max_daily_transactions': 999},
);

void main() {
  group('PlanGate (COU-121)', () {
    test('features: false only when the known plan lacks them', () {
      const gate = PlanGate(_regular);
      expect(gate.allows(PlanFeatures.families), isFalse);
      expect(gate.allows(PlanFeatures.walletProjection), isFalse);
      expect(gate.allows('unknown_feature'), isFalse, reason: 'missing flag = not included');
    });

    test('without a plan everything is allowed: the API decides', () {
      const gate = PlanGate(null);
      expect(gate.allows(PlanFeatures.families), isTrue);
      expect(gate.quota('max_wallets'), isNull);
      expect(gate.canAdd('max_wallets', used: 100), isTrue);
    });

    test('quotas: 999 means unlimited; canAdd only false when usage is known to fill it', () {
      const gate = PlanGate(_regular);
      expect(gate.quota('max_wallets'), 3);
      expect(gate.quota('max_daily_transactions'), isNull);
      expect(gate.canAdd('max_wallets', used: 2), isTrue);
      expect(gate.canAdd('max_wallets', used: 3), isFalse);
      expect(gate.canAdd('max_wallets', used: null), isTrue);
      expect(gate.canAdd('max_daily_transactions', used: 5000), isTrue);
    });
  });

  test('PlanNotices broadcasts every feature_not_in_plan (COU-183)', () async {
    final notices = PlanNotices();
    const failure = AppFailure(kind: FailureKind.featureNotInPlan, message: 'Tu plan no incluye familias');
    final received = <AppFailure>[];
    final subscription = notices.featureNotInPlan.listen(received.add);
    notices.report(failure);
    await Future<void>.delayed(Duration.zero);
    expect(received, [failure]);
    await subscription.cancel();
    await notices.dispose();
    notices.report(failure); // closed: ignored, no throw
  });
}
