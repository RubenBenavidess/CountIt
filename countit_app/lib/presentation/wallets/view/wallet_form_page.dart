import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../app/errors/app_failure.dart';
import '../../../app/router/app_router.dart';
import '../../../app/theme/app_theme.dart';
import '../../../app/theme/tokens.dart';
import '../../../data/dtos/bank.dart';
import '../../../data/dtos/json_parsing.dart';
import '../../../data/dtos/wallet.dart';
import '../../../data/repositories/wallet_repository.dart';
import '../../../shared/state/submit_cubit.dart';
import '../../../shared/utils/money.dart';
import '../../../shared/utils/validators.dart';
import '../../../shared/widgets/app_banner.dart';
import '../../../shared/widgets/app_button.dart';
import '../../../shared/widgets/app_dialogs.dart';
import '../../../shared/widgets/app_feedback.dart';
import '../../../shared/widgets/app_fields.dart';
import '../../../shared/widgets/app_layout.dart';
import '../../plans/view/plan_upsell_sheet.dart';
import '../cubit/wallet_form_cubit.dart';
import 'bank_picker_sheet.dart';
import 'widgets/wallet_card.dart';
import 'widgets/wallet_colors.dart';
import 'widgets/wallet_type_selector.dart';

/// Create (no [initial]) or edit a wallet (HU-07/HU-09 · COU-192..COU-194).
/// Pops with `true` after saving.
class WalletFormPage extends StatelessWidget {
  const WalletFormPage({super.key, this.initial});

  final Wallet? initial;

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) => WalletFormCubit(context.read<WalletRepository>(), walletId: initial?.walletId),
      child: _WalletFormView(initial: initial),
    );
  }
}

class _WalletFormView extends StatefulWidget {
  const _WalletFormView({this.initial});

  final Wallet? initial;

  @override
  State<_WalletFormView> createState() => _WalletFormViewState();
}

