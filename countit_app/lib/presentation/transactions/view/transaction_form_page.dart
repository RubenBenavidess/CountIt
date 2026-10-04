import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../app/errors/app_failure.dart';
import '../../../app/router/app_router.dart';
import '../../../app/session/session_cubit.dart';
import '../../../data/dtos/budget.dart';
import '../../../data/dtos/json_parsing.dart';
import '../../../data/dtos/transaction.dart';
import '../../../data/repositories/budget_repository.dart';
import '../../../data/repositories/transaction_repository.dart';
import '../../../shared/state/load_state.dart';
import '../../../shared/state/submit_cubit.dart';
import '../../../shared/utils/dates.dart';
import '../../../shared/utils/validators.dart';
import '../../../shared/widgets/app_banner.dart';
import '../../../shared/widgets/app_button.dart';
import '../../../shared/widgets/app_dialogs.dart';
import '../../../shared/widgets/app_feedback.dart';
import '../../../shared/widgets/app_fields.dart';
import '../../../shared/widgets/app_layout.dart';
import '../../budgets/cubit/budget_list_cubit.dart';
import '../../budgets/view/widgets/budget_selector_field.dart';
import '../../plans/view/plan_upsell_sheet.dart';
import '../cubit/transaction_form_cubit.dart';

/// Register (no [initial]) or edit a transaction of [walletId] (HU-15/HU-18
/// · COU-236..COU-239). Pops with `true` after saving, so the wallet reloads
/// its balance, budgets and movements.
class TransactionFormPage extends StatelessWidget {
  const TransactionFormPage({super.key, required this.walletId, this.initial});

  final int walletId;
  final Transaction? initial;

  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      providers: [
        BlocProvider(
          create: (context) => TransactionFormCubit(
            context.read<TransactionRepository>(),
            walletId: walletId,
            transactionId: initial?.transactionId,
          ),
        ),
        // The selector's options: the wallet's active budgets.
        BlocProvider(
          create: (context) => BudgetListCubit(context.read<BudgetRepository>(), walletId: walletId)..load(),
        ),
      ],
      child: _TransactionFormView(initial: initial),
    );
  }
}

class _TransactionFormView extends StatefulWidget {
  const _TransactionFormView({this.initial});

  final Transaction? initial;

  @override
  State<_TransactionFormView> createState() => _TransactionFormViewState();
}

class _TransactionFormViewState extends State<_TransactionFormView> {
  static final _amountText = NumberFormat('0.00', 'es');

  /// Backend keys shown next to a field instead of the banner.
  static const _amountKeys = {'invalid_amount'};
  static const _dateKeys = {'future_date'};
  static const _budgetKeys = {'budget_type_mismatch', 'budget_not_active', 'budget_wallet_mismatch'};
  static const _nameKeys = {'max_length'};

