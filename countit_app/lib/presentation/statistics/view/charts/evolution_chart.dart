import 'package:flutter/material.dart';

import '../../../../data/dtos/statistics.dart';
import '../../../../shared/utils/money.dart';
import 'chart_labels.dart';
import 'trend_line_chart.dart';

/// Evolución en el tiempo (HU-26 · COU-97): the period's balance (income
/// minus expenses) accumulated bucket by bucket, from the series the API
/// sent (`WalletStatistics.cumulativeNetCents`).
class EvolutionChart extends StatefulWidget {
  const EvolutionChart({super.key, required this.statistics});

  final WalletStatistics statistics;

  @override
  State<EvolutionChart> createState() => _EvolutionChartState();
}

class _EvolutionChartState extends State<EvolutionChart> {
  late List<TrendPoint> _points;
  late String _summary;

  @override
  void initState() {
    super.initState();
    _prepare();
  }

  @override
  void didUpdateWidget(EvolutionChart oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.statistics, widget.statistics)) _prepare();
  }

  /// Once per answer, never per frame.
  void _prepare() {
    final statistics = widget.statistics;
    final cumulative = statistics.cumulativeNetCents;
    _points = List.unmodifiable([
      for (var i = 0; i < statistics.series.length; i++) TrendPoint(statistics.series[i].periodStart, cumulative[i]),
    ]);
    _summary = evolutionSummary(statistics);
  }

  @override
  Widget build(BuildContext context) {
    final bucket = widget.statistics.bucket;
    return TrendLineChart(
      points: _points,
      summary: _summary,
      describe: (point) => '${bucketLabel(bucket, point.date)}: acumulado ${_signed(point.cents)}',
    );
  }
}

String _signed(int cents) => Money.signed(cents.abs() / 100, income: cents >= 0);

/// Spoken summary: where the accumulated balance ends and its extremes.
String evolutionSummary(WalletStatistics statistics) {
  final cumulative = statistics.cumulativeNetCents;
  if (cumulative.isEmpty) return 'Gráfico de evolución sin datos.';
  var high = 0;
  var low = 0;
  for (var i = 1; i < cumulative.length; i++) {
    if (cumulative[i] > cumulative[high]) high = i;
    if (cumulative[i] < cumulative[low]) low = i;
  }
  final bucket = statistics.bucket;
  final series = statistics.series;
  return 'Gráfico de evolución del balance acumulado ${bucket.label}. '
      'Termina en ${_signed(cumulative.last)}. '
      'Máximo ${_signed(cumulative[high])} (${bucketLabel(bucket, series[high].periodStart)}), '
      'mínimo ${_signed(cumulative[low])} (${bucketLabel(bucket, series[low].periodStart)}).';
}
