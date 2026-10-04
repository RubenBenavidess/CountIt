import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../app/errors/app_failure.dart';
import '../../../app/router/app_router.dart';
import '../../../app/session/session_cubit.dart';
import '../../../app/theme/app_theme.dart';
import '../../../app/theme/tokens.dart';
import '../../../data/dtos/budget.dart';
import '../../../data/dtos/json_parsing.dart';
import '../../../data/dtos/scheduled_transaction.dart';
import '../../../data/dtos/transaction.dart';
import '../../../data/repositories/budget_repository.dart';
import '../../../data/repositories/scheduled_transaction_repository.dart';
import '../../../shared/state/load_state.dart';
import '../../../shared/state/submit_cubit.dart';
import '../../../shared/utils/dates.dart';
import '../../../shared/utils/validators.dart';
import '../../../shared/widgets/app_banner.dart';
import '../../../shared/widgets/app_button.dart';
import '../../../shared/widgets/app_card.dart';
import '../../../shared/widgets/app_dialogs.dart';
import '../../../shared/widgets/app_feedback.dart';
import '../../../shared/widgets/app_fields.dart';
import '../../../shared/widgets/app_layout.dart';
import '../../budgets/cubit/budget_list_cubit.dart';
import '../../budgets/view/widgets/budget_selector_field.dart';
import '../../plans/view/plan_upsell_sheet.dart';
import '../../transactions/cubit/transaction_form_cubit.dart';
import '../cubit/scheduled_form_cubit.dart';

/// What the list passes to the edit route: the listed rule and whether the
/// caller may delete it ([ScheduledTransaction.canBeManagedBy]).
class ScheduledEditArgs {
  const ScheduledEditArgs(this.rule, {this.canDelete = false});

  final ScheduledTransaction rule;
  final bool canDelete;
}

/// Schedule (no [initial]) or edit a rule of [walletId] (HU-16/HU-20 ·
/// COU-89, COU-151, COU-152). [draft] pre-fills a new rule (a transaction
/// form with a future date hands its fields over). Pops with `true` after
/// saving.
class ScheduledFormPage extends StatelessWidget {
  const ScheduledFormPage({super.key, required this.walletId, this.initial, this.draft});

  final int walletId;
  final ScheduledTransaction? initial;
  final ScheduledTransactionInput? draft;

  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      providers: [
        BlocProvider(
          create: (context) => ScheduledFormCubit(
            context.read<ScheduledTransactionRepository>(),
            walletId: walletId,
            scheduledTransactionId: initial?.scheduledTransactionId,
          ),
        ),
        // The selector's options: the wallet's active budgets.
        BlocProvider(
          create: (context) => BudgetListCubit(context.read<BudgetRepository>(), walletId: walletId)..load(),
        ),
      ],
      child: _ScheduledFormView(initial: initial, draft: draft),
    );
  }
}

class _ScheduledFormView extends StatefulWidget {
  const _ScheduledFormView({this.initial, this.draft});

  final ScheduledTransaction? initial;
  final ScheduledTransactionInput? draft;

  @override
  State<_ScheduledFormView> createState() => _ScheduledFormViewState();
}

class _ScheduledFormViewState extends State<_ScheduledFormView> {
  static final _amountText = NumberFormat('0.00', 'es');

  /// Backend keys shown next to a field instead of the banner.
  static const _nameKeys = {'max_length'};
  static const _amountKeys = {'invalid_amount'};
  static const _startKeys = {'invalid_start_date'};
  static const _periodicityKeys = {'invalid_periodicity'};
  static const _intervalKeys = {'invalid_interval'};
  static const _endKeys = {'invalid_date_range'};
  static const _budgetKeys = {
    'budget_type_mismatch',
    'budget_not_active',
    'budget_wallet_mismatch',
    'budget_not_found',
  };
  static const _allFieldKeys = {
    ..._nameKeys,
    ..._amountKeys,
    ..._startKeys,
    ..._periodicityKeys,
    ..._intervalKeys,
    ..._endKeys,
    ..._budgetKeys,
  };

  final _formKey = GlobalKey<FormState>();

  /// The user's calendar day: rules start strictly after it.
  late final DateTime _today = Dates.userToday(context.read<SessionCubit>().state.profile?.timezone);
  late final DateTime _tomorrow = DateTime(_today.year, _today.month, _today.day + 1);
  late final DateTime _lastDate = DateTime(_today.year + 5, 12, 31);

