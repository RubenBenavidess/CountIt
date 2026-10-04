import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../app/theme/app_theme.dart';
import '../../../../app/theme/tokens.dart';
import '../../../../data/dtos/statistics.dart';
import '../../../../shared/utils/money.dart';
import 'chart_labels.dart';
import 'chart_theme.dart';

/// Ingresos vs. gastos per bucket (HU-26 · COU-96): two bars per period,
/// income first, with a legend, a spoken summary and the figures of the
/// bucket the user taps (colour never carries the meaning alone).
class IncomeExpenseChart extends StatefulWidget {
  const IncomeExpenseChart({super.key, required this.statistics, this.height = 180});

  final WalletStatistics statistics;
  final double height;

  @override
  State<IncomeExpenseChart> createState() => _IncomeExpenseChartState();
}

class _IncomeExpenseChartState extends State<IncomeExpenseChart> {
  int? _selected;
  late String _summary;

  @override
  void initState() {
    super.initState();
    _summary = incomeExpenseSummary(widget.statistics);
  }

  @override
  void didUpdateWidget(IncomeExpenseChart oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.statistics, widget.statistics)) {
      _summary = incomeExpenseSummary(widget.statistics);
      _selected = null;
    }
  }

  void _select(Offset position, double width) {
    final index = BarLayout(width: width, count: widget.statistics.series.length).slotAt(position.dx);
    if (index != null && index != _selected) setState(() => _selected = index);
  }

  @override
  Widget build(BuildContext context) {
    final chart = ChartTheme.of(context);
    final statistics = widget.statistics;
    final selected = _selected;
    final point = selected == null ? null : statistics.series[selected];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: AppSpacing.md,
      children: [
        ChartLegend(items: [(chart.income, 'Ingresos'), (chart.expense, 'Gastos')]),
        Semantics(
          label: _summary,
          container: true,
          excludeSemantics: true,
          child: LayoutBuilder(
            builder: (context, constraints) => GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapDown: (details) => _select(details.localPosition, constraints.maxWidth),
              onHorizontalDragUpdate: (details) => _select(details.localPosition, constraints.maxWidth),
              child: RepaintBoundary(
                child: CustomPaint(
                  size: Size(constraints.maxWidth, widget.height),
                  painter: IncomeExpensePainter(
                    series: statistics.series,
                    peakCents: statistics.peakBucketCents,
                    bucket: statistics.bucket,
                    theme: chart,
                    selected: selected,
                  ),
                ),
              ),
            ),
          ),
        ),
        Semantics(
          liveRegion: true,
          child: Text(
            point == null
                ? 'Toca una barra para ver sus cifras.'
                : '${bucketLabel(statistics.bucket, point.periodStart)}: '
                      '${Money.signed(point.incomeCents / 100, income: true)} · '
                      '${Money.signed(point.expenseCents / 100, income: false)}',
            style: AppTypography.caption.copyWith(color: context.palette.muted),
          ),
        ),
      ],
    );
  }
}

/// What a screen reader says for the whole chart: the range and the
/// busiest buckets.
String incomeExpenseSummary(WalletStatistics statistics) {
  final series = statistics.series;
  final buffer = StringBuffer('Gráfico de ingresos y gastos ${statistics.bucket.label}, ${series.length} periodos.');
  StatisticsPoint? topIncome;
  StatisticsPoint? topExpense;
  for (final point in series) {
    if (point.incomeCents > (topIncome?.incomeCents ?? 0)) topIncome = point;
    if (point.expenseCents > (topExpense?.expenseCents ?? 0)) topExpense = point;
  }
  if (topIncome != null) {
    buffer.write(
      ' Mayor ingreso: ${bucketLabel(statistics.bucket, topIncome.periodStart)}, '
      '${Money.format(topIncome.incomeCents / 100)}.',
    );
  }
  if (topExpense != null) {
    buffer.write(
      ' Mayor gasto: ${bucketLabel(statistics.bucket, topExpense.periodStart)}, '
      '${Money.format(topExpense.expenseCents / 100)}.',
    );
  }
  return buffer.toString();
}

