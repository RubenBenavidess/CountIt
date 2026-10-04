import 'package:flutter/material.dart';

import '../../../../app/theme/app_theme.dart';
import '../../../../app/theme/tokens.dart';
import '../../../../data/dtos/budget.dart';
import '../../../../shared/utils/dates.dart';
import '../../../../shared/widgets/app_card.dart';
import 'budget_icon.dart';
import 'budget_progress.dart';

/// Budget of a wallet (HU-12 · COU-219): category, period with the current
/// window, progress and what is left. [today] is the user's calendar day.
class BudgetCard extends StatelessWidget {
  const BudgetCard({super.key, required this.budget, required this.today, this.onTap});

  final Budget budget;
  final DateTime today;
  final VoidCallback? onTap;

  /// «Mensual · 1 oct – 31 oct 2026», or when it starts / ended.
  static String windowLabel(Budget budget, DateTime today) {
    if (budget.hasEnded(today)) return 'Finalizó el ${Dates.date(budget.endDate!)}';
    if (budget.hasNotStarted(today)) return '${budget.period.label} · empieza el ${Dates.date(budget.startDate)}';
    final start = budget.windowStart;
    final end = budget.windowEnd;
    if (start == null || end == null) return budget.period.label;
    return '${budget.period.label} · ${Dates.range(start, end)}';
  }

  String _semantics(String window) => [
    'Presupuesto de ${budget.type.label.toLowerCase()} ${budget.name}',
    window,
    '${budget.spentVerb} ${budget.amountsLabel}, ${budget.percentLabel}',
    ?budget.statusLabel,
    budget.balanceLabel,
  ].join('. ');

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final window = windowLabel(budget, today);
    return AppCard(
      onTap: onTap,
      semanticLabel: _semantics(window),
      child: ExcludeSemantics(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: AppSpacing.md,
          children: [
            Row(
              spacing: AppSpacing.md,
              children: [
                IconTile(budget.icon.iconData, color: budget.isIncome ? palette.income : AppColors.lavender),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(budget.name, style: AppTypography.h2, maxLines: 1, overflow: TextOverflow.ellipsis),
                      Text(
                        window,
                        style: AppTypography.caption.copyWith(color: palette.muted),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                if (budget.isIncome) const AppBadge('Ingreso', tone: BadgeTone.ok),
              ],
            ),
            BudgetProgress(budget: budget),
          ],
        ),
      ),
    );
  }
}
