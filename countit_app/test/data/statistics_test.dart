import 'package:countit_app/data/dtos/statistics.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/statistics_fixtures.dart';

void main() {
  group('WalletStatistics.fromJson (COU-22)', () {
    test('series, totals and growth in cents and calendar days', () {
      final stats = WalletStatistics.fromJson(statisticsJson());
      expect(stats.walletId, 4);
      expect(stats.range, StatisticsRange.days15);
      expect(stats.bucket, StatisticsBucket.day);
      expect(stats.from, DateTime(2026, 9, 20));
      expect(stats.to, DateTime(2026, 10, 4));
      expect(stats.series, hasLength(15));
      expect(stats.series[2].incomeCents, 90000);
      expect(stats.series[3].expenseCents, 12050);
      expect(stats.series[3].netCents, -12050);
      expect(stats.totals.incomeCents, 90000);
      expect(stats.totals.expenseCents, 16575);
      expect(stats.totals.netCents, 73425);
      expect(stats.growth.incomePct, 12.5);
      expect(stats.growth.expensePct, -3);
      expect(stats.isEmpty, isFalse);
    });

    test('distribution by budget, «Sin presupuesto» without id', () {
      final stats = WalletStatistics.fromJson(statisticsJson());
      final expenses = stats.distribution!.expenses;
      expect(expenses.map((s) => s.budgetName), ['Supermercado', 'Sin presupuesto']);
      expect(expenses.first.budgetId, 7);
      expect(expenses.first.amountCents, 12050);
      expect(expenses.first.pct, 72.7);
      expect(expenses.last.budgetId, isNull);
      expect(stats.distribution!.incomes.single.pct, 100);
    });

    test('Regular plan: the API sends no distribution', () {
      expect(WalletStatistics.fromJson(statisticsJson(advanced: false)).distribution, isNull);
    });

    test('no previous month: growth is null, not zero', () {
      final stats = WalletStatistics.fromJson(statisticsJson(incomeGrowth: null, expenseGrowth: '4.25'));
      expect(stats.growth.incomePct, isNull);
      expect(stats.growth.expensePct, 4.25);
    });

    test('an empty range is empty', () {
      expect(WalletStatistics.fromJson(statisticsJson(empty: true)).isEmpty, isTrue);
    });

    test('ranges and buckets map the API values', () {
      expect(StatisticsRange.values.map((r) => r.apiValue), ['15d', '30d', '3m', '6m', '1y']);
      expect(StatisticsRange.parse('1y'), StatisticsRange.year1);
      expect(StatisticsRange.parse('2y'), isNull);
      expect(StatisticsBucket.parse('week'), StatisticsBucket.week);
      expect(StatisticsBucket.parse('month').label, 'por mes');
    });
  });

  group('chart aggregates (COU-96, COU-97)', () {
    test('cumulative net after each bucket and the largest single bucket', () {
      final stats = WalletStatistics.fromJson(statisticsJson());
      final cumulative = stats.cumulativeNetCents;
      expect(cumulative, hasLength(15));
      expect(cumulative[1], 0);
      expect(cumulative[2], 90000);
      expect(cumulative[3], 90000 - 12050);
      expect(cumulative.last, stats.totals.netCents);
      expect(stats.peakBucketCents, 90000);
    });

    test('an empty series has no peak and stays at zero', () {
      final stats = WalletStatistics.fromJson(statisticsJson(empty: true));
      expect(stats.peakBucketCents, 0);
      expect(stats.cumulativeNetCents.toSet(), {0});
    });
  });
}
