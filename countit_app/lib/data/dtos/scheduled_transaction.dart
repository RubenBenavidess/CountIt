import 'package:equatable/equatable.dart';

import '../../shared/utils/dates.dart';
import 'budget.dart';
import 'json_parsing.dart';
import 'transaction.dart';

/// `public.periodicity_enum` (API: Programadas · `p_periodicity`): a single
/// occurrence or every [ScheduledTransaction.periodInterval] days, weeks,
/// months or years.
enum Periodicity {
  oneTime('one_time', 'Una vez'),
  days('days', 'Días'),
  weeks('weeks', 'Semanas'),
  months('months', 'Meses'),
  years('years', 'Años');

  const Periodicity(this.apiValue, this.label);

  final String apiValue;

  /// Chip label of the form.
  final String label;

  bool get recurs => this != oneTime;

  /// Unknown values fall back to [oneTime], the API default.
  static Periodicity parse(Object? value) {
    for (final periodicity in values) {
      if (periodicity.apiValue == value) return periodicity;
    }
    return oneTime;
  }

  /// «Una vez», «Cada día», «Cada 2 semanas», «Cada mes», «Cada 3 años».
  String describe(int interval) {
    final n = interval < 1 ? 1 : interval;
    return switch (this) {
      oneTime => 'Una vez',
      days => n == 1 ? 'Cada día' : 'Cada $n días',
      weeks => n == 1 ? 'Cada semana' : 'Cada $n semanas',
      months => n == 1 ? 'Cada mes' : 'Cada $n meses',
      years => n == 1 ? 'Cada año' : 'Cada $n años',
    };
  }

  /// Unit after «Cada N» in the interval field («días», «semanas»…).
  String unit(int interval) => switch (this) {
    oneTime => '',
    days => interval == 1 ? 'día' : 'días',
    weeks => interval == 1 ? 'semana' : 'semanas',
    months => interval == 1 ? 'mes' : 'meses',
    years => interval == 1 ? 'año' : 'años',
  };
}

/// A row of `api.v_scheduled_transactions` (HU-16/HU-20): an active (not
/// ended nor deleted) rule of a wallet the caller can read, with its next
/// run and pause state. The RPCs return the same fields without the joined
/// names (wallet, budget, author).
///
/// Amounts in cents ([Cents]) like [Transaction].
class ScheduledTransaction extends Equatable {
  const ScheduledTransaction({
    required this.scheduledTransactionId,
    required this.walletId,
    required this.name,
    required this.type,
    required this.amountCents,
    required this.periodicity,
    required this.startDate,
    this.periodInterval,
    this.endDate,
    this.nextRunDate,
    this.lastRunDate,
    this.walletName,
    this.budgetId,
    this.budgetName,
    this.budgetIcon,
    this.userId,
    this.authorName,
    this.isActive = true,
    this.pausedAt,
    this.isPaused = false,
    this.createdAt,
    this.updatedAt,
  });

  factory ScheduledTransaction.fromJson(Map<String, dynamic> json) {
    DateTime? day(Object? value) => value is String ? Dates.parseDay(value) : null;
    return ScheduledTransaction(
      scheduledTransactionId: (json['scheduled_transaction_id'] as num).toInt(),
      walletId: (json['wallet_id'] as num).toInt(),
      walletName: json['wallet_name'] as String?,
      budgetId: (json['budget_id'] as num?)?.toInt(),
      budgetName: json['budget_name'] as String?,
      budgetIcon: BudgetIcon.parse(json['budget_icon']),
      userId: json['user_id'] as String?,
      authorName: json['author_name'] as String?,
      name: (json['name'] as String?) ?? '',
      type: TransactionType.parse(json['type']),
      amountCents: Cents.parse(json['amount']) ?? 0,
      periodicity: Periodicity.parse(json['periodicity']),
      periodInterval: (json['period_interval'] as num?)?.toInt(),
      startDate: day(json['start_date']) ?? DateTime(1970),
      endDate: day(json['end_date']),
      nextRunDate: day(json['next_run_date']),
      lastRunDate: day(json['last_run_date']),
      isActive: json['is_active'] != false,
      pausedAt: parseTimestamp(json['paused_at']),
      isPaused: json['is_paused'] == true || json['paused_at'] != null,
      createdAt: parseTimestamp(json['created_at']),
      updatedAt: parseTimestamp(json['updated_at']),
    );
  }

  final int scheduledTransactionId;
  final int walletId;
  final String? walletName;

  /// Null = «Sin presupuesto».
  final int? budgetId;
  final String? budgetName;
  final BudgetIcon? budgetIcon;

  /// Author: the only one (with the wallet owner) who may manage the rule,
  /// and whose plan quota it uses.
  final String? userId;
  final String? authorName;

  final String name;
  final TransactionType type;
  final int amountCents;

  final Periodicity periodicity;

  /// 1..365 for recurring rules; null for [Periodicity.oneTime].
  final int? periodInterval;

  /// Calendar days in the author's zone; [startDate] never changes after creation.
  final DateTime startDate;
  final DateTime? endDate;
  final DateTime? nextRunDate;
  final DateTime? lastRunDate;

