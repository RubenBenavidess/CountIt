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
import '../../../data/repositories/budget_repository.dart';
import '../../../shared/state/submit_cubit.dart';
import '../../../shared/utils/dates.dart';
import '../../../shared/widgets/app_banner.dart';
import '../../../shared/widgets/app_button.dart';
import '../../../shared/widgets/app_dialogs.dart';
import '../../../shared/widgets/app_feedback.dart';
import '../../../shared/widgets/app_fields.dart';
import '../../../shared/widgets/app_layout.dart';
import '../../account/view/reauth_sheet.dart';
import '../../plans/view/plan_upsell_sheet.dart';
import '../cubit/budget_delete_cubit.dart';
import '../cubit/budget_form_cubit.dart';
import 'widgets/budget_icon_selector.dart';
import 'widgets/budget_schedule_fields.dart';

/// What the wallet detail passes to the edit route: the listed budget and
/// whether the caller may delete it ([Budget.canBeDeletedBy]).
class BudgetEditArgs {
  const BudgetEditArgs(this.budget, {this.canDelete = false});

  final Budget budget;
  final bool canDelete;
}

/// Create (no [initial]) or edit a budget of [walletId] (HU-11/HU-13/HU-14 ·
/// COU-221..COU-226). Pops with `true` after saving or deleting.
class BudgetFormPage extends StatelessWidget {
  const BudgetFormPage({super.key, required this.walletId, this.initial, this.canDelete = false});

  final int walletId;
  final Budget? initial;

  /// Shows «Eliminar presupuesto» (edit mode only).
  final bool canDelete;

  @override
  Widget build(BuildContext context) {
    final budgets = context.read<BudgetRepository>();
    final budgetId = initial?.budgetId;
    return MultiBlocProvider(
      providers: [
        BlocProvider(
          create: (_) => BudgetFormCubit(budgets, walletId: walletId, budgetId: budgetId),
        ),
        if (budgetId != null) BlocProvider(create: (_) => BudgetDeleteCubit(budgets, budgetId: budgetId)),
      ],
      child: _BudgetFormView(walletId: walletId, initial: initial, canDelete: canDelete && budgetId != null),
    );
  }
}

class _BudgetFormView extends StatefulWidget {
  const _BudgetFormView({required this.walletId, this.initial, this.canDelete = false});

  final int walletId;
  final Budget? initial;
  final bool canDelete;

  @override
  State<_BudgetFormView> createState() => _BudgetFormViewState();
}

class _BudgetFormViewState extends State<_BudgetFormView> {
  static final _amountText = NumberFormat('0.00', 'es');

  /// Keys whose message is shown next to its field instead of the banner.
  static const _fieldKeys = {'budget_name_taken', 'budget_type_locked', 'invalid_amount', 'invalid_date_range'};

