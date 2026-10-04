import 'package:flutter/material.dart';

import '../../../../app/theme/app_theme.dart';
import '../../../../app/theme/tokens.dart';
import '../../../../data/dtos/budget.dart';
import '../../../../shared/utils/money.dart';
import '../../../../shared/widgets/app_card.dart';

/// Texts and tones the budget widgets show, derived from the row only, so
/// the card and the indicator never disagree (COU-218).
extension BudgetDisplay on Budget {
  /// «85 %»: rounded down, so 99.6 % never reads as a full budget.
  String get percentLabel => '${progressPct.floor()} %';

  /// «$85,00 de $100,00».
  String get amountsLabel => '${Money.format(spent)} de ${Money.format(limit)}';

  /// Status in words: colour never carries the meaning alone.
  String? get statusLabel => switch (status) {
    BudgetStatus.warning => 'Cerca del límite',
    BudgetStatus.exceeded => 'Excedido',
    BudgetStatus.goalReached => 'Meta alcanzada',
    BudgetStatus.onTrack || BudgetStatus.inProgress => null,
  };

  /// What is left (or over) in the current window.
  String get balanceLabel => switch (status) {
    BudgetStatus.exceeded => 'Te pasaste por ${Money.format(-remaining)}',
    BudgetStatus.goalReached =>
      remainingCents == 0 ? 'Alcanzaste la meta' : 'Superaste la meta por ${Money.format(-remaining)}',
    BudgetStatus.inProgress => 'Faltan ${Money.format(remaining)} para la meta',
    BudgetStatus.onTrack || BudgetStatus.warning => 'Te quedan ${Money.format(remaining)}',
  };

  ProgressTone get progressTone => switch (status) {
    BudgetStatus.exceeded => ProgressTone.over,
    BudgetStatus.goalReached || BudgetStatus.inProgress => ProgressTone.income,
    BudgetStatus.onTrack || BudgetStatus.warning => ProgressTone.normal,
  };

  /// «Gastado» / «Recibido» for screen readers.
  String get spentVerb => isIncome ? 'Recibido' : 'Gastado';
}

/// Progress of the current window: bar, «$x de $y» with the percentage,
/// what is left and, from 80 % on, an icon + word for the status (COU-218).
class BudgetProgress extends StatelessWidget {
  const BudgetProgress({super.key, required this.budget});

  final Budget budget;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final status = budget.statusLabel;
    final statusColor = budget.status == BudgetStatus.goalReached ? palette.income : palette.expense;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: AppSpacing.sm,
      children: [
        AppProgressBar(value: budget.progress, tone: budget.progressTone),
        Row(
          spacing: AppSpacing.sm,
          children: [
            Expanded(
              child: Text(
                budget.amountsLabel,
                style: AppTypography.money.copyWith(fontSize: 14),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Text(budget.percentLabel, style: AppTypography.money.copyWith(fontSize: 14, color: palette.muted)),
          ],
        ),
        Row(
          spacing: AppSpacing.xs,
          children: [
            Expanded(
              child: Text(budget.balanceLabel, style: AppTypography.caption.copyWith(color: palette.muted)),
            ),
            if (status != null) ...[
              Icon(_statusIcon(budget.status), size: 16, color: statusColor),
              Text(
                status,
                style: AppTypography.caption.copyWith(color: statusColor, fontWeight: FontWeight.w700),
              ),
            ],
          ],
        ),
      ],
    );
  }

  static IconData _statusIcon(BudgetStatus status) => switch (status) {
    BudgetStatus.exceeded => Icons.error_outline_rounded,
    BudgetStatus.goalReached => Icons.check_circle_outline_rounded,
    _ => Icons.warning_amber_rounded,
  };
}
