import 'package:flutter/material.dart';

import '../../../../app/theme/app_theme.dart';
import '../../../../app/theme/tokens.dart';
import '../../../../data/dtos/transaction.dart';
import '../../../../shared/utils/dates.dart';
import '../../../../shared/utils/money.dart';
import '../../../../shared/widgets/app_card.dart';
import '../../../budgets/view/widgets/budget_icon.dart';

/// Texts shared by the row and the detail screen of a transaction.
extension TransactionLabels on Transaction {
  /// «Sin presupuesto» when it has none.
  String get budgetLabel => budgetName ?? 'Sin presupuesto';

  /// «+ $450,00» / «− $12,50»: the sign always travels with the colour.
  String get signedAmount => Money.signed(amount, income: isIncome);

  /// The author as shown; the API may send no name (API 1.1).
  String get authorLabel => authorName ?? 'Autor desconocido';

  /// Category icon of its budget, or the direction of the money without one.
  IconData get iconData => hasBudget
      ? budgetIcon.iconData
      : isIncome
      ? Icons.south_west_rounded
      : Icons.north_east_rounded;

  /// What a screen reader announces for the row: type, name, amount with its
  /// sign in words, date, budget and author.
  String semanticLabel({required bool showAuthor}) => [
    '${type.label} $name',
    '${isIncome ? 'más' : 'menos'} ${Money.format(amount)}',
    Dates.long(date),
    hasBudget ? 'Presupuesto $budgetName' : 'Sin presupuesto',
    if (showAuthor) 'Registrado por $authorLabel',
  ].join(', ');
}

/// A transaction in the wallet list (HU-17 · COU-231): category, name,
/// budget (and author in shared wallets) and the signed amount.
class TransactionTile extends StatelessWidget {
  const TransactionTile({super.key, required this.transaction, this.showAuthor = false, this.onTap});

  final Transaction transaction;

  /// Shared wallets say who registered each movement.
  final bool showAuthor;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final t = transaction;
    final color = t.isIncome ? palette.income : palette.expense;
    final subtitle = showAuthor ? '${t.budgetLabel} · ${t.authorLabel}' : t.budgetLabel;
    return Semantics(
      button: onTap != null,
      label: t.semanticLabel(showAuthor: showAuthor),
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
                IconTile(t.iconData, color: t.hasBudget ? AppColors.lavender : color),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(t.name, style: AppTypography.label, maxLines: 1, overflow: TextOverflow.ellipsis),
                      Text(
                        subtitle,
                        style: AppTypography.caption.copyWith(color: palette.muted),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                Text(t.signedAmount, style: AppTypography.money.copyWith(fontSize: 15, color: color)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// «Hoy», «Ayer» or the long date above the movements of that day.
class TransactionDayLabel extends StatelessWidget {
  const TransactionDayLabel({super.key, required this.day, required this.today});

  final DateTime day;
  final DateTime today;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.lg, bottom: AppSpacing.xs),
      child: Semantics(
        header: true,
        child: Text(
          Dates.dayHeader(day, today: today),
          style: AppTypography.overline.copyWith(color: context.palette.muted, letterSpacing: 0.2),
        ),
      ),
    );
  }
}
