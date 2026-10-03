import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../app/session/session_cubit.dart';
import '../../../data/repositories/auth_repository.dart';
import '../../../shared/state/submit_cubit.dart';
import '../../../shared/utils/validators.dart';
import '../../../shared/widgets/app_banner.dart';
import '../../../shared/widgets/app_button.dart';
import '../../../shared/widgets/app_fields.dart';
import '../../../shared/widgets/app_layout.dart';
import '../../../shared/widgets/password_checklist.dart';
import '../../../shared/widgets/secure_screen.dart';
import '../cubit/password_cubits.dart';
import 'auth_header.dart';

/// New password with the recovery session (HU-03, design Restablecer ·
/// COU-136, COU-141). Only reachable in [SessionStatus.passwordRecovery].
class ResetPasswordPage extends StatelessWidget {
  const ResetPasswordPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) => ResetPasswordCubit(context.read<AuthRepository>()),
      child: const SecureScreen(child: _ResetPasswordView()),
    );
  }
}

class _ResetPasswordView extends StatefulWidget {
  const _ResetPasswordView();

  @override
  State<_ResetPasswordView> createState() => _ResetPasswordViewState();
}

class _ResetPasswordViewState extends State<_ResetPasswordView> {
  final _formKey = GlobalKey<FormState>();
  final _password = TextEditingController();
  final _confirm = TextEditingController();

  @override
  void dispose() {
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final session = context.read<SessionCubit>();
    if (await context.read<ResetPasswordCubit>().save(_password.text)) {
      // «Guardar y entrar»: the recovery session becomes a normal one.
      await session.recoveryCompleted();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const AppTopBar(showWordmark: true, showBack: false),
      body: BlocBuilder<ResetPasswordCubit, SubmitState>(
        builder: (context, state) {
          final busy = state.submitting || state.status == SubmitStatus.success;
          return Form(
            key: _formKey,
            child: AutofillGroup(
              child: FormScreenBody(
                gap: 18,
                content: [
                  const AuthHeader(
                    title: 'Crea una nueva contraseña',
                    subtitle: 'Abriste el enlace de recuperación. Elige una contraseña que no uses en otros sitios.',
                  ),
                  if (state.failure != null) AppBanner(tone: BannerTone.error, message: state.failure!.message),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    spacing: 12,
                    children: [
                      AppPasswordField(
                        label: 'Nueva contraseña',
                        controller: _password,
                        newPassword: true,
                        validator: Validators.newPassword,
                        enabled: !busy,
                        textInputAction: TextInputAction.next,
                      ),
                      PasswordChecklist(controller: _password),
                    ],
                  ),
                  AppPasswordField(
                    label: 'Repite la contraseña',
                    controller: _confirm,
                    newPassword: true,
                    validator: Validators.matches(() => _password.text),
                    enabled: !busy,
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) => _submit(),
                  ),
                ],
                footer: [
                  AppButton(label: 'Guardar y entrar', loading: busy, onPressed: _submit),
                  AppButton(
                    label: 'Cancelar',
                    variant: AppButtonVariant.ghost,
                    onPressed: busy ? null : () => context.read<SessionCubit>().signOut(),
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
