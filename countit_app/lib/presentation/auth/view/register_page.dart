import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router/app_router.dart';
import '../../../app/router/navigation.dart';
import '../../../app/theme/tokens.dart';
import '../../../data/repositories/auth_repository.dart';
import '../../../shared/state/submit_cubit.dart';
import '../../../shared/utils/validators.dart';
import '../../../shared/widgets/app_banner.dart';
import '../../../shared/widgets/app_fields.dart';
import '../../../shared/widgets/app_layout.dart';
import '../../../shared/widgets/cooldown_button.dart';
import '../../../shared/widgets/password_checklist.dart';
import '../../../shared/widgets/secure_screen.dart';
import '../cubit/register_cubit.dart';
import 'captcha_form.dart';

/// Registration (HU-01, design Registro · COU-82, COU-102, COU-105).
class RegisterPage extends StatelessWidget {
  const RegisterPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) => RegisterCubit(context.read<AuthRepository>()),
      child: const SecureScreen(child: _RegisterView()),
    );
  }
}

class _RegisterView extends StatefulWidget {
  const _RegisterView();

  @override
  State<_RegisterView> createState() => _RegisterViewState();
}

class _RegisterViewState extends State<_RegisterView> with CaptchaForm {
  final _formKey = GlobalKey<FormState>();
  final _firstName = TextEditingController();
  final _lastName = TextEditingController();
  final _username = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();

  @override
  void dispose() {
    for (final c in [_firstName, _lastName, _username, _email, _password, _confirm]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final email = _email.text.trim().toLowerCase();
    final ok = await context.read<RegisterCubit>().register(
      firstName: _firstName.text,
      lastName: _lastName.text,
      username: _username.text,
      email: email,
      password: _password.text,
      captchaToken: captchaToken,
    );
    resetCaptcha();
    // Replace the stack: back must not return to a form full of data (COU-110).
    if (ok && mounted) context.go(AppRoutes.checkEmail, extra: email);
  }

  /// Edits hide the server's last answer so stale field errors do not linger.
  void _edited(String _) => context.read<RegisterCubit>().clearFailure();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppTopBar(title: 'Crear cuenta', onBack: () => context.backOr(AppRoutes.welcome)),
      body: BlocBuilder<RegisterCubit, SubmitState>(
        builder: (context, state) {
          final busy = state.submitting || state.status == SubmitStatus.success;
          final failure = state.failure;
          final usernameError =
              state.fieldError('username') ?? (failure?.key == 'username_taken' ? failure!.message : null);
          final fieldErrorShown = usernameError != null || (failure?.fieldErrors.isNotEmpty ?? false);
          return Form(
            key: _formKey,
            child: AutofillGroup(
              child: FormScreenBody(
                content: [
                  if (failure != null && !fieldErrorShown) AppBanner(tone: BannerTone.error, message: failure.message),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    spacing: AppSpacing.md,
                    children: [
                      Expanded(
                        child: AppTextField(
                          label: 'Nombre',
                          controller: _firstName,
                          textCapitalization: TextCapitalization.words,
                          autofillHints: const [AutofillHints.givenName],
                          textInputAction: TextInputAction.next,
                          maxLength: 40,
                          validator: (v) => Validators.personName(v),
                          errorText: state.fieldError('firstName'),
                          enabled: !busy,
                          onChanged: _edited,
                        ),
                      ),
                      Expanded(
                        child: AppTextField(
                          label: 'Apellido',
                          controller: _lastName,
                          textCapitalization: TextCapitalization.words,
                          autofillHints: const [AutofillHints.familyName],
                          textInputAction: TextInputAction.next,
                          maxLength: 40,
                          validator: (v) => Validators.personName(v, label: 'apellido'),
                          errorText: state.fieldError('lastName'),
                          enabled: !busy,
                          onChanged: _edited,
                        ),
                      ),
                    ],
                  ),
                  AppTextField(
                    label: 'Nombre de usuario',
                    controller: _username,
                    helper: '5 a 12 caracteres: letras, números, - y _. Así te invitarán a familias.',
                    autofillHints: const [AutofillHints.newUsername],
                    textInputAction: TextInputAction.next,
                    maxLength: 12,
                    validator: Validators.username,
                    errorText: usernameError,
                    enabled: !busy,
                    onChanged: _edited,
                    prefix: const Padding(
                      padding: EdgeInsets.only(left: AppSpacing.lg, right: AppSpacing.xs),
                      child: Text('@', style: TextStyle(fontSize: 16, color: AppColors.muted)),
                    ),
                  ),
                  AppTextField(
                    label: 'Correo electrónico',
                    controller: _email,
                    keyboardType: TextInputType.emailAddress,
                    autofillHints: const [AutofillHints.email],
                    textInputAction: TextInputAction.next,
                    maxLength: 255,
                    validator: Validators.email,
                    errorText: state.fieldError('email'),
                    enabled: !busy,
                    onChanged: _edited,
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    spacing: AppSpacing.md,
                    children: [
                      AppPasswordField(
                        controller: _password,
                        newPassword: true,
                        validator: Validators.newPassword,
                        errorText: state.fieldError('password'),
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
                  captchaSlot(),
                ],
                footer: [
                  CooldownButton(
                    label: 'Crear cuenta',
                    loading: busy,
                    until: state.blockedUntil,
                    onPressed: captchaReady ? _submit : null,
                  ),
                  AppLinkPrompt(
                    text: '¿Ya tienes cuenta?',
                    link: 'Inicia sesión',
                    onPressed: () => context.pushReplacement(AppRoutes.login),
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