  /// What «unsaved changes» compares against: the rule, or an empty form
  /// (a draft from the transaction form counts as unsaved).
  late final ScheduledTransactionInput _original = widget.initial == null
      ? ScheduledTransactionInput(name: '', type: TransactionType.expense, amountCents: 0, startDate: _tomorrow)
      : ScheduledTransactionInput.fromRule(widget.initial!);

  /// The form's first values: the rule, the draft or the empty form.
  late final ScheduledTransactionInput _seed = widget.initial == null ? (widget.draft ?? _original) : _original;

  late final _name = TextEditingController(text: _seed.name);
  late final _amount = TextEditingController(
    text: _seed.amountCents > 0 ? _amountText.format(Cents.toAmount(_seed.amountCents)) : '',
  );
  late final _interval = TextEditingController(text: '${_seed.interval}');
  late TransactionType _type = _seed.type;
  late Periodicity _periodicity = _seed.periodicity;
  late DateTime _startDate = _seed.startDate;
  late DateTime? _endDate = _seed.endDate;
  late int? _budgetId = _seed.budgetId;

  /// Shows the amount, date and interval errors only after a save attempt (or typing).
  bool _submitted = false;

  /// Set right before leaving after a successful save (no «discard?» dialog).
  bool _saved = false;

  bool get _editing => widget.initial != null;

  @override
  void initState() {
    super.initState();
    for (final c in [_name, _amount, _interval]) {
      c.addListener(_changed);
    }
  }

  @override
  void dispose() {
    for (final c in [_name, _amount, _interval]) {
      c.dispose();
    }
    super.dispose();
  }

  void _changed() {
    context.read<ScheduledFormCubit>().clearFailure();
    setState(() {});
  }

  void _update(VoidCallback change) {
    setState(change);
    context.read<ScheduledFormCubit>().clearFailure();
  }

  /// A budget of the other type cannot stay selected (`budget_type_mismatch`).
  void _setType(TransactionType type) => _update(() {
    _type = type;
    final budgets = context.read<BudgetListCubit>().state.data ?? const <Budget>[];
    final selected = budgets.where((b) => b.budgetId == _budgetId).firstOrNull;
    final stillValid = selected != null
        ? TransactionValidators.budgetAccepts(selected, type)
        : _budgetId == _retired?.id && type == _original.type;
    if (!stillValid) _budgetId = null;
  });

  void _setStart(DateTime day) => _update(() {
    _startDate = day;
    // Keeps the range valid: an end before the new start is dropped.
    if (_endDate != null && _endDate!.isBefore(day)) _endDate = null;
  });

  /// The edited rule's budget, offered even if it was deleted since.
  RetiredBudget? get _retired {
    final rule = widget.initial;
    final id = rule?.budgetId;
    if (id == null) return null;
    return (id: id, name: rule!.budgetName ?? 'Presupuesto');
  }

  int get _intervalValue => int.tryParse(_interval.text.trim()) ?? 0;

  ScheduledTransactionInput get _input => ScheduledTransactionInput(
    name: _name.text.trim(),
    type: _type,
    amountCents: Validators.amountCents(_amount.text) ?? 0,
    startDate: _startDate,
    periodicity: _periodicity,
    interval: _periodicity.recurs ? _intervalValue : 1,
    endDate: _periodicity.recurs ? _endDate : null,
    budgetId: _budgetId,
  );

  bool get _dirty => _input != _original;

  /// Editing without a new cadence keeps the next run, which bounds the end.
  bool get _sameCadence {
    final rule = widget.initial;
    return rule != null &&
        rule.periodicity == _periodicity &&
        (!_periodicity.recurs || (rule.periodInterval ?? 1) == _intervalValue);
  }

  bool get _canBeOneTime => ScheduledValidators.canBecomeOneTime(widget.initial, today: _today);

  String? get _amountError =>
      _submitted || _amount.text.trim().isNotEmpty ? ScheduledValidators.amount(_amount.text) : null;

  String? get _startError => _editing || !_submitted ? null : ScheduledValidators.startDate(_startDate, today: _today);

  String? get _intervalError => _periodicity.recurs ? ScheduledValidators.interval(_interval.text) : null;

  String? get _endError => ScheduledValidators.endDate(
    _periodicity,
    start: _startDate,
    end: _endDate,
    nextRun: _sameCadence ? widget.initial?.nextRunDate : null,
  );

