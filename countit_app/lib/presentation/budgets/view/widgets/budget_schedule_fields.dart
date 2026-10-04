import 'package:flutter/material.dart';

import '../../../../app/theme/tokens.dart';
import '../../../../data/dtos/budget.dart';
import '../../../../shared/widgets/app_fields.dart';

/// Period and dates of a budget (COU-221): renewing periods need only the
/// start (the anchor of every window); «Sin renovación» also asks for the end.
class BudgetScheduleFields extends StatelessWidget {
  const BudgetScheduleFields({
    super.key,
    required this.period,
    required this.startDate,
    required this.endDate,
    required this.onPeriodChanged,
    required this.onStartChanged,
    required this.onEndChanged,
    required this.firstDate,
    required this.lastDate,
    this.endDateError,
    this.enabled = true,
  });

  final BudgetPeriod period;
  final DateTime startDate;
  final DateTime? endDate;
  final ValueChanged<BudgetPeriod> onPeriodChanged;
  final ValueChanged<DateTime> onStartChanged;
  final ValueChanged<DateTime> onEndChanged;

  /// Bounds of both date pickers.
  final DateTime firstDate;
  final DateTime lastDate;
  final String? endDateError;
  final bool enabled;

  /// Order of the design: the usual renewals first, fixed dates last.
  static const _order = [BudgetPeriod.weekly, BudgetPeriod.monthly, BudgetPeriod.yearly, BudgetPeriod.none];

  /// What the chosen period means for the windows.
  static String helperFor(BudgetPeriod period) => switch (period) {
    BudgetPeriod.weekly => 'Se renueva cada 7 días desde la fecha de inicio.',
    BudgetPeriod.monthly => 'Se renueva cada mes, el mismo día de la fecha de inicio.',
    BudgetPeriod.yearly => 'Se renueva cada año en la fecha de inicio.',
    BudgetPeriod.none => 'Cuenta solo los movimientos entre la fecha de inicio y la de fin.',
  };

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: AppSpacing.lg,
      children: [
        AppChoiceChips<BudgetPeriod>(
          label: 'Periodo',
          options: [for (final p in _order) AppOption(p, p.label)],
          value: period,
          onChanged: onPeriodChanged,
          helper: helperFor(period),
          enabled: enabled,
        ),
        AppDateField(
          key: const ValueKey('budget-start-date'),
          label: 'Fecha de inicio',
          value: startDate,
          onChanged: onStartChanged,
          firstDate: firstDate,
          lastDate: lastDate,
          enabled: enabled,
        ),
        if (!period.renews)
          AppDateField(
            key: const ValueKey('budget-end-date'),
            label: 'Fecha de fin',
            value: endDate,
            onChanged: onEndChanged,
            // The end can never be before the start.
            firstDate: startDate,
            lastDate: lastDate,
            errorText: endDateError,
            enabled: enabled,
          ),
      ],
    );
  }
}
