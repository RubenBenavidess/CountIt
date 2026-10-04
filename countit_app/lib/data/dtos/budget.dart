import 'package:equatable/equatable.dart';

import '../../shared/utils/dates.dart';
import 'json_parsing.dart';

/// `public.transaction_type` as a budget kind (API: Presupuestos · `p_type`).
enum BudgetType {
  expense('expense', 'Gasto'),
  income('income', 'Ingreso');

  const BudgetType(this.apiValue, this.label);

  final String apiValue;
  final String label;

  /// Unknown values fall back to [expense], the API default.
  static BudgetType parse(Object? value) => value == income.apiValue ? income : expense;
}

/// `public.budget_period`: how the budget renews (API: Presupuestos · periodos).
enum BudgetPeriod {
  /// Fixed dates: requires an end date and never renews.
  none('none', 'Sin renovación'),
  weekly('weekly', 'Semanal'),
  monthly('monthly', 'Mensual'),
  yearly('yearly', 'Anual');

  const BudgetPeriod(this.apiValue, this.label);

  final String apiValue;
  final String label;

  bool get renews => this != none;

  /// Unknown values fall back to [monthly], the API default.
  static BudgetPeriod parse(Object? value) {
    for (final period in values) {
      if (period.apiValue == value) return period;
    }
    return monthly;
  }
}

/// `public.budget_icon`: the visual category catalogue the API accepts.
enum BudgetIcon {
  groceries('groceries', 'Supermercado'),
  home('home', 'Hogar'),
  utilities('utilities', 'Servicios básicos'),
  transport('transport', 'Transporte'),
  food('food', 'Comida'),
  health('health', 'Salud'),
  education('education', 'Educación'),
  entertainment('entertainment', 'Entretenimiento'),
  clothing('clothing', 'Ropa'),
  travel('travel', 'Viajes'),
  gifts('gifts', 'Regalos'),
  pets('pets', 'Mascotas'),
  phone('phone', 'Teléfono e internet'),
  savings('savings', 'Ahorro'),
  salary('salary', 'Sueldo'),
  business('business', 'Negocio'),
  debt('debt', 'Deudas'),
  other('other', 'Otro');

  const BudgetIcon(this.apiValue, this.label);

  final String apiValue;
  final String label;

  /// Null for a missing or unknown value (the icon is optional).
  static BudgetIcon? parse(Object? value) {
    for (final icon in values) {
      if (icon.apiValue == value) return icon;
    }
    return null;
  }
}

/// Where the current window stands, for the progress indicator (COU-218).
enum BudgetStatus {
  /// Expense budget below 80 % of the limit.
  onTrack,

  /// Expense budget at 80 % or more without passing the limit (the backend
  /// sends the `budget_warning` notification at the same threshold).
  warning,

  /// Expense budget past its limit (`is_exceeded`).
  exceeded,

  /// Income budget still short of its goal.
  inProgress,

  /// Income budget that reached its goal.
  goalReached,
}

/// A row of `api.v_budgets` (HU-12): an active budget with its current window
/// and what was spent (or earned) in it.
///
/// Amounts in cents ([Cents]) like [Wallet]; `progress_pct` comes rounded to
/// 2 decimals by the API (it is not clamped: 130 means 30 % over).
class Budget extends Equatable {
  const Budget({
    required this.budgetId,
    required this.walletId,
    required this.name,
    required this.limitCents,
    required this.startDate,
    this.type = BudgetType.expense,
    this.period = BudgetPeriod.monthly,
    this.icon,
    this.endDate,
    this.windowStart,
    this.windowEnd,
    this.spentCents = 0,
    this.remainingCents = 0,
    this.progressPct = 0,
    this.isExceeded = false,
    this.createdBy,
  });

  factory Budget.fromJson(Map<String, dynamic> json) {
    final limit = Cents.parse(json['limit_amount']) ?? 0;
    final spent = Cents.parse(json['spent']) ?? 0;
    return Budget(
      budgetId: (json['budget_id'] as num).toInt(),
      walletId: (json['wallet_id'] as num).toInt(),
      name: (json['name'] as String?) ?? '',
      type: BudgetType.parse(json['type']),
      period: BudgetPeriod.parse(json['period']),
      icon: BudgetIcon.parse(json['icon']),
      limitCents: limit,
      startDate: _day(json['start_date']) ?? DateTime(1970),
      endDate: _day(json['end_date']),
      windowStart: _day(json['window_start']),
      windowEnd: _day(json['window_end']),
      spentCents: spent,
      remainingCents: Cents.parse(json['remaining']) ?? limit - spent,
      progressPct: _number(json['progress_pct']),
      isExceeded: json['is_exceeded'] == true,
      createdBy: json['created_by'] as String?,
    );
  }

