import 'package:flutter/material.dart';

import '../../../../app/theme/tokens.dart';
import '../../../../data/dtos/budget.dart';
import '../../../../data/dtos/transaction.dart';
import '../../../../shared/utils/dates.dart';
import '../../../../shared/widgets/app_button.dart';
import '../../../../shared/widgets/app_dialogs.dart';
import '../../../../shared/widgets/app_fields.dart';

/// One active filter as a removable chip: its label and the filter without it.
typedef ActiveFilter = ({String key, String label, TransactionFilter without});

extension TransactionFilterLabels on TransactionFilter {
  /// The active groups, in the sheet's order (COU-233).
  List<ActiveFilter> get active => [
    if (type != null)
      (key: 'type', label: type == TransactionType.income ? 'Ingresos' : 'Gastos', without: withoutType()),
    if (hasDates) (key: 'dates', label: datesLabel, without: withoutDates()),
    if (hasBudget)
      (
        key: 'budget',
        label: withoutBudget ? 'Sin presupuesto' : (budgetName ?? 'Presupuesto'),
        without: withoutBudgetFilter(),
      ),
    if (authorId != null) (key: 'author', label: authorName ?? 'Autor', without: withoutAuthor()),
  ];

  /// «1 oct – 31 oct 2026», «Desde 1 oct 2026» or «Hasta 3 oct 2026».
  String get datesLabel {
    if (from != null && to != null) return Dates.range(from!, to!);
    if (from != null) return 'Desde ${Dates.date(from!)}';
    return 'Hasta ${Dates.date(to!)}';
  }
}

/// Opens the filters sheet; returns the new filter, or null when dismissed.
///
/// [authors] (`user_id` → name) is offered only in shared wallets; the
/// budget filter only when one wallet is listed ([showBudget]).
Future<TransactionFilter?> showTransactionFilters(
  BuildContext context, {
  required TransactionFilter current,
  required List<Budget> budgets,
  required Map<String, String> authors,
  required DateTime today,
  bool showBudget = true,
}) => showAppBottomSheet<TransactionFilter>(
  context,
  title: 'Filtrar movimientos',
  builder: (_) => Flexible(
    child: TransactionFilterForm(
      initial: current,
      budgets: budgets,
      authors: authors,
      today: today,
      showBudget: showBudget,
    ),
  ),
);

enum _DatePreset {
  all('Todo'),
  month('Este mes'),
  last30('Últimos 30 días'),
  custom('Personalizado');

  const _DatePreset(this.label);

  final String label;
}

/// Body of the filters sheet: edits a draft and pops it on «Aplicar».
class TransactionFilterForm extends StatefulWidget {
  const TransactionFilterForm({
    super.key,
    required this.initial,
    required this.budgets,
    required this.authors,
    required this.today,
    this.showBudget = true,
  });

  final TransactionFilter initial;
  final List<Budget> budgets;
  final Map<String, String> authors;
  final DateTime today;

  /// Budgets belong to one wallet: hidden when the list mixes several.
  final bool showBudget;

  @override
  State<TransactionFilterForm> createState() => _TransactionFilterFormState();
}

class _TransactionFilterFormState extends State<TransactionFilterForm> {
  static const _all = 'all';
  static const _none = 'none';

  late TransactionFilter _draft = widget.initial;
  late _DatePreset _preset = _presetOf(widget.initial);

  DateTime get _monthStart => DateTime(widget.today.year, widget.today.month);
  DateTime get _last30Start => DateTime(widget.today.year, widget.today.month, widget.today.day - 29);

  _DatePreset _presetOf(TransactionFilter f) {
    if (!f.hasDates) return _DatePreset.all;
    if (f.to == null && f.from == _monthStart) return _DatePreset.month;
    if (f.to == null && f.from == _last30Start) return _DatePreset.last30;
    return _DatePreset.custom;
  }