  final _formKey = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.initial?.name ?? '');
  late final _amount = TextEditingController(
    text: widget.initial == null ? '' : _amountText.format(Cents.toAmount(widget.initial!.amountCents)),
  );

  /// The user's calendar day: default date and the latest one allowed.
  late final DateTime _today = Dates.userToday(context.read<SessionCubit>().state.profile?.timezone);

  late final TransactionInput _original = widget.initial == null
      ? TransactionInput(name: '', type: TransactionType.expense, amountCents: 0, date: _today)
      : TransactionInput.fromTransaction(widget.initial!);
  late TransactionType _type = _original.type;
  late DateTime _date = _original.date;
  late int? _budgetId = _original.budgetId;

  /// Shows the amount and date errors only after a save attempt (or typing).
  bool _submitted = false;

  /// Set right before leaving after a successful save (no «discard?» dialog).
  bool _saved = false;

  bool get _editing => widget.initial != null;

  @override
  void initState() {
    super.initState();
    for (final c in [_name, _amount]) {
      c.addListener(_changed);
    }
  }

  @override
  void dispose() {
    for (final c in [_name, _amount]) {
      c.dispose();
    }
    super.dispose();
  }

  /// Any edit hides the last server error and refreshes the «unsaved» guard.
  void _changed() {
    context.read<TransactionFormCubit>().clearFailure();
    setState(() {});
  }

  void _update(VoidCallback change) {
    setState(change);
    context.read<TransactionFormCubit>().clearFailure();
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

  /// The edited transaction's budget, offered even if it was deleted since.
  RetiredBudget? get _retired {
    final initial = widget.initial;
    final id = initial?.budgetId;
    if (id == null) return null;
    return (id: id, name: initial!.budgetName ?? 'Presupuesto');
  }

  TransactionInput get _input => TransactionInput(
    name: _name.text.trim(),
    type: _type,
    amountCents: Validators.amountCents(_amount.text) ?? 0,
    date: _date,
    budgetId: _budgetId,
  );

  bool get _dirty => _input != _original;

  String? get _amountError =>
      _submitted || _amount.text.trim().isNotEmpty ? TransactionValidators.amount(_amount.text) : null;

  String? get _dateError => TransactionValidators.date(_date, today: _today);

  Future<void> _save() async {
    setState(() => _submitted = true);
    final fieldsValid = _formKey.currentState?.validate() ?? false;
    if (!fieldsValid || TransactionValidators.amount(_amount.text) != null || _dateError != null) return;
    await context.read<TransactionFormCubit>().save(_input);
  }

  void _onState(BuildContext context, SubmitState state) {
    switch (state.status) {
      case SubmitStatus.success:
        showAppSnackBar(
          context,
          _editing ? 'Guardamos los cambios' : 'Registramos «${_name.text.trim()}»',
          kind: SnackKind.success,
        );
        setState(() => _saved = true);
        context.pop(true);
      case SubmitStatus.failure:
        final failure = state.failure!;
        if (failure.isQuota) {
          unawaited(showPlanUpsell(context, message: failure.message));
        } else if (failure.kind == FailureKind.notFound) {
          // The transaction was deleted, or the wallet is gone or no longer shared.
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

  /// Errors shown in the banner: everything not handled by a field or a navigation.
  static String? _bannerError(AppFailure? failure) {
    if (failure == null || failure.kind == FailureKind.notFound || failure.isQuota) return null;
    final key = failure.key;
    final byField =
        _amountKeys.contains(key) || _dateKeys.contains(key) || _budgetKeys.contains(key) || _nameKeys.contains(key);
    return byField ? null : failure.message;
  }

  static String? _fieldError(AppFailure? failure, Set<String> keys) =>
      failure != null && keys.contains(failure.key) ? failure.message : null;

  @override
  Widget build(BuildContext context) {
    final dirty = _dirty;
    return PopScope(
      canPop: !dirty || _saved,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) unawaited(confirmDiscardChanges(context));
      },
      child: Scaffold(
        appBar: AppTopBar(title: _editing ? 'Editar movimiento' : 'Nuevo movimiento'),
        body: BlocConsumer<TransactionFormCubit, SubmitState>(
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
                    hint: _type == TransactionType.expense ? 'Ej.: Almuerzo, Taxi, Farmacia' : 'Ej.: Sueldo, Venta',
                    textCapitalization: TextCapitalization.sentences,
                    textInputAction: TextInputAction.next,
                    maxLength: TransactionValidators.nameMax,
                    enabled: !busy,
                    errorText: _fieldError(failure, _nameKeys),
                    validator: TransactionValidators.name,
                  ),
                  AppMoneyField(
                    label: 'Monto',
                    controller: _amount,
                    enabled: !busy,
                    helper: 'En dólares, con hasta 2 decimales.',
                    errorText: _fieldError(failure, _amountKeys) ?? _amountError,
                  ),
                  AppDateField(
                    label: 'Fecha',
                    value: _date,
                    onChanged: (day) => _update(() => _date = day),
                    firstDate: DateTime(_today.year - 10),
                    lastDate: _today,
                    errorText: _fieldError(failure, _dateKeys) ?? _dateError,
                    enabled: !busy,
                  ),
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
                ],
                footer: [
                  AppButton(
                    label: _editing ? 'Guardar cambios' : 'Registrar movimiento',
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
