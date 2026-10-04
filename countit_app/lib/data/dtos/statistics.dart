import 'package:equatable/equatable.dart';

import '../../shared/utils/dates.dart';
import 'json_parsing.dart';

/// Ranges of `get_wallet_statistics(p_range)` (HU-26). The API counts them
/// back from today in the caller's calendar; there is no custom range.
enum StatisticsRange {
  days15('15d', '15 días'),
  days30('30d', '30 días'),
  months3('3m', '3 meses'),
  months6('6m', '6 meses'),
  year1('1y', '1 año');

  const StatisticsRange(this.apiValue, this.label);

  /// `p_range` sent to the API and `range` it answers.
  final String apiValue;

  /// Spanish label of the selector.
  final String label;

  static StatisticsRange? parse(Object? value) {
    for (final range in values) {
      if (range.apiValue == value) return range;
    }
    return null;
  }
}

/// Size of each point of the series: 15d/30d by day, 3m by week (Monday),
/// 6m/1y by month.
enum StatisticsBucket {
  day('por día'),
  week('por semana'),
  month('por mes');

  const StatisticsBucket(this.label);

  /// «por día», after the range description.
  final String label;

  static StatisticsBucket parse(Object? value) =>
      values.firstWhere((bucket) => bucket.name == value, orElse: () => StatisticsBucket.day);
}

/// One bucket of the series: what came in and went out from [periodStart].
/// Empty buckets come from the API with zeros, so the series has no gaps.
class StatisticsPoint extends Equatable {
  const StatisticsPoint({required this.periodStart, required this.incomeCents, required this.expenseCents});

  factory StatisticsPoint.fromJson(Map<String, dynamic> json) => StatisticsPoint(
    periodStart: Dates.parseDay(json['period_start'] as String),
    incomeCents: Cents.parse(json['income']) ?? 0,
    expenseCents: Cents.parse(json['expense']) ?? 0,
  );

  final DateTime periodStart;
  final int incomeCents;
  final int expenseCents;

  int get netCents => incomeCents - expenseCents;

  @override
  List<Object?> get props => [periodStart, incomeCents, expenseCents];
}

/// Sums of the whole range.
class StatisticsTotals extends Equatable {
  const StatisticsTotals({required this.incomeCents, required this.expenseCents, required this.netCents});

  factory StatisticsTotals.fromJson(Map<String, dynamic>? json) => StatisticsTotals(
    incomeCents: Cents.parse(json?['income']) ?? 0,
    expenseCents: Cents.parse(json?['expense']) ?? 0,
    netCents: Cents.parse(json?['net']) ?? 0,
  );

  final int incomeCents;
  final int expenseCents;
  final int netCents;

  double get income => Cents.toAmount(incomeCents);
  double get expense => Cents.toAmount(expenseCents);
  double get net => Cents.toAmount(netCents);

  @override
  List<Object?> get props => [incomeCents, expenseCents, netCents];
}

/// This month against the previous one (whatever the range); null when the
/// previous month had nothing of that type (no rate to compute).
class StatisticsGrowth extends Equatable {
  const StatisticsGrowth({this.incomePct, this.expensePct});

  factory StatisticsGrowth.fromJson(Map<String, dynamic>? json) =>
      StatisticsGrowth(incomePct: _percent(json?['income_pct']), expensePct: _percent(json?['expense_pct']));

  static double? _percent(Object? value) => switch (value) {
    num() => value.toDouble(),
    String() => double.tryParse(value),
    _ => null,
  };

  final double? incomePct;
  final double? expensePct;

  @override
  List<Object?> get props => [incomePct, expensePct];
}

/// Share of one budget (or of the movements without one) in the range.
class BudgetShare extends Equatable {
  const BudgetShare({required this.budgetName, required this.amountCents, required this.pct, this.budgetId});

  factory BudgetShare.fromJson(Map<String, dynamic> json) => BudgetShare(
    budgetId: (json['budget_id'] as num?)?.toInt(),
    budgetName: (json['budget_name'] as String?) ?? 'Sin presupuesto',
    amountCents: Cents.parse(json['amount']) ?? 0,
    pct: StatisticsGrowth._percent(json['pct']) ?? 0,
  );

  /// Null for «Sin presupuesto».
  final int? budgetId;