class _WalletFormViewState extends State<_WalletFormView> {
  static const nameMax = 50;
  static const descriptionMax = 255;
  final _formKey = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.initial?.name ?? '');
  late final _description = TextEditingController(text: widget.initial?.description ?? '');
  late final _balance = TextEditingController(text: _initialBalanceText());
  late WalletType? _type = widget.initial?.type;
  late Bank? _bank = _initialBank();

  /// What the form held when it opened: «sin guardar» compares against it.
  late final WalletInput _original = widget.initial == null
      ? const WalletInput(name: '')
      : WalletInput.fromWallet(widget.initial!);

  bool get _editing => widget.initial != null;

  /// Set right before leaving after a successful save (no «discard?» dialog).
  bool _saved = false;

  String _initialBalanceText() {
    final cents = widget.initial?.initialBalanceCents ?? 0;
    return cents == 0 ? '' : Money.input(Cents.toAmount(cents));
  }

  Bank? _initialBank() {
    final wallet = widget.initial;
    if (wallet?.bankId == null) return null;
    return Bank(bankId: wallet!.bankId!, name: wallet.bankName ?? '', color: wallet.bankColor);
  }

  @override
  void initState() {
    super.initState();
    for (final c in [_name, _description, _balance]) {
      c.addListener(_changed);
    }
  }

  @override
  void dispose() {
    for (final c in [_name, _description, _balance]) {
      c.dispose();
    }
    super.dispose();
  }

  /// Redraws the preview and the «unsaved changes» guard.
  void _changed() {
    context.read<WalletFormCubit>().clearFailure();
    setState(() {});
  }

  /// Null while the amount is not valid (the field shows why).
  int? get _balanceCents {
    final text = _balance.text.trim();
    if (text.isEmpty) return 0;
    final amount = Money.parse(text);
    return amount == null ? null : Cents.fromAmount(amount);
  }

  WalletInput get _input => WalletInput(
    name: _name.text.trim(),
    type: _type,
    bankId: _bank?.bankId,
    description: _description.text.trim().isEmpty ? null : _description.text.trim(),
    initialBalanceCents: _balanceCents ?? _original.initialBalanceCents,
  );

  bool get _dirty {
    final input = _input;
    return input.name != _original.name.trim() ||
        input.type != _original.type ||
        input.bankId != _original.bankId ||
        (input.description ?? '') != (_original.description?.trim() ?? '') ||
        _balanceCents != _original.initialBalanceCents;
  }

  /// The card as it will look: balance and projection follow the new opening balance.
  Wallet get _preview {
    final base = widget.initial;
    final input = _input;
    final delta = input.initialBalanceCents - (base?.initialBalanceCents ?? 0);
    return Wallet(
      walletId: base?.walletId ?? 0,
      name: input.name.isEmpty ? (base?.name ?? 'Nueva billetera') : input.name,
      isOwner: true,
      ownerName: base?.ownerName,
      type: input.type,
      bankId: _bank?.bankId,
      bankName: _bank?.name,
      bankColor: _bank?.color,
      memberCount: base?.memberCount ?? 0,
      initialBalanceCents: input.initialBalanceCents,
      balanceCents: (base?.balanceCents ?? 0) + delta,
      monthIncomeCents: base?.monthIncomeCents ?? 0,
      monthExpensesCents: base?.monthExpensesCents ?? 0,
      projectedBalanceCents: base?.projectedBalanceCents == null ? null : base!.projectedBalanceCents! + delta,
    );
  }

  Future<void> _pickBank() async {
    final selection = await pickBank(context, selectedId: _bank?.bankId);
    if (selection == null || !mounted) return;
    setState(() => _bank = selection.bank);
    context.read<WalletFormCubit>().clearFailure();
  }

  void _pickType(WalletType type) {
    setState(() => _type = type);
    context.read<WalletFormCubit>().clearFailure();
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    await context.read<WalletFormCubit>().save(_input);
  }

  void _onState(BuildContext context, SubmitState state) {
    switch (state.status) {
      case SubmitStatus.success:
        showAppSnackBar(
          context,
          _editing ? 'Guardamos los cambios' : 'Creamos tu billetera «${_name.text.trim()}»',
          kind: SnackKind.success,
        );
        setState(() => _saved = true);
        context.pop(true);
      case SubmitStatus.failure:
        final failure = state.failure!;
        if (failure.isQuota) {
          unawaited(showPlanUpsell(context, message: failure.message));
        } else if (failure.kind == FailureKind.notFound) {
          // Deleted (or no longer ours) while editing: nothing left to edit.
          showAppSnackBar(context, 'Billetera no encontrada', kind: SnackKind.error);
          context.go(AppRoutes.home);
        }
      case SubmitStatus.idle || SubmitStatus.submitting:
        break;
    }
  }

  /// Errors shown in the banner: everything except the ones handled elsewhere.
  static String? _bannerError(AppFailure? failure) {
    if (failure == null) return null;
    if (failure.key == 'wallet_name_taken' || failure.kind == FailureKind.notFound) return null;
    if (failure.isQuota) return null;
    return failure.message;
  }

  @override
  Widget build(BuildContext context) {
    final dirty = _dirty;
    return DiscardChangesGuard(
      dirty: dirty && !_saved,
      child: Scaffold(
        appBar: AppTopBar(title: _editing ? 'Editar billetera' : 'Nueva billetera'),
        body: BlocConsumer<WalletFormCubit, SubmitState>(
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
                  ExcludeSemantics(child: WalletCard(wallet: _preview)),
                  if (banner != null) AppBanner(tone: BannerTone.error, message: banner),
                  AppTextField(
                    label: 'Nombre',
                    controller: _name,
                    hint: 'Ej.: Ahorros, Efectivo, Tarjeta',
                    textCapitalization: TextCapitalization.sentences,
                    textInputAction: TextInputAction.next,
                    maxLength: nameMax,
                    enabled: !busy,
                    errorText: failure?.key == 'wallet_name_taken' ? failure!.message : null,
                    validator: (value) =>
                        Validators.required(value) ??
                        ((value ?? '').trim().length > nameMax
                            ? 'Máximo de caracteres alcanzado ($nameMax) en el nombre'
                            : null),
                  ),
                  WalletTypeSelector(value: _type, onChanged: _pickType, enabled: !busy),
                  _BankField(bank: _bank, onTap: busy ? null : _pickBank),
                  AppMoneyField(
                    label: 'Saldo inicial',
                    controller: _balance,
                    enabled: !busy,
                    helper: _editing
                        ? 'Cambiarlo ajusta el saldo actual en la misma cantidad.'
                        : 'Lo que tienes hoy en esta billetera. Puede ser 0.',
                    errorText: _balance.text.trim().isNotEmpty && _balanceCents == null
                        ? 'Ingresa un monto válido, con hasta 2 decimales'
                        : null,
                  ),
                  AppTextField(
                    label: 'Descripción (opcional)',
                    controller: _description,
                    hint: 'Para qué usas esta billetera',
                    textCapitalization: TextCapitalization.sentences,
                    maxLength: descriptionMax,
                    enabled: !busy,
                  ),
                ],
                footer: [
                  AppButton(
                    label: _editing ? 'Guardar cambios' : 'Crear billetera',
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

/// Read-only field that opens the bank sheet, with the bank's colour swatch.
class _BankField extends StatelessWidget {
  const _BankField({required this.bank, required this.onTap});

  final Bank? bank;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final name = bank?.name ?? 'Sin banco';
    final color = bankAccentOf(bank?.color);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: AppSpacing.sm,
      children: [
        Text('Banco', style: AppTypography.label.copyWith(color: scheme.onSurface)),
        Semantics(
          button: true,
          label: 'Banco: $name',
          excludeSemantics: true,
          child: InkWell(
            key: const ValueKey('wallet-bank-field'),
            borderRadius: BorderRadius.circular(AppRadii.lg),
            onTap: onTap,
            child: InputDecorator(
              decoration: InputDecoration(
                enabled: onTap != null,
                prefixIcon: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Container(
                    width: 22,
                    height: 22,
                    decoration: BoxDecoration(
                      color: color,
                      shape: BoxShape.circle,
                      border: Border.all(color: context.palette.line, width: AppSizes.borderWidth),
                    ),
                  ),
                ),
                suffixIcon: const Icon(Icons.expand_more_rounded),
              ),
              child: Text(
                name,
                style: AppTypography.body.copyWith(fontSize: 16, color: scheme.onSurface),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
