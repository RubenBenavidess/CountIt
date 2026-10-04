import 'package:countit_app/data/dtos/budget.dart';
import 'package:countit_app/data/dtos/transaction.dart';

/// Transaction as `v_transactions` would return it; amount in dollars for readability.
Transaction transactionFixture({
  int id = 1,
  int walletId = 4,
  String name = 'Almuerzo',
  TransactionType type = TransactionType.expense,
  double amount = 12.5,
  DateTime? date,
  int? budgetId,
  String? budgetName,
  BudgetIcon? budgetIcon,
  String? userId = 'u1',
  String? authorName = 'María Quishpe',
  bool isScheduled = false,
}) => Transaction(
  transactionId: id,
  walletId: walletId,
  name: name,
  type: type,
  amountCents: (amount * 100).round(),
  date: date ?? DateTime(2026, 10, 3),
  budgetId: budgetId,
  budgetName: budgetName,
  budgetIcon: budgetIcon,
  userId: userId,
  authorName: authorName,
  isScheduled: isScheduled,
);