  Future<void> _save() async {
    setState(() => _submitted = true);
    final fieldsValid = _formKey.currentState?.validate() ?? false;
    final startError = _editing ? null : ScheduledValidators.startDate(_startDate, today: _today);
    if (!fieldsValid ||
        ScheduledValidators.amount(_amount.text) != null ||
        startError != null ||
        _intervalError != null ||
        _endError != null) {
      return;
    }
    await context.read<ScheduledFormCubit>().save(_input);
  }

  void _onState(BuildContext context, SubmitState state) {
    switch (state.status) {
      case SubmitStatus.success:
        final next = context.read<ScheduledFormCubit>().saved?.nextRunDate;
        final name = _name.text.trim();
        showAppSnackBar(
          context,
          _editing
              ? 'Guardamos los cambios'
              : next == null
              ? 'Programamos «$name»'
              : 'Programamos «$name» para el ${Dates.date(next)}',
          kind: SnackKind.success,
        );
        setState(() => _saved = true);
        context.pop(true);
      case SubmitStatus.failure:
        final failure = state.failure!;
        if (failure.isQuota) {
          unawaited(showPlanUpsell(context, message: failure.message));
        } else if (failure.kind == FailureKind.notFound && !_budgetKeys.contains(failure.key)) {
          // The rule ended or was deleted, or the wallet is gone or no longer shared.
          showAppSnackBar(context, failure.message, kind: SnackKind.error);
          setState(() => _saved = true);
          if (failure.key == 'wallet_not_found') {
            context.go(AppRoutes.home);
          } else {
            context.pop(true);
          }
        }
      case SubmitStatus.idle || SubmitStatus.submitting:
        break;
    }
  }

  static String? _bannerError(AppFailure? failure) {
    if (failure == null || failure.isQuota) return null;
    if (failure.kind == FailureKind.notFound && !_budgetKeys.contains(failure.key)) return null;
    return _allFieldKeys.contains(failure.key) ? null : failure.message;
  }

  static String? _fieldError(AppFailure? failure, Set<String> keys) =>
      failure != null && keys.contains(failure.key) ? failure.message : null;

  /// One sentence with what will happen, read by screen readers on change.
  String get _summary {
    final input = _input;
    if (_editing) {
      final next = widget.initial!.nextRunDate;
      if (!_sameCadence) return 'Con la nueva frecuencia, la próxima ejecución se recalcula al guardar.';
      if (widget.initial!.isPaused) return 'Está pausada: no se registra nada hasta que la reanudes.';
      return next == null ? 'Sin próxima ejecución.' : 'Próxima ejecución: ${Dates.long(next)}.';
    }
    if (!input.periodicity.recurs) return 'Se registrará una sola vez, el ${Dates.long(input.startDate)}.';
    final every = input.periodicity.describe(input.interval).toLowerCase();
    final end = input.endDate;
    return 'Se registrará $every desde el ${Dates.long(input.startDate)}'
        '${end == null ? ', sin fecha de fin' : ' hasta el ${Dates.long(end)}'}.';
  }

