import 'package:flutter/material.dart';

import '../../../data/dtos/profile.dart';

/// One quota of the plan: «Billeteras · 10», «Movimientos por día · Ilimitados».
class PlanQuota {
  const PlanQuota(this.icon, this.label, this.value);

  final IconData icon;
  final String label;
  final String value;
}

/// A plan feature and whether the plan includes it.
class PlanFeature {
  const PlanFeature(this.label, {required this.included});

  final String label;
  final bool included;
}

/// Quotas of [plan] in display order; limits the plan does not define are skipped.
List<PlanQuota> planQuotas(UserPlan plan) {
  String value(String key, {bool feminine = false}) {
    final quota = plan.quota(key);
    return quota == null ? (feminine ? 'Ilimitadas' : 'Ilimitados') : '$quota';
  }

  final families = plan.hasFeature(PlanFeatures.families);
  return [
    if (plan.limits.containsKey('max_wallets'))
      PlanQuota(Icons.account_balance_wallet_outlined, 'Billeteras', value('max_wallets', feminine: true)),
    if (plan.limits.containsKey('max_budgets_per_wallet'))
      PlanQuota(Icons.pie_chart_outline_rounded, 'Presupuestos por billetera', value('max_budgets_per_wallet')),
    if (plan.limits.containsKey('max_daily_transactions'))
      PlanQuota(Icons.swap_vert_rounded, 'Movimientos por día', value('max_daily_transactions')),
    if (plan.limits.containsKey('max_scheduled_transactions'))
      PlanQuota(Icons.event_repeat_rounded, 'Programadas activas', value('max_scheduled_transactions', feminine: true)),
    if (families && plan.limits.containsKey('max_families'))
      PlanQuota(Icons.group_outlined, 'Billeteras compartidas', value('max_families', feminine: true)),
    if (families && plan.limits.containsKey('max_family_users'))
      PlanQuota(Icons.person_add_alt_outlined, 'Miembros por billetera', value('max_family_users')),
  ];
}

/// Plan features, included or not (the latter invite to a higher plan).
List<PlanFeature> planFeatures(UserPlan plan) => [
  PlanFeature('Billeteras compartidas', included: plan.hasFeature(PlanFeatures.families)),
  PlanFeature('Estadísticas avanzadas', included: plan.hasFeature(PlanFeatures.advancedStatistics)),
  PlanFeature('Proyección de saldo', included: plan.hasFeature(PlanFeatures.walletProjection)),
];
