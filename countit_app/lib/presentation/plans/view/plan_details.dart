import 'package:flutter/material.dart';

import '../../../data/dtos/json_parsing.dart';
import '../../../data/dtos/profile.dart';
import '../../../shared/utils/dates.dart';
import '../../../shared/utils/money.dart';

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

/// «$2,99 al mes» / «Gratis»; null when the price is unknown.
String? planPrice(UserPlan plan) {
  final cents = plan.monthlyPriceCents;
  if (cents == null) return null;
  return cents == 0 ? 'Gratis' : '${Money.format(Cents.toAmount(cents))} al mes';
}

/// The expiry notice of [plan] on [today] (COU-117); null when none is due.
String? planExpiryMessage(UserPlan plan, DateTime today) {
  final expiry = plan.expiryOn(today);
  final end = plan.validUntil;
  if (!expiry.needsNotice || end == null) return null;
  const after = 'Después pasarás al plan Regular y se aplicarán sus límites.';
  return switch (expiry.daysLeft!) {
    < 0 => 'Tu plan ${plan.name} venció el ${Dates.date(end)}. En unas horas pasarás al plan Regular.',
    0 => 'Tu plan ${plan.name} termina hoy. $after',
    1 => 'Tu plan ${plan.name} vence mañana, el ${Dates.date(end)}. $after',
    final days => 'Tu plan ${plan.name} vence en $days días, el ${Dates.date(end)}. $after',
  };
}

/// Short label for a pill: «Vence el 4 oct 2027», «Vence en 2 días», «Vencido».
String? planValidityLabel(UserPlan plan, DateTime today) {
  final end = plan.validUntil;
  if (end == null || !plan.isPaid) return null;
  final expiry = plan.expiryOn(today);
  return switch (expiry.daysLeft) {
    null => 'Vence el ${Dates.date(end)}',
    < 0 => 'Vencido',
    0 => 'Vence hoy',
    1 => 'Vence mañana',
    final days => 'Vence en $days días',
  };
}