  static double _number(Object? value) => switch (value) {
    num() => value.toDouble(),
    String() => double.tryParse(value) ?? 0,
    _ => 0,
  };

  static DateTime? _day(Object? value) => value is String && value.isNotEmpty ? Dates.parseDay(value) : null;

  /// Share of the limit at which an expense budget warns (backend: 80 %).
  static const warningPct = 80.0;

  final int budgetId;
  final int walletId;
  final String name;
  final BudgetType type;
  final BudgetPeriod period;
  final BudgetIcon? icon;
  final int limitCents;

  /// Anchor of the windows (`start_date`).
  final DateTime startDate;

  /// Only for [BudgetPeriod.none].
  final DateTime? endDate;

  /// Current window (the first one while the budget has not started).
  final DateTime? windowStart;
  final DateTime? windowEnd;

  /// Spent (expense) or earned (income) in the current window.
  final int spentCents;

  /// `limit - spent`: negative once exceeded.
  final int remainingCents;
  final double progressPct;
  final bool isExceeded;

  /// Author: with the wallet owner, the only one allowed to delete it (HU-14).
  final String? createdBy;

  bool get isIncome => type == BudgetType.income;

  /// 0..∞ share of the limit for progress bars.
  double get progress => progressPct / 100;

  BudgetStatus get status {
    if (isIncome) return spentCents >= limitCents ? BudgetStatus.goalReached : BudgetStatus.inProgress;
    if (isExceeded) return BudgetStatus.exceeded;
    return progressPct >= warningPct ? BudgetStatus.warning : BudgetStatus.onTrack;
  }

  /// Not started yet on [today] (its first window lies ahead).
  bool hasNotStarted(DateTime today) => startDate.isAfter(today);

  /// A fixed-dates budget whose end date already passed on [today].
  bool hasEnded(DateTime today) => !period.renews && endDate != null && endDate!.isBefore(today);

  /// HU-14: the wallet owner or the budget's author may delete it. Only a UI
  /// hint: the API answers 404 to anyone else.
  bool canBeDeletedBy(String? userId, {required bool walletIsOwner}) =>
      walletIsOwner || (userId != null && createdBy == userId);

  double get limit => Cents.toAmount(limitCents);
  double get spent => Cents.toAmount(spentCents);
  double get remaining => Cents.toAmount(remainingCents);

  @override
  List<Object?> get props => [
    budgetId,
    walletId,
    name,
    type,
    period,
    icon,
    limitCents,
    startDate,
    endDate,
    windowStart,
    windowEnd,
    spentCents,
    remainingCents,
    progressPct,
    isExceeded,
    createdBy,
  ];
}

/// What the budget form sends to `create_budget` / `update_budget`.
///
/// `update_budget` replaces the budget: an omitted icon is cleared, so
/// [toParams] always sends every field. The end date only travels with
/// [BudgetPeriod.none] (the API rejects it for renewing periods).
class BudgetInput extends Equatable {
  const BudgetInput({
    required this.name,
    required this.limitCents,
    required this.startDate,
    this.type = BudgetType.expense,
    this.period = BudgetPeriod.monthly,
    this.endDate,
    this.icon,
  });

  /// The form's current state for an existing budget (edit mode).
  factory BudgetInput.fromBudget(Budget budget) => BudgetInput(
    name: budget.name,
    limitCents: budget.limitCents,
    startDate: budget.startDate,
    type: budget.type,
    period: budget.period,
    endDate: budget.endDate,
    icon: budget.icon,
  );

  final String name;
  final int limitCents;
  final DateTime startDate;
  final BudgetType type;
  final BudgetPeriod period;
  final DateTime? endDate;
  final BudgetIcon? icon;

  Map<String, dynamic> toParams() => {
    'p_name': name.trim(),
    'p_limit_amount': Cents.toAmount(limitCents),
    'p_start_date': Dates.toApi(startDate),
    'p_period': period.apiValue,
    'p_end_date': period.renews || endDate == null ? null : Dates.toApi(endDate!),
    'p_type': type.apiValue,
    'p_icon': icon?.apiValue,
  };

  @override
  List<Object?> get props => [name, limitCents, startDate, type, period, endDate, icon];
}
