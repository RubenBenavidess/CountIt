import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../app/errors/app_failure.dart';
import '../../../app/router/app_router.dart';
import '../../../app/router/navigation.dart';
import '../../../app/session/session_cubit.dart';
import '../../../data/repositories/auth_repository.dart';
import '../../../shared/state/submit_cubit.dart';
import '../../../shared/utils/validators.dart';
import '../../../shared/widgets/app_banner.dart';
import '../../../shared/widgets/app_fields.dart';
import '../../../shared/widgets/app_layout.dart';
import '../../../shared/widgets/cooldown_button.dart';
import '../../../shared/widgets/secure_screen.dart';
import '../cubit/login_cubit.dart';
import 'auth_header.dart';
import 'captcha_form.dart';

/// Login (HU-02, design Login · COU-84, COU-118, COU-125).
class LoginPage extends StatelessWidget {
  const LoginPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) => LoginCubit(context.read<AuthRepository>()),
      child: const SecureScreen(child: _LoginView()),
    );
  }
}

class _LoginView extends StatefulWidget {
  const _LoginView();

  @override
  State<_LoginView> createState() => _LoginViewState();
}

class _LoginViewState extends State<_LoginView> with CaptchaForm {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _passwordFocus = FocusNode();

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _passwordFocus.dispose();
    super.dispose();
  }

  void _submit() {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    context.read<LoginCubit>().login(email: _email.text, password: _password.text, captchaToken: captchaToken);
  }

  void _onResult(BuildContext context, SubmitState state) {
    resetCaptcha();
    if (state.failure?.kind == FailureKind.invalidCredentials) {
      // Ask again for the password only; the e-mail stays.
      _password.clear();
      _passwordFocus.requestFocus();
    }
  }

  @override
  Widget build(BuildContext context) {
    final sessionMessage = context.select((SessionCubit c) => c.state.message);
    return Scaffold(
      appBar: AppTopBar(showWordmark: true, onBack: () => context.backOr(AppRoutes.welcome)),
      body: BlocConsumer<LoginCubit, SubmitState>(
        listenWhen: (previous, current) =>
            previous.status != current.status &&
            (current.status == SubmitStatus.failure || current.status == SubmitStatus.success),
        listener: _onResult,
        builder: (context, state) {
          final busy = state.submitting || state.status == SubmitStatus.success;
          final failure = state.failure;
          return Form(
            key: _formKey,
            child: AutofillGroup(
              child: FormScreenBody(
                gap: 18,
                content: [
                  const AuthHeader(title: 'Hola de nuevo', subtitle: 'Inicia sesión con tu correo.'),
                  if (failure != null)
                    AppBanner(
                      tone: BannerTone.error,
                      message: failure.message,
                      action: failure.key == 'email_not_confirmed'
                          ? AppLink(
                              label: 'Ir a revisar mi correo',
                              onPressed: () => context.go(AppRoutes.checkEmail, extra: _email.text.trim()),
                            )
                          : null,
                    )
                  else if (sessionMessage != null)
                    AppBanner(message: sessionMessage),
                  AppTextField(
                    label: 'Correo electrónico',
                    controller: _email,
                    keyboardType: TextInputType.emailAddress,
                    autofillHints: const [AutofillHints.email],
                    textInputAction: TextInputAction.next,
                    validator: Validators.email,
                    enabled: !busy,
                    onSubmitted: (_) => _passwordFocus.requestFocus(),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      AppPasswordField(
                        controller: _password,
                        focusNode: _passwordFocus,
                        validator: Validators.existingPassword,
                        enabled: !busy,
                        textInputAction: TextInputAction.done,
                        onSubmitted: (_) => _submit(),
                      ),
                      AppLink(
                        label: '¿Olvidaste tu contraseña?',
                        onPressed: busy ? null : () => context.push(AppRoutes.forgotPassword),
                      ),
                    ],
                  ),
                  captchaSlot(),
                ],
                footer: [
                  CooldownButton(
                    label: 'Iniciar sesión',
                    loading: busy,
                    until: state.blockedUntil,
                    onPressed: captchaReady ? _submit : null,
                  ),
                  AppLinkPrompt(
                    text: '¿No tienes cuenta?',
                    link: 'Crea una',
                    onPressed: () => context.pushReplacement(AppRoutes.register),
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
