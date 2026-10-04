import 'dart:math' as math;

import 'package:equatable/equatable.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../app/theme/app_theme.dart';
import '../../../../app/theme/tokens.dart';
import '../../../../shared/utils/dates.dart';
import 'chart_entrance.dart';
import 'chart_labels.dart';
import 'chart_theme.dart';

/// One value of a trend: an amount in cents on a calendar day.
class TrendPoint extends Equatable {
  const TrendPoint(this.date, this.cents);

  final DateTime date;
  final int cents;

  @override
  List<Object?> get props => [date, cents];
}

/// Line over time (COU-97 evolution, COU-99 projection): x is proportional
/// to the days between points, the zero line is always visible, and the
/// point the user taps is described below the chart (and announced).
///
/// [stepped] draws a balance that only changes on the days of the points
/// (projection) instead of joining them diagonally.
class TrendLineChart extends StatefulWidget {
  const TrendLineChart({
    super.key,
    required this.points,
    required this.summary,
    required this.describe,
    this.hint = 'Toca el gráfico para ver cada punto.',
    this.stepped = false,
    this.height = 180,
  });

  final List<TrendPoint> points;

  /// What a screen reader says for the whole chart.
  final String summary;

  /// Caption of the selected point.
  final String Function(TrendPoint point) describe;
  final String hint;
  final bool stepped;
  final double height;

  @override
  State<TrendLineChart> createState() => _TrendLineChartState();
}

class _TrendLineChartState extends State<TrendLineChart> {
  int? _selected;
  late TrendGeometry _geometry;

  @override
  void initState() {
    super.initState();
    _geometry = TrendGeometry(widget.points);
  }

