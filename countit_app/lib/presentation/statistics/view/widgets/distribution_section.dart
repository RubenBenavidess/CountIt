import 'package:flutter/material.dart';

import '../../../../app/theme/app_theme.dart';
import '../../../../app/theme/tokens.dart';
import '../../../../data/dtos/statistics.dart';
import '../../../../shared/utils/money.dart';
import '../../../../shared/widgets/section_header.dart';

/// Distribution by budget (HU-26, plan feature `advanced_statistics`):
/// expenses and incomes of the range per budget, largest first, as the API
/// sorted them. Rows are built lazily (a Pro wallet may have many budgets).
class DistributionSection extends StatelessWidget {
  const DistributionSection({super.key, required this.distribution});

  final BudgetDistribution distribution;

  @override
  Widget build(BuildContext context) {
    return SliverMainAxisGroup(
      slivers: [
        ..._group(context, 'Gastos por presupuesto', distribution.expenses, income: false),
        const SliverToBoxAdapter(child: SizedBox(height: AppSpacing.xxl)),
        ..._group(context, 'Ingresos por presupuesto', distribution.incomes, income: true),
      ],
    );
  }

  List<Widget> _group(BuildContext context, String title, List<BudgetShare> shares, {required bool income}) => [
    SliverToBoxAdapter(child: SectionHeader(title: title)),
    if (shares.isEmpty)
      SliverToBoxAdapter(
        child: Text(
          income ? 'Sin ingresos en este periodo.' : 'Sin gastos en este periodo.',
          style: AppTypography.caption.copyWith(color: context.palette.muted),
        ),
      )
    else
      SliverList.builder(
        itemCount: shares.length,
        itemBuilder: (context, index) => BudgetShareRow(share: shares[index], income: income),
      ),
  ];
}

/// One budget (COU-94): name, signed amount, share and a horizontal bar of
/// that share, read as one sentence. The bar is a plain box (no painter):
/// rows are built lazily and stay cheap.
class BudgetShareRow extends StatelessWidget {
  const BudgetShareRow({super.key, required this.share, required this.income});

  final BudgetShare share;
  final bool income;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final amount = Money.signed(share.amount, income: income);
    return Semantics(
      label: '${share.budgetName}: $amount, ${Percent.format(share.pct)} del total',
      container: true,
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: 6,
          children: [
            Row(
              spacing: AppSpacing.md,
              children: [
                Expanded(
                  child: Text(share.budgetName, style: AppTypography.label, overflow: TextOverflow.ellipsis),
                ),
                Text(
                  amount,
                  style: AppTypography.money.copyWith(fontSize: 14, color: income ? palette.income : palette.expense),
                ),
                SizedBox(
                  width: 56,
                  child: Text(
                    Percent.format(share.pct),
                    textAlign: TextAlign.end,
                    style: AppTypography.caption.copyWith(color: palette.muted),
                  ),
                ),
              ],
            ),
            ShareBar(fraction: share.pct / 100, color: income ? palette.income : palette.expense),
          ],
        ),
      ),
    );
  }
}

/// 6 px bar: [fraction] (0–1) of the width in [color] over the track.
class ShareBar extends StatelessWidget {
  const ShareBar({super.key, required this.fraction, required this.color});

  final double fraction;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(3);
    return Container(
      height: 6,
      alignment: Alignment.centerLeft,
      decoration: BoxDecoration(color: context.palette.surface2, borderRadius: radius),
      child: FractionallySizedBox(
        widthFactor: fraction.clamp(0, 1),
        heightFactor: 1,
        child: DecoratedBox(
          decoration: BoxDecoration(color: color, borderRadius: radius),
        ),
      ),
    );
  }
}