  /// False once the rule ended (nothing left to run) or was deleted.
  final bool isActive;
  final DateTime? pausedAt;
  final bool isPaused;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  bool get isIncome => type == TransactionType.income;
  bool get hasBudget => budgetId != null;
  double get amount => Cents.toAmount(amountCents);

  /// «Cada mes», «Una vez»…
  String get frequencyLabel => periodicity.describe(periodInterval ?? 1);

  /// HU-20: the author or the wallet owner may edit, pause or delete it. Only
  /// a UI hint: the API answers 404 to anyone else.
  bool canBeManagedBy(String? userId, {required bool walletIsOwner}) =>
      walletIsOwner || (userId != null && this.userId == userId);

  /// The state an RPC returned (`set_scheduled_transaction_paused`, update)
  /// on top of this listed row, keeping the names only the view joins.
  ScheduledTransaction mergeRule(ScheduledTransaction fresh) => ScheduledTransaction(
    scheduledTransactionId: scheduledTransactionId,
    walletId: walletId,
    walletName: walletName,
    budgetId: fresh.budgetId,
    budgetName: fresh.budgetId == budgetId ? budgetName : fresh.budgetName,
    budgetIcon: fresh.budgetId == budgetId ? budgetIcon : fresh.budgetIcon,
    userId: userId,
    authorName: authorName,
    name: fresh.name,
    type: fresh.type,
    amountCents: fresh.amountCents,
    periodicity: fresh.periodicity,
    periodInterval: fresh.periodInterval,
    startDate: fresh.startDate,
    endDate: fresh.endDate,
    nextRunDate: fresh.nextRunDate,
    lastRunDate: fresh.lastRunDate,
    isActive: fresh.isActive,
    pausedAt: fresh.pausedAt,
    isPaused: fresh.isPaused,
    createdAt: createdAt,
    updatedAt: fresh.updatedAt,
  );

  @override
  List<Object?> get props => [
    scheduledTransactionId,
    walletId,
    walletName,
    budgetId,
    budgetName,
    budgetIcon,
    userId,
    authorName,
    name,
    type,
    amountCents,
    periodicity,
    periodInterval,
    startDate,
    endDate,
    nextRunDate,
    lastRunDate,
    isActive,
    pausedAt,
    isPaused,
    createdAt,
    updatedAt,
  ];
}

/// The caller's own active rules across every wallet: the plan quota
/// (`max_scheduled_transactions`) counts them all when creating, and only the
/// running ones when resuming a paused rule (HU-20).
class ScheduledUsage extends Equatable {
  const ScheduledUsage({required this.total, required this.running});

  final int total;
  final int running;

  int get paused => total - running;

  @override
  List<Object?> get props => [total, running];
}

/// What the rule form sends to `create_scheduled_transaction` /
/// `update_scheduled_transaction`. The update replaces every editable field
/// (an omitted budget or end date is cleared) and never changes the start.
class ScheduledTransactionInput extends Equatable {
  const ScheduledTransactionInput({
    required this.name,
    required this.type,
    required this.amountCents,
    required this.startDate,
    this.periodicity = Periodicity.oneTime,
    this.interval = 1,
    this.endDate,
    this.budgetId,
  });

  /// The form's current state for an existing rule (edit mode).
  factory ScheduledTransactionInput.fromRule(ScheduledTransaction rule) => ScheduledTransactionInput(
    name: rule.name,
    type: rule.type,
    amountCents: rule.amountCents,
    startDate: rule.startDate,
    periodicity: rule.periodicity,
    interval: rule.periodInterval ?? 1,
    endDate: rule.periodicity.recurs ? rule.endDate : null,
    budgetId: rule.budgetId,
  );

  final String name;
  final TransactionType type;
  final int amountCents;
  final DateTime startDate;
  final Periodicity periodicity;

  /// Ignored (sent as 1) for a one-time rule.
  final int interval;

  /// Only for recurring rules; null = no end.
  final DateTime? endDate;
  final int? budgetId;

  Map<String, dynamic> _common() => {
    'p_name': name.trim(),
    'p_type': type.apiValue,
    'p_amount': Cents.toAmount(amountCents),
    'p_periodicity': periodicity.apiValue,
    'p_period_interval': periodicity.recurs ? interval : 1,
    'p_end_date': periodicity.recurs && endDate != null ? Dates.toApi(endDate!) : null,
    'p_budget_id': budgetId,
  };

  /// `create_scheduled_transaction` (without the wallet id).
  Map<String, dynamic> toCreateParams() => {..._common(), 'p_start_date': Dates.toApi(startDate)};

  /// `update_scheduled_transaction` (without the rule id): the start is fixed.
  Map<String, dynamic> toUpdateParams() => _common();

  @override
  List<Object?> get props => [
    name,
    type,
    amountCents,
    startDate,
    periodicity,
    periodicity.recurs ? interval : 1,
    periodicity.recurs ? endDate : null,
    budgetId,
  ];
}
