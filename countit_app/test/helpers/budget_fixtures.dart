import 'package:countit_app/data/dtos/budget.dart';

/// Budget as `v_budgets` would return it; amounts in dollars for readability.
/// The window defaults to October 2026 and [progressPct]/[isExceeded] follow
/// [spent] like the view computes them.
Budget budgetFixture({
  int id = 1,
  int walletId = 4,
  String name = 'Comida',
  BudgetType type = BudgetType.expense,
  BudgetPeriod period = BudgetPeriod.monthly,
  BudgetIcon? icon = BudgetIcon.food,
  double limit = 100,
  double spent = 40,
  DateTime? startDate,
  DateTime? endDate,
  DateTime? windowStart,
  DateTime? windowEnd,
  String? createdBy = 'u1',
}) {
  final limitCents = (limit * 100).round();
  final spentCents = (spent * 100).round();
  return Budget(
    budgetId: id,
    walletId: walletId,
    name: name,
    type: type,
    period: period,
    icon: icon,
    limitCents: limitCents,
    spentCents: spentCents,
    remainingCents: limitCents - spentCents,
    progressPct: (spent * 10000 / limit).round() / 100,
    isExceeded: spentCents > limitCents,
    startDate: startDate ?? DateTime(2026, 9, 1),
    endDate: endDate,
    windowStart: windowStart ?? DateTime(2026, 10, 1),
    windowEnd: windowEnd ?? DateTime(2026, 10, 31),
    createdBy: createdBy,
  );
}
