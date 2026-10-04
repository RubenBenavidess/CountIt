import 'package:countit_app/data/dtos/statistics.dart';

/// `get_wallet_statistics` answer for 15d (daily buckets 2026-09-20…2026-10-04)
/// with a few movements; [advanced] adds the distribution (Contador / Pro).
Map<String, dynamic> statisticsJson({
  int walletId = 4,
  String range = '15d',
  bool advanced = true,
  bool empty = false,
  Object? incomeGrowth = 12.5,
  Object? expenseGrowth = -3,
}) {
  final start = DateTime(2026, 9, 20);
  String day(int offset) {
    final d = start.add(Duration(days: offset));
    return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  }

  return {
    'wallet_id': walletId,
    'range': range,
    'bucket': 'day',
    'from': '2026-09-20',
    'to': '2026-10-04',
    'series': [
      for (var i = 0; i < 15; i++)
        {
          'period_start': day(i),
          'income': empty || i != 2 ? 0 : 900,
          'expense': empty ? 0 : (i == 3 ? 120.5 : (i == 10 ? 45.25 : 0)),
        },
    ],
    'totals': empty ? {'income': 0, 'expense': 0, 'net': 0} : {'income': 900, 'expense': 165.75, 'net': 734.25},
    'growth': {'income_pct': incomeGrowth, 'expense_pct': expenseGrowth},
    'distribution': advanced
        ? {
            'expenses_by_budget': empty
                ? <Map<String, dynamic>>[]
                : [
                    {'budget_id': 7, 'budget_name': 'Supermercado', 'amount': 120.5, 'pct': 72.7},
                    {'budget_id': null, 'budget_name': 'Sin presupuesto', 'amount': 45.25, 'pct': 27.3},
                  ],
            'incomes_by_budget': empty
                ? <Map<String, dynamic>>[]
                : [
                    {'budget_id': null, 'budget_name': 'Sin presupuesto', 'amount': 900, 'pct': 100},
                  ],
          }
        : null,
  };
}

WalletStatistics statisticsFixture({
  int walletId = 4,
  StatisticsRange range = StatisticsRange.days15,
  bool advanced = true,
  bool empty = false,
}) => WalletStatistics.fromJson(
  statisticsJson(walletId: walletId, range: range.apiValue, advanced: advanced, empty: empty),
);
