import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../app/errors/app_failure.dart';
import '../../../app/theme/app_theme.dart';
import '../../../app/theme/tokens.dart';
import '../../../data/remote/api_client.dart';
import '../../../data/repositories/auth_repository.dart';
import '../../../shared/state/submit_cubit.dart';
import '../../../shared/utils/validators.dart';
import '../../../shared/widgets/app_banner.dart';
import '../../../shared/widgets/app_button.dart';
import '../../../shared/widgets/app_card.dart';
import '../../../shared/widgets/app_fields.dart';
import '../../../shared/widgets/cooldown_button.dart';
import '../../../shared/widgets/secure_screen.dart';
import '../cubit/account_cubits.dart';

/// «Confirma que eres tú» (HU-06, design ConfirmarIdentidad · COU-86, COU-147).
///
/// Returns true when the password was confirmed: the caller retries its
/// destructive action. The server keeps the 5-minute window, so within it the
/// API never answers `reauth_required` and this sheet is not shown again.
Future<bool> confirmIdentity(
  BuildContext context, {
  required String action,
  required String confirmLabel,
  String? consequences,
}) async {
  final confirmed = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => BlocProvider(
      create: (_) => ReauthCubit(context.read<AuthRepository>()),
      child: SecureScreen(
        child: _ReauthSheet(action: action, confirmLabel: confirmLabel, consequences: consequences),
      ),
    ),
  );
  return confirmed ?? false;
}

/// Adapter for [ApiClient.run]'s `onReauth`: destructive calls pass
/// `onReauth: reauthPrompt(context, action: 'eliminar «Hogar»', …)`.
ReauthPrompt reauthPrompt(
  BuildContext context, {
  required String action,
  required String confirmLabel,
  String? consequences,
}) =>
    () => confirmIdentity(context, action: action, confirmLabel: confirmLabel, consequences: consequences);

class _ReauthSheet extends StatefulWidget {
  const _ReauthSheet({required this.action, required this.confirmLabel, this.consequences});

  final String action;
  final String confirmLabel;
  final String? consequences;

  @override
  State<_ReauthSheet> createState() => _ReauthSheetState();
}

class _ReauthSheetState extends State<_ReauthSheet> {
  final _formKey = GlobalKey<FormState>();
  final _password = TextEditingController();

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final cubit = context.read<ReauthCubit>();
    // The keyboard's «done» bypasses the disabled button.
    if (cubit.blocked) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final navigator = Navigator.of(context);
    if (await cubit.confirm(_password.text)) navigator.pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final expense = context.palette.expense;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        AppSpacing.screen,
        AppSpacing.sm,
        AppSpacing.screen,
        MediaQuery.viewInsetsOf(context).bottom + 28,
      ),
      child: BlocConsumer<ReauthCubit, SubmitState>(
        listenWhen: (previous, current) => current.status == SubmitStatus.failure,
        listener: (context, state) => _password.clear(),
        builder: (context, state) {
          final failure = state.failure;
          final wrongPassword = failure?.kind == FailureKind.invalidCredentials;
          return Form(
            key: _formKey,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                spacing: AppSpacing.lg,
                children: [
                  Row(
                    spacing: 14,
                    children: [
                      IconTile(Icons.lock_outline_rounded, size: 48, color: expense),
                      Expanded(
                        child: Semantics(
                          header: true,
                          child: Text('Confirma que eres tú', style: AppTypography.h2.copyWith(fontSize: 19)),
                        ),
                      ),
                    ],
                  ),
                  Text(
                    'Para ${widget.action} escribe tu contraseña. Durante 5 minutos no te la volveremos a pedir.',
                    style: AppTypography.body.copyWith(color: AppColors.muted),
                  ),
                  if (widget.consequences != null) AppBanner(tone: BannerTone.error, message: widget.consequences!),
                  if (failure != null && !wrongPassword) AppBanner(tone: BannerTone.error, message: failure.message),
                  AppPasswordField(
                    controller: _password,
                    helper: '3 intentos cada 2 minutos.',
                    errorText: wrongPassword ? failure!.message : null,
                    validator: Validators.existingPassword,
                    enabled: !state.submitting,
                    textInputAction: TextInputAction.done,
                    onChanged: (_) => context.read<ReauthCubit>().passwordEdited(),
                    onSubmitted: (_) => _submit(),
                  ),
                  CooldownButton(
                    label: widget.confirmLabel,
                    variant: AppButtonVariant.dangerSolid,
                    loading: state.submitting || state.status == SubmitStatus.success,
                    until: state.blockedUntil,
                    onPressed: failure?.kind == FailureKind.locked ? null : _submit,
                  ),
                  AppButton(
                    label: 'Cancelar',
                    variant: AppButtonVariant.ghost,
                    onPressed: () => Navigator.of(context).pop(false),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
