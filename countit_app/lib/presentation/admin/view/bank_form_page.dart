import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../app/theme/app_theme.dart';
import '../../../app/theme/tokens.dart';
import '../../../data/dtos/bank.dart';
import '../../../data/dtos/json_parsing.dart';
import '../../../data/dtos/wallet.dart';
import '../../../data/repositories/admin_repository.dart';
import '../../../shared/state/submit_cubit.dart';
import '../../../shared/widgets/app_banner.dart';
import '../../../shared/widgets/app_button.dart';
import '../../../shared/widgets/app_dialogs.dart';
import '../../../shared/widgets/app_feedback.dart';
import '../../../shared/widgets/app_fields.dart';
import '../../../shared/widgets/app_layout.dart';
import '../../wallets/view/widgets/wallet_card.dart';
import '../../wallets/view/widgets/wallet_colors.dart';
import '../cubit/bank_form_cubit.dart';
import 'widgets/bank_color_picker.dart';
import 'widgets/role_guard.dart';

/// Create (no [initial]) or edit a bank (HU-27 · COU-206): name, country and
/// colour with a live wallet card preview. Pops with the saved [Bank].
class BankFormPage extends StatelessWidget {
  const BankFormPage({super.key, this.initial});

  final Bank? initial;

  @override
  Widget build(BuildContext context) => RoleGuard(
    allows: RoleGuard.admin,
    builder: (context) => BlocProvider(
      create: (context) => BankFormCubit(context.read<AdminRepository>(), bankId: initial?.bankId),
      child: _BankFormView(initial: initial),
    ),
  );
}

class _BankFormView extends StatefulWidget {
  const _BankFormView({this.initial});

  final Bank? initial;

  @override
  State<_BankFormView> createState() => _BankFormViewState();
}

class _BankFormViewState extends State<_BankFormView> {
  final _formKey = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.initial?.name ?? '');
  late final _country = TextEditingController(text: widget.initial?.countryCode ?? 'EC');
  late final _hex = TextEditingController(text: toHexColor(widget.initial?.color) ?? '');
  late int? _color = widget.initial?.color;
  bool _saved = false;

  bool get _editing => widget.initial != null;

  bool get _dirty =>
      _name.text.trim() != (widget.initial?.name ?? '') ||
      _country.text.trim() != (widget.initial?.countryCode ?? 'EC') ||
      _color != widget.initial?.color;

  @override
  void initState() {
    super.initState();
    for (final controller in [_name, _country]) {
      controller.addListener(_changed);
    }
  }

  void _changed() {
    setState(() {});
    context.read<BankFormCubit>().clearFailure();
  }

  @override
  void dispose() {
    _name.dispose();
    _country.dispose();
    _hex.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    await context.read<BankFormCubit>().save(
      BankInput(name: _name.text.trim(), countryCode: _country.text.trim(), color: _color),
    );
  }

  void _onState(BuildContext context, SubmitState state) {
    if (state.status != SubmitStatus.success) return;
    final bank = context.read<BankFormCubit>().saved!;
    showAppSnackBar(
      context,
      _editing ? 'Guardamos «${bank.name}»' : 'Creamos el banco «${bank.name}»',
      kind: SnackKind.success,
    );
    setState(() => _saved = true);
    Navigator.of(context).pop(bank);
  }

  Wallet get _preview => Wallet(
    walletId: 0,
    name: 'Billetera de ejemplo',
    isOwner: true,
    type: WalletType.savings,
    bankName: _name.text.trim().isEmpty ? 'Nuevo banco' : _name.text.trim(),
    bankColor: _color,
  );

  @override
  Widget build(BuildContext context) {
    final muted = context.palette.muted;
    final adjusted = _color != null && WalletColors.readable(Color(_color!)) != Color(_color!);
    return DiscardChangesGuard(
      dirty: _dirty && !_saved,
      child: Scaffold(
        appBar: AppTopBar(title: _editing ? 'Editar banco' : 'Nuevo banco'),
        body: BlocConsumer<BankFormCubit, SubmitState>(
          listenWhen: (previous, current) => previous.status != current.status,
          listener: _onState,
          builder: (context, state) {
            final failure = state.failure;
            final busy = state.submitting || state.status == SubmitStatus.success;
            final nameTaken = failure?.key == 'bank_name_taken';
            final colorError = failure?.key == 'invalid_color' ? failure!.message : null;
            final countryError = failure?.key == 'invalid_country_code' ? failure!.message : null;
            final banner = failure != null && !nameTaken && colorError == null && countryError == null
                ? failure.message
                : null;
            return Form(
              key: _formKey,
              child: FormScreenBody(
                content: [
                  Semantics(
                    label: 'Vista previa de una billetera de este banco',
                    child: ExcludeSemantics(child: WalletCard(wallet: _preview)),
                  ),
                  if (adjusted)
                    Text(
                      'Para que el texto se lea bien, las tarjetas usan un tono más oscuro de este color.',
                      style: AppTypography.caption.copyWith(color: muted),
                    ),
                  if (banner != null) AppBanner(tone: BannerTone.error, message: banner),
                  AppTextField(
                    key: const ValueKey('bank-name'),
                    label: 'Nombre',
                    controller: _name,
                    hint: 'Ej.: Banco Pichincha',
                    textCapitalization: TextCapitalization.words,
                    textInputAction: TextInputAction.next,
                    maxLength: BankFormCubit.nameMax,
                    enabled: !busy,
                    errorText: nameTaken ? failure!.message : null,
                    validator: BankFormCubit.validateName,
                  ),
                  AppTextField(
                    key: const ValueKey('bank-country'),
                    label: 'País',
                    controller: _country,
                    hint: 'EC',
                    helper: 'Código de 2 letras (ISO 3166-1).',
                    textCapitalization: TextCapitalization.characters,
                    maxLength: 2,
                    inputFormatters: [
                      TextInputFormatter.withFunction((previous, next) => next.copyWith(text: next.text.toUpperCase())),
                    ],
                    enabled: !busy,
                    errorText: countryError,
                    validator: BankFormCubit.validateCountry,
                  ),
                  Text('COLOR', style: AppTypography.overline.copyWith(color: muted)),
                  BankColorPicker(
                    color: _color,
                    hexController: _hex,
                    errorText: colorError,
                    onChanged: (color) {
                      setState(() => _color = color);
                      context.read<BankFormCubit>().clearFailure();
                    },
                  ),
                  Text(
                    'Sin color, las billeteras de este banco usan el color por defecto.',
                    style: AppTypography.caption.copyWith(color: muted),
                  ),
                ],
                footer: [
                  AppButton(
                    key: const ValueKey('bank-save'),
                    label: _editing ? 'Guardar cambios' : 'Crear banco',
                    loading: busy,
                    onPressed: busy ? null : () => unawaited(_save()),
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
