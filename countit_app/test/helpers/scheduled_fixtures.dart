import 'package:countit_app/data/dtos/budget.dart';
import 'package:countit_app/data/dtos/scheduled_transaction.dart';
import 'package:countit_app/data/dtos/transaction.dart';

/// Rule as `v_scheduled_transactions` would return it; amount in dollars for readability.
ScheduledTransaction scheduledFixture({
  int id = 1,
  int walletId = 4,
  String name = 'Arriendo',
  TransactionType type = TransactionType.expense,
  double amount = 300,
  Periodicity periodicity = Periodicity.months,
  int? interval = 1,
  DateTime? startDate,
  DateTime? endDate,
  DateTime? nextRunDate,
  DateTime? lastRunDate,
  int? budgetId,
  String? budgetName,
  BudgetIcon? budgetIcon,
  String? userId = 'u1',
  String? authorName = 'María Quishpe',
  bool isPaused = false,
}) => ScheduledTransaction(
  scheduledTransactionId: id,
  walletId: walletId,
  name: name,
  type: type,
  amountCents: (amount * 100).round(),
  periodicity: periodicity,
  periodInterval: periodicity.recurs ? interval : null,
  startDate: startDate ?? DateTime(2026, 11, 5),
  endDate: endDate,
  nextRunDate: nextRunDate ?? startDate ?? DateTime(2026, 11, 5),
  lastRunDate: lastRunDate,
  budgetId: budgetId,
  budgetName: budgetName,
  budgetIcon: budgetIcon,
  userId: userId,
  authorName: authorName,
  isPaused: isPaused,
  pausedAt: isPaused ? DateTime.utc(2026, 10, 4, 12) : null,
);