  @override
  Widget build(BuildContext context) {
    final dirty = _dirty;
    final muted = context.palette.muted;
    final periodicities = [
      for (final p in Periodicity.values)
        if (p != Periodicity.oneTime || _canBeOneTime || _periodicity == Periodicity.oneTime) p,
    ];
    return PopScope(
      canPop: !dirty || _saved,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) unawaited(confirmDiscardChanges(context));
      },
      child: Scaffold(
        appBar: AppTopBar(title: _editing ? 'Editar programado' : 'Programar movimiento'),
        body: BlocConsumer<ScheduledFormCubit, SubmitState>(
          listenWhen: (previous, current) => previous.status != current.status,
          listener: _onState,
          builder: (context, state) {
            final failure = state.failure;
            final banner = _bannerError(failure);
            final busy = state.submitting || state.status == SubmitStatus.success;
            return Form(
              key: _formKey,
              child: FormScreenBody(
                content: [
                  if (banner != null) AppBanner(tone: BannerTone.error, message: banner),
                  AppChoiceChips<TransactionType>(
                    label: 'Tipo',
                    options: [for (final t in TransactionType.values) AppOption(t, t.label)],
                    value: _type,
                    onChanged: _setType,
                    enabled: !busy,
                  ),
                  AppTextField(
                    label: 'Descripción',
                    controller: _name,
                    hint: _type == TransactionType.expense
                        ? 'Ej.: Arriendo, Internet, Netflix'
                        : 'Ej.: Sueldo, Arriendo cobrado',
                    textCapitalization: TextCapitalization.sentences,
                    textInputAction: TextInputAction.next,
                    maxLength: ScheduledValidators.nameMax,
                    enabled: !busy,
                    errorText: _fieldError(failure, _nameKeys),
                    validator: ScheduledValidators.name,
                  ),
                  AppMoneyField(
                    label: 'Monto',
                    controller: _amount,
                    enabled: !busy,
                    helper: 'En dólares, con hasta 2 decimales.',
                    errorText: _fieldError(failure, _amountKeys) ?? _amountError,
                  ),
                  AppChoiceChips<Periodicity>(
                    key: const ValueKey('scheduled-periodicity'),
                    label: 'Frecuencia',
                    options: [for (final p in periodicities) AppOption(p, p.label)],
                    value: _periodicity,
                    onChanged: (p) => _update(() => _periodicity = p),
                    helper: _canBeOneTime
                        ? (_periodicity.recurs ? 'Se repite en el intervalo que elijas.' : 'Se registra una sola vez.')
                        : 'Ya empezó: puede cambiar de intervalo, pero no volverse única.',
                    errorText: _fieldError(failure, _periodicityKeys),
                    enabled: !busy,
                  ),
                  if (_periodicity.recurs)
                    AppTextField(
                      key: const ValueKey('scheduled-interval'),
                      label: 'Repetir cada',
                      controller: _interval,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      maxLength: 3,
                      enabled: !busy,
                      helper: 'Entre 1 y 365.',
                      suffix: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
                        child: Center(
                          widthFactor: 1,
                          child: Text(_periodicity.unit(_intervalValue), style: AppTypography.body),
                        ),
                      ),
                      errorText: _fieldError(failure, _intervalKeys) ?? (_submitted ? _intervalError : null),
                      validator: ScheduledValidators.interval,
                    ),
                  AppDateField(
                    key: const ValueKey('scheduled-start'),
                    label: _periodicity.recurs ? 'Primera ejecución' : 'Fecha',
                    value: _startDate,
                    onChanged: _setStart,
                    // Editing keeps the start (the API ignores it); the picker never opens.
                    firstDate: _editing && _startDate.isBefore(_tomorrow) ? _startDate : _tomorrow,
                    lastDate: _lastDate,
                    errorText: _fieldError(failure, _startKeys) ?? _startError,
                    enabled: !busy && !_editing,
                  ),
                  if (_editing)
                    Text(
                      'La fecha de inicio no se puede cambiar.',
                      style: AppTypography.caption.copyWith(color: muted),
                    ),
                  if (_periodicity.recurs) ...[
                    AppDateField(
                      key: const ValueKey('scheduled-end'),
                      label: 'Fecha de fin (opcional)',
                      value: _endDate,
                      placeholder: 'Sin fecha de fin',
                      onChanged: (day) => _update(() => _endDate = day),
                      firstDate: _startDate,
                      lastDate: DateTime(_lastDate.year + 5, 12, 31),
                      errorText: _fieldError(failure, _endKeys) ?? _endError,
                      enabled: !busy,
                    ),
                    if (_endDate != null)
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton.icon(
                          onPressed: busy ? null : () => _update(() => _endDate = null),
                          icon: const Icon(Icons.close_rounded),
                          label: const Text('Quitar fecha de fin'),
                          style: TextButton.styleFrom(
                            minimumSize: const Size(AppSizes.iconButton, AppSizes.iconButton),
                          ),
                        ),
                      ),
                  ],
                  BlocBuilder<BudgetListCubit, LoadState<List<Budget>>>(
                    builder: (context, budgets) => BudgetSelectorField(
                      budgets: budgets,
                      type: _type,
                      value: _budgetId,
                      retired: _type == _original.type ? _retired : null,
                      onChanged: (id) => _update(() => _budgetId = id),
                      errorText: _fieldError(failure, _budgetKeys),
                      enabled: !busy,
                    ),
                  ),
                  AppCard(
                    outlined: true,
                    child: Semantics(
                      liveRegion: true,
                      child: Row(
                        spacing: AppSpacing.md,
                        children: [
                          const Icon(Icons.event_repeat_rounded),
                          Expanded(child: Text(_summary, style: AppTypography.caption)),
                        ],
                      ),
                    ),
                  ),
                ],
                footer: [
                  AppButton(
                    label: _editing ? 'Guardar cambios' : 'Programar movimiento',
                    loading: busy,
                    onPressed: _editing && !dirty ? null : _save,
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}