  void _setPreset(_DatePreset preset) => setState(() {
    _preset = preset;
    _draft = switch (preset) {
      _DatePreset.all => _draft.withoutDates(),
      _DatePreset.month => _draft.copyWith(from: () => _monthStart, to: () => null),
      _DatePreset.last30 => _draft.copyWith(from: () => _last30Start, to: () => null),
      _DatePreset.custom => _draft,
    };
  });

  String? get _rangeError {
    final from = _draft.from;
    final to = _draft.to;
    return from != null && to != null && to.isBefore(from) ? 'La fecha final no puede ser anterior a la inicial' : null;
  }

  String get _budgetValue => _draft.withoutBudget ? _none : (_draft.budgetId?.toString() ?? _all);

  void _setBudget(String? value) => setState(() {
    if (value == _none) {
      _draft = _draft.copyWith(budget: (id: null, name: null, without: true));
      return;
    }
    final budget = widget.budgets.where((b) => b.budgetId.toString() == value).firstOrNull;
    _draft = _draft.copyWith(budget: (id: budget?.budgetId, name: budget?.name, without: false));
  });

  void _setAuthor(String? value) => setState(() {
    final name = widget.authors[value];
    _draft = _draft.copyWith(author: (id: name == null ? null : value, name: name));
  });

  @override
  Widget build(BuildContext context) {
    final rangeError = _rangeError;
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: AppSpacing.lg,
        children: [
          AppChoiceChips<TransactionType?>(
            label: 'Tipo',
            options: const [
              AppOption(null, 'Todos'),
              AppOption(TransactionType.expense, 'Gastos'),
              AppOption(TransactionType.income, 'Ingresos'),
            ],
            value: _draft.type,
            onChanged: (type) => setState(() => _draft = _draft.copyWith(type: () => type)),
          ),
          AppChoiceChips<_DatePreset>(
            label: 'Fechas',
            options: [for (final p in _DatePreset.values) AppOption(p, p.label)],
            value: _preset,
            onChanged: _setPreset,
          ),
          if (_preset == _DatePreset.custom)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: AppSpacing.md,
              children: [
                Expanded(
                  child: AppDateField(
                    label: 'Desde',
                    value: _draft.from,
                    placeholder: 'Sin límite',
                    firstDate: DateTime(widget.today.year - 10),
                    lastDate: widget.today,
                    onChanged: (day) => setState(() => _draft = _draft.copyWith(from: () => day)),
                  ),
                ),
                Expanded(
                  child: AppDateField(
                    label: 'Hasta',
                    value: _draft.to,
                    placeholder: 'Sin límite',
                    firstDate: DateTime(widget.today.year - 10),
                    lastDate: widget.today,
                    errorText: rangeError,
                    onChanged: (day) => setState(() => _draft = _draft.copyWith(to: () => day)),
                  ),
                ),
              ],
            ),
          if (widget.showBudget)
            AppDropdownField<String>(
              label: 'Presupuesto',
              value: _budgetValue,
              options: [
                const AppOption(_all, 'Todos'),
                const AppOption(_none, 'Sin presupuesto'),
                for (final b in widget.budgets) AppOption(b.budgetId.toString(), b.name),
              ],
              onChanged: _setBudget,
            ),
          if (widget.authors.isNotEmpty)
            AppDropdownField<String>(
              label: 'Registrado por',
              value: _draft.authorId ?? _all,
              options: [
                const AppOption(_all, 'Cualquier miembro'),
                for (final MapEntry(:key, :value) in widget.authors.entries) AppOption(key, value),
              ],
              onChanged: _setAuthor,
            ),
          AppButton(
            label: 'Aplicar filtros',
            onPressed: rangeError == null ? () => Navigator.of(context).pop(_draft) : null,
          ),
          AppButton(
            label: 'Limpiar filtros',
            variant: AppButtonVariant.ghost,
            onPressed: () => Navigator.of(context).pop(const TransactionFilter()),
          ),
        ],
      ),
    );
  }
}
