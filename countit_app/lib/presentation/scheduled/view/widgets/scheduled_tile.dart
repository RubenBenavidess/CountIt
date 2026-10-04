import 'package:flutter/material.dart';

import '../../../../app/theme/app_theme.dart';
import '../../../../app/theme/tokens.dart';
import '../../../../data/dtos/scheduled_transaction.dart';
import '../../../../shared/utils/dates.dart';
import '../../../../shared/utils/money.dart';
import '../../../../shared/widgets/app_card.dart';
import '../../../budgets/view/widgets/budget_icon.dart';

/// Texts shared by the row and the form of a scheduled rule.
extension ScheduledLabels on ScheduledTransaction {
  /// «+ $450,00» / «− $12,50»: the sign always travels with the colour.
  String get signedAmount => Money.signed(amount, income: isIncome);

  String get budgetLabel => budgetName ?? 'Sin presupuesto';

  String get authorLabel => authorName ?? 'Autor desconocido';

  /// «Próxima: 5 oct 2026», or «Pausada» (the paused period is skipped on resume).
  String get nextRunLabel {
    if (isPaused) return 'Pausada';
    final next = nextRunDate;
    return next == null ? 'Sin próxima ejecución' : 'Próxima: ${Dates.date(next)}';
  }

  /// Category icon of its budget, or the direction of the money without one.
  IconData get iconData => hasBudget
      ? budgetIcon.iconData
      : isIncome
      ? Icons.south_west_rounded
      : Icons.north_east_rounded;

  /// What a screen reader announces: type, name, signed amount in words,
  /// frequency, next run or pause, end, budget and author.
  String semanticLabel({required bool showAuthor}) {
    final next = nextRunDate;
    final end = endDate;
    return [
      '${type.label} programado $name',
      '${isIncome ? 'más' : 'menos'} ${Money.format(amount)}',
      frequencyLabel,
      if (isPaused) 'pausada' else if (next != null) 'próxima ejecución ${Dates.long(next)}',
      if (periodicity.recurs && end != null) 'hasta el ${Dates.long(end)}',
      hasBudget ? 'presupuesto $budgetName' : 'sin presupuesto',
      if (showAuthor) 'programada por $authorLabel',
    ].join(', ');
  }
}

/// A scheduled rule in the wallet's list (HU-16/HU-20 · COU-88): category,
/// name, frequency and next run (or «Pausada»), signed amount, and an
/// optional [trailing] action (pause/resume).
class ScheduledTile extends StatelessWidget {
  const ScheduledTile({super.key, required this.rule, this.showAuthor = false, this.onTap, this.trailing});

  final ScheduledTransaction rule;

  /// Shared wallets say who scheduled each rule.
  final bool showAuthor;
  final VoidCallback? onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final r = rule;
    final color = r.isIncome ? palette.income : palette.expense;
    final details = [r.frequencyLabel, if (!r.isPaused) r.nextRunLabel].join(' · ');
    final secondary = showAuthor ? '${r.budgetLabel} · ${r.authorLabel}' : r.budgetLabel;
    final row = Semantics(
      button: onTap != null,
      label: r.semanticLabel(showAuthor: showAuthor),
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadii.md),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 64),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
            child: Row(
              spacing: AppSpacing.md,
              children: [
                Opacity(
                  opacity: r.isPaused ? 0.55 : 1,
                  child: IconTile(r.iconData, color: r.hasBudget ? AppColors.lavender : color),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    spacing: 2,
                    children: [
                      Text(r.name, style: AppTypography.label, maxLines: 1, overflow: TextOverflow.ellipsis),
                      Row(
                        spacing: AppSpacing.xs,
                        children: [
                          if (r.isPaused) const AppBadge('Pausada', tone: BadgeTone.warn),
                          Flexible(
                            child: Text(
                              details,
                              style: AppTypography.caption.copyWith(color: palette.muted),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                      Text(
                        secondary,
                        style: AppTypography.caption.copyWith(color: palette.muted),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                Text(r.signedAmount, style: AppTypography.money.copyWith(fontSize: 15, color: color)),
              ],
            ),
          ),
        ),
      ),
    );
    final action = trailing;
    return action == null
        ? row
        : Row(
            children: [
              Expanded(child: row),
              action,
            ],
          );
  }
}
