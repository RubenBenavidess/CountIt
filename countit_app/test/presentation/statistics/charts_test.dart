import 'package:countit_app/data/dtos/statistics.dart';
import 'package:countit_app/presentation/statistics/view/charts/chart_labels.dart';
import 'package:countit_app/presentation/statistics/view/charts/chart_theme.dart';
import 'package:countit_app/presentation/statistics/view/charts/evolution_chart.dart';
import 'package:countit_app/presentation/statistics/view/charts/income_expense_chart.dart';
import 'package:countit_app/presentation/statistics/view/charts/trend_line_chart.dart';
import 'package:countit_app/presentation/statistics/view/widgets/distribution_section.dart';
import 'package:countit_app/shared/utils/dates.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/pump_app.dart';
import '../../helpers/statistics_fixtures.dart';

void main() {
  setUpAll(Dates.init);

  group('labels and scale (COU-53)', () {
    test('round axis ceilings, never below \$1', () {
      expect(niceCeiling(0), 100);
      expect(niceCeiling(48730), 50000);
      expect(niceCeiling(90000), 100000);
      expect(niceCeiling(120000), 200000);
      expect(niceCeiling(230000), 250000);
      expect(niceCeiling(100000), 100000);
    });

    test('compact axis amounts with sign', () {
      expect(axisAmount(95000), r'$950');
      expect(axisAmount(120000), contains('1,2'));
      expect(axisAmount(-300000).startsWith('−\$'), isTrue);
    });

    test('axis days carry the year only across years', () {
      expect(axisDay(DateTime(2026, 10, 4), withYear: false), '4 oct');
      expect(axisDay(DateTime(2027, 10, 4), withYear: true), '4 oct 2027');
    });

    test('bucket names, long and short', () {
      final day = DateTime(2026, 9, 5);
      expect(bucketLabel(StatisticsBucket.day, day), '5 sept 2026');
      expect(bucketLabel(StatisticsBucket.day, day, short: true), '5 sept');
      expect(bucketLabel(StatisticsBucket.week, DateTime(2026, 7, 6)), 'Semana del 6 jul 2026');
      expect(bucketLabel(StatisticsBucket.month, DateTime(2026, 10)), 'octubre 2026');
      expect(bucketLabel(StatisticsBucket.month, DateTime(2026, 10), short: true), 'oct 2026');
    });
  });

  group('geometry', () {
    test('bars: bucket under a tap, nothing on the axis', () {
      const layout = BarLayout(width: 344, count: 15);
      expect(layout.slotAt(10), isNull);
      expect(layout.slotAt(BarLayout.axisWidth + 1), 0);
      expect(layout.slotAt(344), 14);
      expect(const BarLayout(width: 344, count: 0).slotAt(200), isNull);
    });

    test('bars: width follows the room of each period, within a minimum and a maximum', () {
      // The old geometry gave ~6 px to each bar of 15 periods on a phone.
      expect(const BarLayout(width: 344, count: 15).bar, greaterThan(7.5));
      const daily = BarLayout(width: 344, count: 30);
      const monthly = BarLayout(width: 344, count: 6);
      expect(monthly.bar, greaterThan(daily.bar));
      expect(const BarLayout(width: 1200, count: 6).bar, BarLayout.maxBar);
      expect(const BarLayout(width: 120, count: 30).bar, greaterThanOrEqualTo(1.0));
      expect(const BarLayout(width: 1200, count: 30).bar, greaterThan(daily.bar), reason: 'a tablet gives more room');
    });

    test('bars: each pair stays in its slot, clearly apart from the next one', () {
      for (final (width, count) in const [(344.0, 30), (344.0, 15), (344.0, 12), (344.0, 6), (700.0, 13)]) {
        final layout = BarLayout(width: width, count: count);
        final pair = layout.bar * 2 + layout.innerGap;
        for (var i = 0; i < count; i++) {
          final left = layout.pairLeft(i);
          expect(left, greaterThanOrEqualTo(layout.plotLeft + layout.slot * i - 1e-9));
          expect(left + pair, lessThanOrEqualTo(layout.plotLeft + layout.slot * (i + 1) + 1e-9));
        }
        final between = layout.pairLeft(1) - (layout.pairLeft(0) + pair);
        expect(between, greaterThanOrEqualTo(2), reason: '$count periods in $width px');
        expect(between, greaterThan(layout.innerGap), reason: 'pairs read as pairs');
      }
    });

    test('trend: x by days, zero always inside the range', () {
      final geometry = TrendGeometry([
        TrendPoint(DateTime(2026, 10, 4), 50000),
        TrendPoint(DateTime(2026, 10, 5), -20000),
        TrendPoint(DateTime(2026, 11, 3), 80000),
      ]);
      expect(geometry.xs, [0, 1 / 30, 1]);
      expect(geometry.top, 100000);
      expect(geometry.bottom, -20000);
      expect(geometry.level(0), closeTo(20000 / 120000, 1e-9));
      expect(geometry.nearest(0.9), 2);
      expect(geometry.nearest(0.02), 1);
    });

    test('trend: one point sits in the middle; only zeros still have a scale', () {
      final geometry = TrendGeometry([TrendPoint(DateTime(2026, 10, 4), 0)]);
      expect(geometry.xs, [0.5]);
      expect(geometry.top, 100);
      expect(geometry.bottom, 0);
    });
  });

  group('spoken summaries', () {
    test('income vs expenses names the busiest buckets', () {
      final summary = incomeExpenseSummary(statisticsFixture());
      expect(summary, contains('15 periodos'));
      expect(summary, contains('Mayor ingreso: 22 sept 2026, \$900,00'));
      expect(summary, contains('Mayor gasto: 23 sept 2026, \$120,50'));
    });

    test('evolution says where it ends and its extremes', () {
      final summary = evolutionSummary(statisticsFixture());
      expect(summary, contains('Termina en + \$734,25'));
      expect(summary, contains('Máximo + \$900,00 (22 sept 2026)'));
    });
  });

  group('IncomeExpenseChart (COU-96)', () {
    testWidgets('legend, summary and the figures of a tapped bucket', (tester) async {
      final stats = statisticsFixture();
      await tester.pumpApp(
        Padding(
          padding: const EdgeInsets.all(16),
          child: IncomeExpenseChart(statistics: stats),
        ),
      );
      expect(find.text('Ingresos'), findsOneWidget);
      expect(find.text('Gastos'), findsOneWidget);
      expect(find.bySemanticsLabel(RegExp('^Gráfico de ingresos y gastos')), findsOneWidget);
      expect(
        find.descendant(of: find.byType(IncomeExpenseChart), matching: find.byType(RepaintBoundary)),
        findsWidgets,
      );
      // Bucket 2 (22 sept) of 15.
      final rect = tester.getRect(find.byType(CustomPaint).last);
      final slot = (rect.width - BarLayout.axisWidth) / 15;
      await tester.tapAt(rect.topLeft + Offset(BarLayout.axisWidth + slot * 2.5, 100));
      await tester.pump();
      expect(find.text('22 sept 2026: + \$900,00 · \$0,00'), findsOneWidget);
    });

    testWidgets('paints in the light theme too', (tester) async {
      await tester.pumpApp(IncomeExpenseChart(statistics: statisticsFixture()), themeMode: ThemeMode.light);
      expect(tester.takeException(), isNull);
    });

    test('repaints only when data, theme or selection change', () {
      final stats = statisticsFixture();
      const theme = ChartTheme(
        income: Colors.green,
        expense: Colors.orange,
        accent: Colors.blue,
        grid: Colors.grey,
        label: TextStyle(),
        highlight: Colors.black,
      );
      IncomeExpensePainter painter({int? selected, List<StatisticsPoint>? series}) => IncomeExpensePainter(
        series: series ?? stats.series,
        peakCents: stats.peakBucketCents,
        bucket: stats.bucket,
        theme: theme,
        selected: selected,
      );
      expect(painter().shouldRepaint(painter()), isFalse);
      expect(painter(selected: 1).shouldRepaint(painter()), isTrue);
      expect(painter(series: [...stats.series]).shouldRepaint(painter()), isTrue);
    });
  });

  group('EvolutionChart (COU-97)', () {
    testWidgets('accumulated balance of the tapped bucket', (tester) async {
      await tester.pumpApp(
        Padding(
          padding: const EdgeInsets.all(16),
          child: EvolutionChart(statistics: statisticsFixture()),
        ),
      );
      expect(find.bySemanticsLabel(RegExp('^Gráfico de evolución')), findsOneWidget);
      final rect = tester.getRect(find.byType(CustomPaint).last);
      await tester.tapAt(Offset(rect.right - 1, rect.top + 50));
      await tester.pump();
      expect(find.text('4 oct 2026: acumulado + \$734,25'), findsOneWidget);
    });
  });

  group('distribution bars (COU-94)', () {
    testWidgets('each budget bar is its share of the width', (tester) async {
      final share = statisticsFixture().distribution!.expenses.first;
      await tester.pumpApp(BudgetShareRow(share: share, income: false));
      final bar = tester.widget<FractionallySizedBox>(find.byType(FractionallySizedBox));
      expect(bar.widthFactor, closeTo(0.727, 1e-9));
      expect(find.bySemanticsLabel('Supermercado: − \$120,50, 72,7 % del total'), findsOneWidget);
    });
  });
}