  @override
  void didUpdateWidget(TrendLineChart oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.points, widget.points)) {
      _geometry = TrendGeometry(widget.points);
      _selected = null;
    }
  }

  void _select(double dx, double width) {
    final index = _geometry.nearest((dx - TrendGeometry.axisWidth) / math.max(1, width - TrendGeometry.axisWidth));
    if (index != null && index != _selected) setState(() => _selected = index);
  }

  @override
  Widget build(BuildContext context) {
    final chart = ChartTheme.of(context);
    final selected = _selected;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: AppSpacing.md,
      children: [
        Semantics(
          label: widget.summary,
          container: true,
          excludeSemantics: true,
          child: LayoutBuilder(
            builder: (context, constraints) => GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapDown: (details) => _select(details.localPosition.dx, constraints.maxWidth),
              onHorizontalDragUpdate: (details) => _select(details.localPosition.dx, constraints.maxWidth),
              child: RepaintBoundary(
                // The line draws itself from left to right when the data arrives.
                child: ChartEntrance(
                  data: _geometry,
                  builder: (context, reveal) => CustomPaint(
                    size: Size(constraints.maxWidth, widget.height),
                    painter: TrendLinePainter(
                      geometry: _geometry,
                      theme: chart,
                      stepped: widget.stepped,
                      selected: selected,
                      reveal: reveal,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        Semantics(
          liveRegion: true,
          child: Text(
            selected == null ? widget.hint : widget.describe(widget.points[selected]),
            style: AppTypography.caption.copyWith(color: context.palette.muted),
          ),
        ),
      ],
    );
  }
}

/// Positions of a trend, computed once per data set (not per frame): x in
/// 0–1 by days, the rounded value range and its axis amounts.
class TrendGeometry {
  TrendGeometry(this.points) : xs = _xs(points), top = _top(points), bottom = _bottom(points);

  static const axisWidth = 48.0;
  static const footer = 20.0;

  final List<TrendPoint> points;

  /// 0 (first day) to 1 (last day); a single point sits in the middle.
  final List<double> xs;

  /// Rounded maximum (≥ 0) and minimum (≤ 0) in cents: zero is always inside.
  final int top;
  final int bottom;

  static List<double> _xs(List<TrendPoint> points) {
    if (points.isEmpty) return const [];
    if (points.length == 1) return const [0.5];
    final first = _utcDay(points.first.date);
    final span = _utcDay(points.last.date).difference(first).inDays;
    if (span <= 0) return [for (var i = 0; i < points.length; i++) i / (points.length - 1)];
    return [for (final p in points) _utcDay(p.date).difference(first).inDays / span];
  }

  // UTC midnights: a daylight-saving change never makes a day 23 h long.
  static DateTime _utcDay(DateTime d) => DateTime.utc(d.year, d.month, d.day);

  static int _top(List<TrendPoint> points) {
    final max = points.fold<int>(0, (m, p) => math.max(m, p.cents));
    final min = points.fold<int>(0, (m, p) => math.min(m, p.cents));
    return max > 0 ? niceCeiling(max) : (min < 0 ? 0 : 100);
  }

  static int _bottom(List<TrendPoint> points) {
    final min = points.fold<int>(0, (m, p) => math.min(m, p.cents));
    return min < 0 ? -niceCeiling(-min) : 0;
  }

  /// Fraction of the height (0 bottom, 1 top) of [cents].
  double level(int cents) => top == bottom ? 0 : (cents - bottom) / (top - bottom);

  /// Point closest to [fraction] (0–1 of the plot width); null without points.
  int? nearest(double fraction) {
    if (xs.isEmpty) return null;
    var best = 0;
    for (var i = 1; i < xs.length; i++) {
      if ((xs[i] - fraction).abs() < (xs[best] - fraction).abs()) best = i;
    }
    return best;
  }
}

final _axisDay = DateFormat('d MMM', Dates.locale);
final _axisDayYear = DateFormat('d MMM y', Dates.locale);

/// Axis date: «4 oct», or «4 oct 2027» when the chart spans two years
/// (a one-year projection would otherwise read «4 oct … 4 oct»).
String axisDay(DateTime day, {required bool withYear}) =>
    (withYear ? _axisDayYear : _axisDay).format(day).replaceAll('.', '');

class TrendLinePainter extends CustomPainter {
  TrendLinePainter({required this.geometry, required this.theme, this.stepped = false, this.selected, this.reveal = 1});

  final TrendGeometry geometry;
  final ChartTheme theme;
  final bool stepped;
  final int? selected;

  /// 0–1: share of the plot width the line has drawn (entrance animation).
  final double reveal;

  @override
  void paint(Canvas canvas, Size size) {
    const left = TrendGeometry.axisWidth;
    final width = math.max(0.0, size.width - left);
    final height = size.height - TrendGeometry.footer;
    double yOf(int cents) => height - height * geometry.level(cents);
    final grid = Paint()
      ..color = theme.grid
      ..strokeWidth = 1;

    // Top, zero and bottom lines with their amounts.
    for (final value in {geometry.top, 0, geometry.bottom}) {
      final y = yOf(value);
      canvas.drawLine(Offset(left, y), Offset(size.width, y), grid..strokeWidth = value == 0 ? 1.5 : 1);
      final label = layoutLabel(axisAmount(value), theme.label);
      label.paint(canvas, Offset(0, (y - label.height / 2).clamp(0, height - label.height)));
    }

    final points = geometry.points;
    if (points.isEmpty) return;
    final offsets = [
      for (var i = 0; i < points.length; i++) Offset(left + width * geometry.xs[i], yOf(points[i].cents)),
    ];

    final line = Path()..moveTo(offsets.first.dx, offsets.first.dy);
    for (var i = 1; i < offsets.length; i++) {
      if (stepped) line.lineTo(offsets[i].dx, offsets[i - 1].dy);
      line.lineTo(offsets[i].dx, offsets[i].dy);
    }
    // Axis and labels stay; the data appears from the left.
    canvas.save();
    if (reveal < 1) canvas.clipRect(Rect.fromLTRB(0, 0, left + width * reveal + 4, size.height));
    final zero = yOf(0);
    final area = Path.from(line)
      ..lineTo(offsets.last.dx, zero)
      ..lineTo(offsets.first.dx, zero)
      ..close();
    canvas.drawPath(area, Paint()..color = theme.accent.withValues(alpha: 0.14));
    canvas.drawPath(
      line,
      Paint()
        ..color = theme.accent
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..strokeJoin = StrokeJoin.round
        ..strokeCap = StrokeCap.round,
    );

    final dot = Paint()..color = theme.accent;
    if (offsets.length <= 40) {
      for (final offset in offsets) {
        canvas.drawCircle(offset, 3, dot);
      }
    }
    canvas.restore();
    if (selected != null) {
      final at = offsets[selected!];
      canvas.drawLine(Offset(at.dx, 0), Offset(at.dx, height), grid..strokeWidth = 1.5);
      canvas.drawCircle(at, 6, dot);
    }

    final withYear = points.first.date.year != points.last.date.year;
    final first = layoutLabel(axisDay(points.first.date, withYear: withYear), theme.label);
    first.paint(canvas, Offset(left, height + 4));
    if (points.length > 1) {
      final last = layoutLabel(axisDay(points.last.date, withYear: withYear), theme.label);
      last.paint(canvas, Offset(size.width - last.width, height + 4));
    }
  }

  @override
  bool shouldRepaint(TrendLinePainter oldDelegate) =>
      !identical(oldDelegate.geometry, geometry) ||
      oldDelegate.theme != theme ||
      oldDelegate.stepped != stepped ||
      oldDelegate.selected != selected ||
      oldDelegate.reveal != reveal;
}
