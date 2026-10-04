import 'package:countit_app/data/dtos/budget.dart';
import 'package:countit_app/data/dtos/scheduled_transaction.dart';
import 'package:countit_app/data/dtos/transaction.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/scheduled_fixtures.dart';

void main() {
  group('Periodicity', () {
    test('parses the API values and falls back to one_time', () {
      expect(Periodicity.parse('days'), Periodicity.days);
      expect(Periodicity.parse('one_time'), Periodicity.oneTime);
      expect(Periodicity.parse('fortnightly'), Periodicity.oneTime);
      expect(Periodicity.parse(null), Periodicity.oneTime);
    });

    test('describes the frequency in Spanish, singular and plural', () {
      expect(Periodicity.oneTime.describe(1), 'Una vez');
      expect(Periodicity.days.describe(1), 'Cada día');
      expect(Periodicity.weeks.describe(2), 'Cada 2 semanas');
      expect(Periodicity.months.describe(1), 'Cada mes');
      expect(Periodicity.months.describe(3), 'Cada 3 meses');
      expect(Periodicity.years.describe(1), 'Cada año');
      expect(Periodicity.years.describe(0), 'Cada año', reason: 'a broken interval never reads «Cada 0»');
    });
  });

  group('ScheduledTransaction.fromJson (v_scheduled_transactions)', () {
    final row = {
      'scheduled_transaction_id': 9,
      'wallet_id': 4,
      'wallet_name': 'Pichincha',
      'budget_id': 2,
      'budget_name': 'Vivienda',
      'budget_icon': 'home',
      'user_id': 'u1',
      'author_name': 'María Quishpe',
      'name': 'Arriendo',
      'type': 'expense',
      'amount': 350.5,
      'periodicity': 'months',
      'period_interval': 1,
      'start_date': '2026-11-05',
      'end_date': '2027-06-05',
      'next_run_date': '2026-11-05',
      'last_run_date': null,
      'is_active': true,
      'created_at': '2026-10-04T15:00:00+00:00',
      'updated_at': '2026-10-04T15:00:00+00:00',
      'paused_at': null,
      'is_paused': false,
    };

    test('reads every column', () {
      final rule = ScheduledTransaction.fromJson(row);
      expect(rule.scheduledTransactionId, 9);
      expect(rule.amountCents, 35050);
      expect(rule.type, TransactionType.expense);
      expect(rule.periodicity, Periodicity.months);
      expect(rule.periodInterval, 1);
      expect(rule.startDate, DateTime(2026, 11, 5));
      expect(rule.endDate, DateTime(2027, 6, 5));
      expect(rule.nextRunDate, DateTime(2026, 11, 5));
      expect(rule.lastRunDate, isNull);
      expect(rule.budgetIcon, BudgetIcon.home);
      expect(rule.isPaused, isFalse);
      expect(rule.isActive, isTrue);
      expect(rule.frequencyLabel, 'Cada mes');
    });

    test('a paused_at means paused even without is_paused (RPC payloads)', () {
      final rule = ScheduledTransaction.fromJson({...row, 'is_paused': null, 'paused_at': '2026-10-04T15:00:00+00:00'});
      expect(rule.isPaused, isTrue);
      expect(rule.pausedAt, isNotNull);
    });

    test('canBeManagedBy: the author or the wallet owner (HU-20)', () {
      final rule = scheduledFixture(userId: 'u1');
      expect(rule.canBeManagedBy('u1', walletIsOwner: false), isTrue);
      expect(rule.canBeManagedBy('u2', walletIsOwner: true), isTrue);
      expect(rule.canBeManagedBy('u2', walletIsOwner: false), isFalse);
      expect(rule.canBeManagedBy(null, walletIsOwner: false), isFalse);
    });

    test('mergeRule keeps the joined names of the listed row', () {
      final listed = scheduledFixture(budgetId: 2, budgetName: 'Vivienda', authorName: 'María');
      final fresh = ScheduledTransaction.fromJson({
        ...row,
        'budget_name': null,
        'author_name': null,
        'is_paused': true,
      });
      final merged = listed.mergeRule(fresh);
      expect(merged.budgetName, 'Vivienda');
      expect(merged.authorName, 'María');
      expect(merged.isPaused, isTrue);
      expect(merged.amountCents, 35050);
    });
  });

  group('ScheduledTransactionInput', () {
    final recurring = ScheduledTransactionInput(
      name: '  Netflix ',
      type: TransactionType.expense,
      amountCents: 1099,
      startDate: DateTime(2026, 10, 10),
      periodicity: Periodicity.months,
      interval: 1,
      endDate: DateTime(2027, 10, 10),
      budgetId: 5,
    );

    test('create params: every field, trimmed name, dates as API days', () {
      expect(recurring.toCreateParams(), {
        'p_name': 'Netflix',
        'p_type': 'expense',
        'p_amount': 10.99,
        'p_start_date': '2026-10-10',
        'p_periodicity': 'months',
        'p_period_interval': 1,
        'p_end_date': '2027-10-10',
        'p_budget_id': 5,
      });
    });

    test('update params never send the start date', () {
      expect(recurring.toUpdateParams().containsKey('p_start_date'), isFalse);
      expect(recurring.toUpdateParams()['p_end_date'], '2027-10-10');
    });

    test('one-time rules send interval 1 and no end date', () {
      final once = ScheduledTransactionInput(
        name: 'Matrícula',
        type: TransactionType.expense,
        amountCents: 12000,
        startDate: DateTime(2026, 10, 10),
        interval: 4,
        endDate: DateTime(2027),
      );
      final params = once.toCreateParams();
      expect(params['p_periodicity'], 'one_time');
      expect(params['p_period_interval'], 1);
      expect(params['p_end_date'], isNull);
      expect(params['p_budget_id'], isNull);
    });

    test('fromRule reproduces the rule (no spurious «unsaved changes»)', () {
      final rule = scheduledFixture(endDate: DateTime(2027, 1, 5), budgetId: 2);
      final input = ScheduledTransactionInput.fromRule(rule);
      expect(input.periodicity, Periodicity.months);
      expect(input.endDate, DateTime(2027, 1, 5));
      expect(input, ScheduledTransactionInput.fromRule(rule));
    });
  });
}
