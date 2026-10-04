import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router/app_router.dart';
import '../../../app/theme/tokens.dart';
import '../../../shared/platform/mail_launcher.dart';
import '../../../shared/utils/validators.dart';
import '../../../shared/widgets/app_banner.dart';
import '../../../shared/widgets/app_button.dart';
import '../../../shared/widgets/app_feedback.dart';
import '../../../shared/widgets/app_layout.dart';
import 'auth_header.dart';

/// «Revisa tu correo» after registering (HU-01, design CorreoEnviado ·
/// COU-110). Generic on purpose: it never confirms the e-mail was new.
class CheckEmailPage extends StatelessWidget {
  const CheckEmailPage({super.key, this.email, this.mail = const MailLauncher()});

  final String? email;
  final MailLauncher mail;

  Future<void> _openMail(BuildContext context) async {
    final opened = await mail.openInbox();
    if (!opened && context.mounted) {
      showAppSnackBar(context, 'No encontramos una app de correo en este teléfono');
    }
  }

  @override
  Widget build(BuildContext context) {
    final address = email;
    return Scaffold(
      appBar: AppTopBar(onBack: () => context.go(AppRoutes.login)),
      body: FormScreenBody(
        content: [
          const SizedBox(height: AppSpacing.xxl),
          AuthResult(
            icon: Icons.mail_outline_rounded,
            title: 'Revisa tu correo',
            body: Text.rich(
              TextSpan(
                style: AppTypography.body,
                children: [
                  if (address == null || address.isEmpty)
                    const TextSpan(text: 'Si el correo puede registrarse')
                  else ...[
                    const TextSpan(text: 'Si '),
                    TextSpan(
                      text: maskEmail(address),
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const TextSpan(text: ' puede registrarse'),
                  ],
                  const TextSpan(text: ', te enviamos un enlace para confirmar tu cuenta. Ábrelo desde este teléfono.'),
                ],
              ),
            ),
          ),
          const AppBanner(
            message: '¿No te llegó? Revisa la carpeta de spam. Si intentas iniciar sesión sin confirmar, te reenviamos el enlace.',
          ),
        ],
        footer: [
          AppButton(
            label: 'Abrir app de correo',
            variant: AppButtonVariant.ghost,
            icon: Icons.open_in_new_rounded,
            onPressed: () => _openMail(context),
          ),
          AppButton(label: 'Ir a iniciar sesión', onPressed: () => context.go(AppRoutes.login)),
        ],
      ),
    );
  }
}
