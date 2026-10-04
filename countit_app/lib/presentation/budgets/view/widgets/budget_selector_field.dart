import 'package:flutter/material.dart';

import '../../../../data/dtos/budget.dart';
import '../../../../shared/state/load_state.dart';
import '../../../../shared/widgets/app_fields.dart';

/// A budget the selector must keep offering although it is no longer active
/// (edit mode: the transaction still points to a deleted budget, which the
/// API accepts as long as it is not changed).
typedef RetiredBudget = ({int id, String name});

/// «Presupuesto» of a transaction (COU-236): «Sin presupuesto» plus the
/// wallet's budgets of the same [type] (the API rejects the others with
/// `budget_type_mismatch`). Loading or failing to load the budgets never
/// blocks the form: «Sin presupuesto» is always available.
class BudgetSelectorField extends StatelessWidget {
  const BudgetSelectorField({
    super.key,
    required this.budgets,
    required this.type,
    required this.value,
    required this.onChanged,
    this.retired,
    this.errorText,
    this.enabled = true,
  });

  static const noneLabel = 'Sin presupuesto';

  final LoadState<List<Budget>> budgets;
  final BudgetType type;

  /// Selected budget id; null = «Sin presupuesto».
  final int? value;
  final ValueChanged<int?> onChanged;
  final RetiredBudget? retired;
  final String? errorText;
  final bool enabled;

  /// Options for [type]: none first, then the matching budgets by name.
  static List<AppOption<int?>> optionsFor(List<Budget> budgets, BudgetType type, {RetiredBudget? retired}) => [
    const AppOption<int?>(null, noneLabel),
    for (final budget in budgets)
      if (budget.type == type) AppOption<int?>(budget.budgetId, budget.name),
    if (retired != null && !budgets.any((b) => b.budgetId == retired.id))
      AppOption<int?>(retired.id, '${retired.name} (eliminado)'),
  ];

  String? get _helper => switch (budgets.status) {
    LoadStatus.initial || LoadStatus.loading when budgets.data == null => 'Cargando presupuestos…',
    LoadStatus.failure when budgets.data == null => 'No pudimos cargar los presupuestos.',
    _ => type == BudgetType.expense ? 'Solo presupuestos de gastos.' : 'Solo presupuestos de ingresos.',
  };

  @override
  Widget build(BuildContext context) {
    final options = optionsFor(budgets.data ?? const [], type, retired: retired);
    // A value the options no longer contain (type changed) shows as «Sin presupuesto».
    final selected = options.any((o) => o.value == value) ? value : null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppDropdownField<int?>(
          label: 'Presupuesto',
          options: options,
          value: selected,
          hint: noneLabel,
          errorText: errorText,
          enabled: enabled,
          onChanged: onChanged,
        ),
        if (errorText == null && _helper != null)
          Padding(
            padding: const EdgeInsets.only(top: 6, left: 4),
            child: Text(_helper!, style: Theme.of(context).textTheme.bodySmall),
          ),
      ],
    );
  }
}
