import '../../../data/dtos/profile.dart';

/// Short Spanish lines describing what a plan includes (design Perfil:
/// «10 billeteras», «14 presupuestos c/u», «Estadísticas avanzadas»…).
List<String> planHighlights(UserPlan plan) {
  String count(String key, String one, String many, {String suffix = ''}) {
    final value = plan.quota(key);
    if (value == null) return '${many[0].toUpperCase()}${many.substring(1)} ilimitados$suffix';
    return '$value ${value == 1 ? one : many}$suffix';
  }

  return [
    if (plan.limits.containsKey('max_wallets'))
      plan.quota('max_wallets') == null ? 'Billeteras ilimitadas' : count('max_wallets', 'billetera', 'billeteras'),
    if (plan.limits.containsKey('max_budgets_per_wallet'))
      count('max_budgets_per_wallet', 'presupuesto', 'presupuestos', suffix: ' c/u'),
    if (plan.limits.containsKey('max_daily_transactions'))
      count('max_daily_transactions', 'movimiento', 'movimientos', suffix: ' al día'),
    if (plan.limits.containsKey('max_scheduled_transactions'))
      count('max_scheduled_transactions', 'programado', 'programados'),
    if (plan.hasFeature('family_feature'))
      '${count('max_families', 'familia', 'familias')} · ${count('max_family_users', 'miembro', 'miembros')}',
    if (plan.hasFeature('advanced_statistics')) 'Estadísticas avanzadas',
    if (plan.hasFeature('wallet_projection')) 'Proyección de saldo',
  ];
}
