import 'package:flutter/material.dart';

import '../../app/theme/app_theme.dart';
import '../../app/theme/tokens.dart';
import 'app_card.dart';

/// A «label · value» line of [DetailRows].
class DetailRow {
  const DetailRow(this.label, this.value, {this.color, this.money = false});

  final String label;
  final String value;

  /// Income/expense colour for amounts (always with their sign).
  final Color? color;

  /// Tabular figures for amounts.
  final bool money;
}

/// Card with label/value lines split by dividers (wallet figures,
/// transaction detail).
class DetailRows extends StatelessWidget {
  const DetailRows({super.key, required this.rows});

  final List<DetailRow> rows;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return AppCard(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          for (final (index, row) in rows.indexed) ...[
            if (index > 0) Divider(height: 1, color: palette.line),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: 14),
              child: Row(
                spacing: AppSpacing.md,
                children: [
                  Expanded(
                    child: Text(row.label, style: AppTypography.caption.copyWith(color: palette.muted)),
                  ),
                  Flexible(
                    flex: 2,
                    child: Text(
                      row.value,
                      textAlign: TextAlign.end,
                      style: (row.money ? AppTypography.money.copyWith(fontSize: 15) : AppTypography.label).copyWith(
                        color: row.color,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
