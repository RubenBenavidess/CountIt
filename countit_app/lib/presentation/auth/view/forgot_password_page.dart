import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../app/errors/error_mapper.dart';
import '../../../app/router/app_router.dart';
import '../../../app/router/navigation.dart';
import '../../../data/repositories/auth_repository.dart';
import '../../../shared/state/submit_cubit.dart';
import '../../../shared/utils/validators.dart';
import '../../../shared/widgets/app_banner.dart';
import '../../../shared/widgets/app_fields.dart';
import '../../../shared/widgets/app_layout.dart';
import '../../../shared/widgets/cooldown_button.dart';
import '../cubit/password_cubits.dart';
import 'auth_header.dart';
import 'captcha_form.dart';

/// «Recupera tu contraseña» (HU-03, design Recuperar · COU-85, COU-133).
class ForgotPasswordPage extends StatelessWidget {
  const ForgotPasswordPage({super.key, this.linkExpired = false});

  /// Opened from an expired or already used reset link.
  final bool linkExpired;

  static const sentMessage =
      'Si el correo está registrado, recibirás el enlace en unos minutos. '
      'Cambiar la contraseña también desbloquea tu cuenta si estaba bloqueada.';

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) => ForgotPasswordCubit(context.read<AuthRepository>()),
      child: _ForgotPasswordView(linkExpired: linkExpired),
    );
  }
}

class _ForgotPasswordView extends StatefulWidget {
  const _ForgotPasswordView({required this.linkExpired});

  final bool linkExpired;

  @override
  State<_ForgotPasswordView> createState() => _ForgotPasswordViewState();
}

class _ForgotPasswordViewState extends State<_ForgotPasswordView> with CaptchaForm {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    await context.read<ForgotPasswordCubit>().requestLink(email: _email.text, captchaToken: captchaToken);
    resetCaptcha();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppTopBar(onBack: () => context.backOr(AppRoutes.login)),
      body: BlocBuilder<ForgotPasswordCubit, SubmitState>(
        builder: (context, state) {
          final sent = state.status == SubmitStatus.success;
          return Form(
            key: _formKey,
            child: FormScreenBody(
              gap: 18,
              content: [
                const AuthHeader(
                  title: 'Recupera tu contraseña',
                  subtitle: 'Escribe el correo de tu cuenta y te enviaremos un enlace para crear una nueva.',
                ),
                if (widget.linkExpired && state.status == SubmitStatus.idle)
                  AppBanner(tone: BannerTone.error, message: ErrorMapper.messages['otp_expired']!),
                AppTextField(
                  label: 'Correo electrónico',
                  controller: _email,
                  keyboardType: TextInputType.emailAddress,
                  autofillHints: const [AutofillHints.email],
                  textInputAction: TextInputAction.done,
                  validator: Validators.email,
                  enabled: !state.submitting,
                  onSubmitted: (_) => _submit(),
                ),
                if (sent) const AppBanner(tone: BannerTone.success, message: ForgotPasswordPage.sentMessage),
                if (state.failure != null) AppBanner(tone: BannerTone.error, message: state.failure!.message),
                captchaSlot(),
              ],
              footer: [
                CooldownButton(
                  label: sent ? 'Reenviar enlace' : 'Enviar enlace',
                  loading: state.submitting,
                  until: state.blockedUntil,
                  onPressed: captchaReady ? _submit : null,
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
