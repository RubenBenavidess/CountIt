import 'package:flutter/material.dart';
import 'package:intl/intl.dart' show NumberFormat;

import '../../../../app/theme/app_theme.dart';
import '../../../../app/theme/tokens.dart';

/// Colours and text styles of the charts (COU-53), taken from the design
/// tokens so light and dark themes keep their contrast. Income and expense
/// reuse the palette colours that always come with a sign or a legend.
@immutable
class ChartTheme {
  const ChartTheme({
    required this.income,
    required this.expense,
    required this.accent,
    required this.grid,
    required this.label,
    required this.highlight,
  });

  factory ChartTheme.of(BuildContext context) {
    final theme = Theme.of(context);
    final palette = context.palette;
    final dark = theme.brightness == Brightness.dark;
    return ChartTheme(
      income: palette.income,
      expense: palette.expense,
      // Lavender on Ink, Dusk Blue on white: both above 4.5:1.
      accent: dark ? AppColors.lavender : AppColors.dusk,
      grid: palette.line,
      label: AppTypography.caption.copyWith(fontSize: 11, color: palette.muted, height: 1.2),
      highlight: palette.surface2,
    );
  }

  final Color income;
  final Color expense;

  /// Lines (evolution, projection).
  final Color accent;
  final Color grid;

  /// Axis labels.
  final TextStyle label;

  /// Background of the selected bucket.
  final Color highlight;

  @override
  bool operator ==(Object other) =>
      other is ChartTheme &&
      other.income == income &&
      other.expense == expense &&
      other.accent == accent &&
      other.grid == grid &&
      other.label == label &&
      other.highlight == highlight;

  @override
  int get hashCode => Object.hash(income, expense, accent, grid, label, highlight);
}

/// Short axis amounts: `$950`, `$1,2 mil`, `−$3 mil` (cents in, dollars out).
String axisAmount(int cents) {
  final amount = cents / 100;
  final text = '\$${_compact.format(amount.abs())}';
  return amount < 0 ? '−$text' : text;
}

final NumberFormat _compact = NumberFormat.compact(locale: 'es');

/// Colour swatch plus its name: the legend that keeps charts readable
/// without telling colours apart.
class ChartLegend extends StatelessWidget {
  const ChartLegend({super.key, required this.items});

  final List<(Color, String)> items;

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: Wrap(
        spacing: AppSpacing.lg,
        runSpacing: AppSpacing.xs,
        children: [
          for (final (color, label) in items)
            Row(
              mainAxisSize: MainAxisSize.min,
              spacing: 6,
              children: [
                Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(3)),
                ),
                Text(label, style: AppTypography.caption.copyWith(color: context.palette.muted)),
              ],
            ),
        ],
      ),
    );
  }
}

/// Text layout shared by the painters (one TextPainter per label, laid out
/// only when the chart repaints, which happens when its data or theme change).
TextPainter layoutLabel(String text, TextStyle style) => TextPainter(
  text: TextSpan(text: text, style: style),
  textDirection: TextDirection.ltr,
)..layout();
