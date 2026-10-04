import 'package:countit_app/data/dtos/budget.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/budget_fixtures.dart';

/// A `v_budgets` row as PostgREST returns it (contract 1.1).
const _row = <String, dynamic>{
  'budget_id': 9,
  'wallet_id': 4,
  'wallet_name': 'Ahorros',
  'name': 'Comida',
  'type': 'expense',
  'limit_amount': 150.1,
  'period': 'monthly',
  'start_date': '2026-09-15',
  'end_date': null,
  'window_start': '2026-09-15',
  'window_end': '2026-10-14',
  'spent': '120.2',
  'remaining': 29.9,
  'progress_pct': 80.08,
  'is_exceeded': false,
  'created_by': '6f0c1d7e-0000-0000-0000-000000000001',
  'created_at': '2026-09-15T15:00:00+00:00',
  'updated_at': '2026-09-15T15:00:00+00:00',
  'icon': 'groceries',
};

void main() {
  group('Budget.fromJson', () {
    test('reads every column of v_budgets', () {
      final budget = Budget.fromJson(_row);
      expect(budget.budgetId, 9);
      expect(budget.walletId, 4);
      expect(budget.name, 'Comida');
      expect(budget.type, BudgetType.expense);
      expect(budget.period, BudgetPeriod.monthly);
      expect(budget.icon, BudgetIcon.groceries);
      expect(budget.limitCents, 15010);
      expect(budget.spentCents, 12020);
      expect(budget.remainingCents, 2990);
      expect(budget.progressPct, 80.08);
      expect(budget.isExceeded, isFalse);
      expect(budget.startDate, DateTime(2026, 9, 15));
      expect(budget.endDate, isNull);
      expect(budget.windowStart, DateTime(2026, 9, 15));
      expect(budget.windowEnd, DateTime(2026, 10, 14));
      expect(budget.createdBy, '6f0c1d7e-0000-0000-0000-000000000001');
    });

    test('tolerates missing optionals and unknown enum values', () {
      final budget = Budget.fromJson(const {
        'budget_id': 1,
        'wallet_id': 2,
        'name': 'X',
        'limit_amount': 10,
        'start_date': '2026-10-01',
        'type': 'weird',
        'period': 'daily',
        'icon': 'rocket',
        'progress_pct': '12.5',
      });
      expect(budget.type, BudgetType.expense);
      expect(budget.period, BudgetPeriod.monthly);
      expect(budget.icon, isNull);
      expect(budget.progressPct, 12.5);
      expect(budget.remainingCents, 1000, reason: 'limit - spent when remaining is missing');
    });

    test('the icon catalogue matches the API enum', () {
      expect(BudgetIcon.values.map((i) => i.apiValue), [
        'groceries', 'home', 'utilities', 'transport', 'food', 'health', 'education', 'entertainment', //
        'clothing', 'travel', 'gifts', 'pets', 'phone', 'savings', 'salary', 'business', 'debt', 'other',
      ]);
      expect(BudgetPeriod.values.map((p) => p.apiValue), ['none', 'weekly', 'monthly', 'yearly']);
    });
  });

  group('status (COU-218)', () {
    test('expense: on track below 80 %, warning from 80 %, exceeded past the limit', () {
      expect(budgetFixture(spent: 79.99).status, BudgetStatus.onTrack);
      expect(budgetFixture(spent: 80).status, BudgetStatus.warning);
      expect(budgetFixture(spent: 100).status, BudgetStatus.warning, reason: 'at the limit is not over it');
      expect(budgetFixture(spent: 100.01).status, BudgetStatus.exceeded);
    });

    test('income: in progress until the goal is reached', () {
      expect(budgetFixture(type: BudgetType.income, spent: 99).status, BudgetStatus.inProgress);
      expect(budgetFixture(type: BudgetType.income, spent: 100).status, BudgetStatus.goalReached);
      expect(budgetFixture(type: BudgetType.income, spent: 150).status, BudgetStatus.goalReached);
    });

    test('not started and ended on the user day', () {
      final today = DateTime(2026, 10, 3);
      expect(budgetFixture(startDate: DateTime(2026, 11, 1)).hasNotStarted(today), isTrue);
      expect(budgetFixture().hasNotStarted(today), isFalse);
      final fixed = budgetFixture(period: BudgetPeriod.none, endDate: DateTime(2026, 10, 2));
      expect(fixed.hasEnded(today), isTrue);
      expect(budgetFixture(period: BudgetPeriod.none, endDate: today).hasEnded(today), isFalse);
    });
  });

  test('canBeDeletedBy: wallet owner or author only (HU-14)', () {
    final budget = budgetFixture(createdBy: 'u1');
    expect(budget.canBeDeletedBy('u2', walletIsOwner: true), isTrue);
    expect(budget.canBeDeletedBy('u1', walletIsOwner: false), isTrue);
    expect(budget.canBeDeletedBy('u2', walletIsOwner: false), isFalse);
    expect(budgetFixture(createdBy: null).canBeDeletedBy(null, walletIsOwner: false), isFalse);
  });

  group('BudgetInput.toParams', () {
    test('sends every field, dates as API days and the icon (null clears it)', () {
      final input = BudgetInput(
        name: '  Comida ',
        limitCents: 15050,
        startDate: DateTime(2026, 10, 1),
        icon: BudgetIcon.food,
      );
      expect(input.toParams(), {
        'p_name': 'Comida',
        'p_limit_amount': 150.5,
        'p_start_date': '2026-10-01',
        'p_period': 'monthly',
        'p_end_date': null,
        'p_type': 'expense',
        'p_icon': 'food',
      });
      expect(BudgetInput(name: 'A', limitCents: 1, startDate: DateTime(2026)).toParams()['p_icon'], isNull);
    });

    test('the end date only travels with period none', () {
      final end = DateTime(2026, 12, 31);
      final renewing = BudgetInput(name: 'A', limitCents: 100, startDate: DateTime(2026, 10), endDate: end);
      expect(renewing.toParams()['p_end_date'], isNull);
      final fixed = BudgetInput(
        name: 'A',
        limitCents: 100,
        startDate: DateTime(2026, 10),
        period: BudgetPeriod.none,
        endDate: end,
        type: BudgetType.income,
      );
      expect(fixed.toParams(), containsPair('p_end_date', '2026-12-31'));
      expect(fixed.toParams(), containsPair('p_type', 'income'));
    });

    test('fromBudget mirrors the row', () {
      final budget = budgetFixture(period: BudgetPeriod.none, endDate: DateTime(2026, 12, 31));
      final input = BudgetInput.fromBudget(budget);
      expect(input.name, budget.name);
      expect(input.limitCents, budget.limitCents);
      expect(input.period, BudgetPeriod.none);
      expect(input.endDate, DateTime(2026, 12, 31));
      expect(input.icon, BudgetIcon.food);
    });
  });
}
