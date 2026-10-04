import 'package:countit_app/data/dtos/budget.dart';
import 'package:countit_app/data/dtos/transaction.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/transaction_fixtures.dart';

void main() {
  group('Transaction.fromJson (v_transactions)', () {
    test('reads every column; amounts become cents and dates calendar days', () {
      final t = Transaction.fromJson({
        'transaction_id': 7,
        'wallet_id': 4,
        'wallet_name': 'Hogar',
        'budget_id': 2,
        'budget_name': 'Comida',
        'budget_icon': 'food',
        'user_id': 'u1',
        'author_name': 'Usuario eliminado',
        'name': 'Mercado',
        'type': 'expense',
        'amount': '1234.50',
        'date': '2026-10-03',
        'is_scheduled': true,
        'scheduled_transaction_id': 9,
        'created_at': '2026-10-03T14:00:00Z',
        'updated_at': null,
      });
      expect(t.transactionId, 7);
      expect(t.amountCents, 123450);
      expect(t.date, DateTime(2026, 10, 3));
      expect(t.budgetIcon, BudgetIcon.food);
      expect(t.authorName, 'Usuario eliminado');
      expect(t.isScheduled, isTrue);
      expect(t.scheduledTransactionId, 9);
      expect(t.createdAt, DateTime.utc(2026, 10, 3, 14));
      expect(t.isIncome, isFalse);
    });

    test('without budget nor author name (API 1.1 allows a null author_name)', () {
      final t = Transaction.fromJson({
        'transaction_id': 1,
        'wallet_id': 4,
        'name': 'Sueldo',
        'type': 'income',
        'amount': 800,
        'date': '2026-09-30',
      });
      expect(t.hasBudget, isFalse);
      expect(t.authorName, isNull);
      expect(t.isIncome, isTrue);
      expect(t.amount, 800);
    });
  });

  test('canBeManagedBy: the author or the wallet owner (HU-18/HU-19)', () {
    final t = transactionFixture(userId: 'u2');
    expect(t.canBeManagedBy('u2', walletIsOwner: false), isTrue);
    expect(t.canBeManagedBy('u3', walletIsOwner: true), isTrue);
    expect(t.canBeManagedBy('u3', walletIsOwner: false), isFalse);
    expect(t.canBeManagedBy(null, walletIsOwner: false), isFalse);
  });

  test('TransactionInput.toParams sends every field (update replaces the row)', () {
    final input = TransactionInput(
      name: '  Taxi ',
      type: TransactionType.expense,
      amountCents: 350,
      date: DateTime(2026, 10, 2),
    );
    expect(input.toParams(), {
      'p_name': 'Taxi',
      'p_type': 'expense',
      'p_amount': 3.5,
      'p_date': '2026-10-02',
      'p_budget_id': null,
    });
    expect(TransactionInput.fromTransaction(transactionFixture(budgetId: 2)).budgetId, 2);
  });
}