  /// The API names the movements without a budget «Sin presupuesto».
  final String budgetName;
  final int amountCents;

  /// 0–100, two decimals, of the type's total in the range.
  final double pct;

  double get amount => Cents.toAmount(amountCents);

  @override
  List<Object?> get props => [budgetId, budgetName, amountCents, pct];
}

/// Distribution by budget (plan feature `advanced_statistics`), largest first.
class BudgetDistribution extends Equatable {
  const BudgetDistribution({this.expenses = const [], this.incomes = const []});

  factory BudgetDistribution.fromJson(Map<String, dynamic> json) =>
      BudgetDistribution(expenses: _shares(json['expenses_by_budget']), incomes: _shares(json['incomes_by_budget']));

  static List<BudgetShare> _shares(Object? value) => [
    if (value is List)
      for (final row in value) BudgetShare.fromJson(Map<String, dynamic>.from(row as Map)),
  ];

  final List<BudgetShare> expenses;
  final List<BudgetShare> incomes;

  @override
  List<Object?> get props => [expenses, incomes];
}

/// Result of `api.get_wallet_statistics` (HU-26 · COU-22).
///
/// The chart aggregates ([cumulativeNetCents], [peakBucketCents]) are derived
/// here, once per answer, so widgets never loop over the series while building.
class WalletStatistics extends Equatable {
  WalletStatistics({
    required this.walletId,
    required this.range,
    required this.bucket,
    required this.from,
    required this.to,
    required this.series,
    required this.totals,
    required this.growth,
    this.distribution,
  }) : cumulativeNetCents = cumulativeNet(series),
       peakBucketCents = peakBucket(series);

  factory WalletStatistics.fromJson(Map<String, dynamic> json) => WalletStatistics(
    walletId: (json['wallet_id'] as num).toInt(),
    range: StatisticsRange.parse(json['range']) ?? StatisticsRange.days30,
    bucket: StatisticsBucket.parse(json['bucket']),
    from: Dates.parseDay(json['from'] as String),
    to: Dates.parseDay(json['to'] as String),
    series: [
      if (json['series'] is List)
        for (final row in json['series'] as List) StatisticsPoint.fromJson(Map<String, dynamic>.from(row as Map)),
    ],
    totals: StatisticsTotals.fromJson(json['totals'] is Map ? Map<String, dynamic>.from(json['totals'] as Map) : null),
    growth: StatisticsGrowth.fromJson(json['growth'] is Map ? Map<String, dynamic>.from(json['growth'] as Map) : null),
    distribution: json['distribution'] is Map
        ? BudgetDistribution.fromJson(Map<String, dynamic>.from(json['distribution'] as Map))
        : null,
  );

  /// Running sum of income − expense after each bucket (COU-97): where the
  /// period's balance stood at the end of every day, week or month.
  static List<int> cumulativeNet(List<StatisticsPoint> series) {
    var sum = 0;
    return List.unmodifiable([for (final point in series) sum += point.netCents]);
  }

  /// Largest income or expense of a single bucket (scale of the bars, COU-96).
  static int peakBucket(List<StatisticsPoint> series) {
    var peak = 0;
    for (final point in series) {
      if (point.incomeCents > peak) peak = point.incomeCents;
      if (point.expenseCents > peak) peak = point.expenseCents;
    }
    return peak;
  }

  final int walletId;
  final StatisticsRange range;
  final StatisticsBucket bucket;

  /// First and last day of the range (inclusive, the user's calendar).
  final DateTime from;
  final DateTime to;

  /// One point per bucket, oldest first, zeros included.
  final List<StatisticsPoint> series;
  final StatisticsTotals totals;
  final StatisticsGrowth growth;

  /// Null when the caller's plan has no `advanced_statistics` (Regular):
  /// the API decides and the screen offers the plans instead.
  final BudgetDistribution? distribution;

  /// [cumulativeNet] of [series], one value per bucket.
  final List<int> cumulativeNetCents;

  /// [peakBucket] of [series].
  final int peakBucketCents;

  /// No movement in the range.
  bool get isEmpty => totals.incomeCents == 0 && totals.expenseCents == 0;

  @override
  List<Object?> get props => [walletId, range, bucket, from, to, series, totals, growth, distribution];
}