/// Geometry of the bar chart, shared by the painter and the hit test.
class BarLayout {
  const BarLayout({required this.width, required this.count});

  /// Room for the axis amounts on the left.
  static const axisWidth = 44.0;

  /// Room for the first/last period below.
  static const footer = 20.0;

  final double width;
  final int count;

  double get plotLeft => axisWidth;
  double get plotWidth => math.max(0, width - axisWidth);
  double get slot => count == 0 ? 0 : plotWidth / count;

  /// Bucket under [dx]; null outside the plot or without data.
  int? slotAt(double dx) {
    if (count == 0 || dx < plotLeft || dx > width) return null;
    return math.min(count - 1, ((dx - plotLeft) / slot).floor());
  }
}

class IncomeExpensePainter extends CustomPainter {
  IncomeExpensePainter({
    required this.series,
    required this.peakCents,
    required this.bucket,
    required this.theme,
    this.selected,
  });

  final List<StatisticsPoint> series;
  final int peakCents;
  final StatisticsBucket bucket;
  final ChartTheme theme;
  final int? selected;

  @override
  void paint(Canvas canvas, Size size) {
    final layout = BarLayout(width: size.width, count: series.length);
    final plotHeight = size.height - BarLayout.footer;
    final top = niceCeiling(peakCents);
    final grid = Paint()
      ..color = theme.grid
      ..strokeWidth = 1;

    // Grid at 0, half and top with their amounts.
    for (final fraction in const [0.0, 0.5, 1.0]) {
      final y = plotHeight - plotHeight * fraction;
      canvas.drawLine(Offset(layout.plotLeft, y), Offset(size.width, y), grid);
      final label = layoutLabel(axisAmount((top * fraction).round()), theme.label);
      label.paint(canvas, Offset(0, math.max(0, y - label.height / 2)));
    }
    if (series.isEmpty) return;

    final slot = layout.slot;
    if (selected != null) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(layout.plotLeft + slot * selected!, 0, slot, plotHeight),
          const Radius.circular(4),
        ),
        Paint()..color = theme.highlight,
      );
    }

    final group = slot * 0.72;
    final bar = math.max(1.0, group / 2 - math.min(2, slot * 0.06));
    final income = Paint()..color = theme.income;
    final expense = Paint()..color = theme.expense;
    for (var i = 0; i < series.length; i++) {
      final left = layout.plotLeft + slot * i + (slot - group) / 2;
      _bar(canvas, left, bar, series[i].incomeCents, top, plotHeight, income);
      _bar(canvas, left + group - bar, bar, series[i].expenseCents, top, plotHeight, expense);
    }

    // First and last period under the plot.
    final first = layoutLabel(bucketLabel(bucket, series.first.periodStart, short: true), theme.label);
    first.paint(canvas, Offset(layout.plotLeft, plotHeight + 4));
    if (series.length > 1) {
      final last = layoutLabel(bucketLabel(bucket, series.last.periodStart, short: true), theme.label);
      last.paint(canvas, Offset(size.width - last.width, plotHeight + 4));
    }
  }

  void _bar(Canvas canvas, double left, double width, int cents, int top, double plotHeight, Paint paint) {
    if (cents <= 0 || top <= 0) return;
    // At least 2 px so a small amount is still visible next to a large one.
    final height = math.max(2.0, plotHeight * cents / top);
    final radius = Radius.circular(math.min(3, width / 2));
    canvas.drawRRect(
      RRect.fromRectAndCorners(
        Rect.fromLTWH(left, plotHeight - height, width, height),
        topLeft: radius,
        topRight: radius,
      ),
      paint,
    );
  }

  @override
  bool shouldRepaint(IncomeExpensePainter oldDelegate) =>
      !identical(oldDelegate.series, series) || oldDelegate.theme != theme || oldDelegate.selected != selected;
}
