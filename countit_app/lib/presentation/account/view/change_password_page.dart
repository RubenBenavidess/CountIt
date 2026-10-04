import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../app/errors/app_failure.dart';
import '../../../app/session/session_cubit.dart';
import '../../../data/repositories/auth_repository.dart';
import '../../../shared/state/submit_cubit.dart';
import '../../../shared/utils/validators.dart';
import '../../../shared/widgets/app_banner.dart';
import '../../../shared/widgets/app_feedback.dart';
import '../../../shared/widgets/app_fields.dart';
import '../../../shared/widgets/app_layout.dart';
import '../../../shared/widgets/cooldown_button.dart';
import '../../../shared/widgets/password_checklist.dart';
import '../../../shared/widgets/secure_screen.dart';
import '../cubit/account_cubits.dart';

/// HU-04 (design CambiarContrasena · COU-138, COU-142).
class ChangePasswordPage extends StatelessWidget {
  const ChangePasswordPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) =>
          ChangePasswordCubit(auth: context.read<AuthRepository>(), session: context.read<SessionCubit>()),
      child: const SecureScreen(child: _ChangePasswordView()),
    );
  }
}

class _ChangePasswordView extends StatefulWidget {
  const _ChangePasswordView();

  @override
  State<_ChangePasswordView> createState() => _ChangePasswordViewState();
}

class _ChangePasswordViewState extends State<_ChangePasswordView> {
  final _formKey = GlobalKey<FormState>();
  final _current = TextEditingController();
  final _new = TextEditingController();
  final _confirm = TextEditingController();

  @override
  void dispose() {
    _current.dispose();
    _new.dispose();
    _confirm.dispose();
    super.dispose();
  }

  String? _validateNew(String? value) =>
      Validators.newPassword(value) ??
      (value == _current.text ? 'La nueva contraseña debe ser diferente a la actual' : null);

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final session = context.read<SessionCubit>();
    final ok = await context.read<ChangePasswordCubit>().change(currentPassword: _current.text, newPassword: _new.text);
    // Without a fresh session the cubit signed out and the router took over.
    if (ok && mounted && session.state.profile != null) {
      showAppSnackBar(context, 'Actualizamos tu contraseña', kind: SnackKind.success);
      context.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const AppTopBar(title: 'Cambiar contraseña'),
      body: BlocConsumer<ChangePasswordCubit, SubmitState>(
        listenWhen: (previous, current) =>
            current.status == SubmitStatus.failure && current.failure?.kind == FailureKind.invalidCredentials,
        listener: (context, state) => _current.clear(),
        builder: (context, state) {
          final failure = state.failure;
          final wrongCurrent = failure?.kind == FailureKind.invalidCredentials;
          final busy = state.submitting || state.status == SubmitStatus.success;
          return Form(
            key: _formKey,
            child: AutofillGroup(
              child: FormScreenBody(
                content: [
                  if (failure != null && !wrongCurrent && failure.fieldErrors.isEmpty)
                    AppBanner(tone: BannerTone.error, message: failure.message),
                  AppPasswordField(
                    label: 'Contraseña actual',
                    controller: _current,
                    errorText: wrongCurrent ? failure!.message : state.fieldError('currentPassword'),
                    validator: Validators.existingPassword,
                    enabled: !busy,
                    textInputAction: TextInputAction.next,
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    spacing: 12,
                    children: [
                      AppPasswordField(
                        label: 'Nueva contraseña',
                        controller: _new,
                        newPassword: true,
                        errorText: state.fieldError('newPassword'),
                        validator: _validateNew,
                        enabled: !busy,
                        textInputAction: TextInputAction.next,
                      ),
                      PasswordChecklist(controller: _new),
                    ],
                  ),
                  AppPasswordField(
                    label: 'Repite la nueva contraseña',
                    controller: _confirm,
                    newPassword: true,
                    validator: Validators.matches(() => _new.text),
                    enabled: !busy,
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) => _submit(),
                  ),
                  const AppBanner(
                    message: 'Cerraremos tu sesión en los demás dispositivos y te avisaremos por correo.',
                  ),
                ],
                footer: [
                  CooldownButton(
                    label: 'Guardar contraseña',
                    loading: busy,
                    until: state.blockedUntil,
                    onPressed: failure?.kind == FailureKind.locked ? null : _submit,
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