  final _formKey = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.initial?.name ?? '');
  late final _limit = TextEditingController(
    text: widget.initial == null ? '' : _amountText.format(Cents.toAmount(widget.initial!.limitCents)),
  );

  /// The user's calendar day: default start and centre of the pickers.
  late final DateTime _today = Dates.userToday(context.read<SessionCubit>().state.profile?.timezone);

  late final BudgetInput _original = widget.initial == null
      ? BudgetInput(name: '', limitCents: 0, startDate: _today)
      : BudgetInput.fromBudget(widget.initial!);
  late BudgetType _type = _original.type;
  late BudgetPeriod _period = _original.period;
  late BudgetIcon? _icon = _original.icon;
  late DateTime _start = _original.startDate;
  late DateTime? _end = _original.endDate;

  /// Shows the end-date error only after a save attempt.
  bool _submitted = false;

  /// Set right before leaving after a successful save (no «discard?» dialog).
  bool _saved = false;

  bool get _editing => widget.initial != null;

  @override
  void initState() {
    super.initState();
    for (final c in [_name, _limit]) {
      c.addListener(_changed);
    }
  }

  @override
  void dispose() {
    for (final c in [_name, _limit]) {
      c.dispose();
    }
    super.dispose();
  }

  /// Any edit hides the last server error and refreshes the «unsaved» guard.
  void _changed() {
    context.read<BudgetFormCubit>().clearFailure();
    setState(() {});
  }

  void _update(VoidCallback change) {
    setState(change);
    context.read<BudgetFormCubit>().clearFailure();
  }

  BudgetInput get _input => BudgetInput(
    name: _name.text.trim(),
    limitCents: BudgetValidators.limitCents(_limit.text) ?? 0,
    startDate: _start,
    type: _type,
    period: _period,
    endDate: _period.renews ? null : _end,
    icon: _icon,
  );

  bool get _dirty {
    final input = _input;
    final original = _original;
    return input.name != original.name.trim() ||
        input.limitCents != original.limitCents ||
        input.type != original.type ||
        input.period != original.period ||
        input.startDate != original.startDate ||
        input.endDate != (original.period.renews ? null : original.endDate) ||
        input.icon != original.icon;
  }

  String? get _endDateError => _submitted ? BudgetValidators.endDate(_period, _start, _end) : null;

  void _pickStart(DateTime day) => _update(() {
    _start = day;
    // Keeps the range valid: an end before the new start is dropped.
    if (_end != null && _end!.isBefore(day)) _end = null;
  });

  Future<void> _save() async {
    setState(() => _submitted = true);
    final fieldsValid = _formKey.currentState?.validate() ?? false;
    if (!fieldsValid ||
        BudgetValidators.limit(_limit.text) != null ||
        BudgetValidators.endDate(_period, _start, _end) != null) {
      return;
    }
    await context.read<BudgetFormCubit>().save(_input);
  }

  void _onState(BuildContext context, SubmitState state) {
    switch (state.status) {
      case SubmitStatus.success:
        showAppSnackBar(
          context,
          _editing ? 'Guardamos los cambios' : 'Creamos el presupuesto «${_name.text.trim()}»',
          kind: SnackKind.success,
        );
        setState(() => _saved = true);
        context.pop(true);
      case SubmitStatus.failure:
        final failure = state.failure!;
        if (failure.isQuota) {
          unawaited(showPlanUpsell(context, message: failure.message));
        } else if (failure.kind == FailureKind.notFound) {
          // The budget was deleted, or the wallet is gone or no longer shared.
          showAppSnackBar(context, failure.message, kind: SnackKind.error);
          setState(() => _saved = true);
          if (failure.key == 'wallet_not_found') {
            context.go(AppRoutes.home);
          } else {
            // Back to the wallet, whose list reloads without the missing budget.
            context.pop(true);
          }
        }
      case SubmitStatus.idle || SubmitStatus.submitting:
        break;
    }
  }

  Future<void> _delete() async {
    final cubit = context.read<BudgetDeleteCubit>();
    final name = widget.initial!.name;
    final confirmed = await showConfirmDialog(
      context,
      title: '¿Eliminar «$name»?',
      message:
          'Dejará de aparecer en la billetera. Los movimientos ya registrados se conservan '
          'y los programados quedan sin presupuesto.',
      confirmLabel: 'Eliminar',
      destructive: true,
    );
    if (!confirmed || !mounted) return;
    await cubit.delete(
      onReauth: reauthPrompt(context, action: 'eliminar «$name»', confirmLabel: 'Eliminar presupuesto'),
    );
  }

  void _onDeleteState(BuildContext context, BudgetDeleteState state) {
    switch (state.status) {
      case BudgetDeleteStatus.deleted:
        showAppSnackBar(context, 'Eliminamos «${widget.initial!.name}»', kind: SnackKind.success);
        setState(() => _saved = true);
        context.pop(true);
      case BudgetDeleteStatus.failure:
        showFailureSnackBar(context, state.failure!);
      case BudgetDeleteStatus.idle || BudgetDeleteStatus.deleting:
        break;
    }
  }

  /// Errors shown in the banner: everything not handled by a field or a navigation.
  static String? _bannerError(AppFailure? failure) {
    if (failure == null || failure.kind == FailureKind.notFound || failure.isQuota) return null;
    return _fieldKeys.contains(failure.key) ? null : failure.message;
  }

  static String? _fieldError(AppFailure? failure, String key) => failure?.key == key ? failure!.message : null;

  @override
  Widget build(BuildContext context) {
    final dirty = _dirty;
    return PopScope(
      canPop: !dirty || _saved,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) unawaited(confirmDiscardChanges(context));
      },
      child: Scaffold(
        appBar: AppTopBar(title: _editing ? 'Editar presupuesto' : 'Nuevo presupuesto'),
        body: BlocConsumer<BudgetFormCubit, SubmitState>(
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
                  AppChoiceChips<BudgetType>(
                    label: 'Tipo',
                    options: [for (final t in BudgetType.values) AppOption(t, t.label)],
                    value: _type,
                    onChanged: (type) => _update(() => _type = type),
                    helper: _type == BudgetType.expense
                        ? 'Un tope para lo que gastas en esta categoría.'
                        : 'Una meta para lo que recibes en esta categoría.',
                    errorText: _fieldError(failure, 'budget_type_locked'),
                    enabled: !busy,
                  ),
                  AppTextField(
                    label: 'Nombre',
                    controller: _name,
                    hint: 'Ej.: Comida, Transporte, Sueldo',
                    textCapitalization: TextCapitalization.sentences,
                    textInputAction: TextInputAction.next,
                    maxLength: BudgetValidators.nameMax,
                    enabled: !busy,
                    errorText: _fieldError(failure, 'budget_name_taken'),
                    validator: BudgetValidators.name,
                  ),
                  AppMoneyField(
                    label: _type == BudgetType.expense ? 'Límite' : 'Meta',
                    controller: _limit,
                    enabled: !busy,
                    helper: 'Monto por periodo, en dólares.',
                    errorText: _fieldError(failure, 'invalid_amount') ?? _limitError,
                  ),
                  BudgetScheduleFields(
                    period: _period,
                    startDate: _start,
                    endDate: _end,
                    onPeriodChanged: (period) => _update(() => _period = period),
                    onStartChanged: _pickStart,
                    onEndChanged: (day) => _update(() => _end = day),
                    firstDate: DateTime(_today.year - 5),
                    lastDate: DateTime(_today.year + 5, 12, 31),
                    endDateError: _fieldError(failure, 'invalid_date_range') ?? _endDateError,
                    enabled: !busy,
                  ),
                  BudgetIconSelector(value: _icon, onChanged: (icon) => _update(() => _icon = icon), enabled: !busy),
                ],
                footer: [
                  AppButton(
                    label: _editing ? 'Guardar cambios' : 'Crear presupuesto',
                    loading: busy,
                    onPressed: _editing && !dirty ? null : _save,
                  ),
                  if (widget.canDelete)
                    BlocConsumer<BudgetDeleteCubit, BudgetDeleteState>(
                      listenWhen: (previous, current) => previous.status != current.status,
                      listener: _onDeleteState,
                      builder: (context, delete) => AppButton(
                        label: 'Eliminar presupuesto',
                        icon: Icons.delete_outline_rounded,
                        variant: AppButtonVariant.danger,
                        loading: delete.deleting,
                        onPressed: busy ? null : _delete,
                      ),
                    ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  /// The money field has no validator hook: its error shows once touched or
  /// after a save attempt.
  String? get _limitError => _submitted || _limit.text.trim().isNotEmpty ? BudgetValidators.limit(_limit.text) : null;
}
