import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router/app_router.dart';
import '../../../app/theme/app_theme.dart';
import '../../../app/theme/tokens.dart';
import '../../../shared/widgets/app_button.dart';
import '../../../shared/widgets/app_layout.dart';
import 'auth_header.dart';

/// Landing of `https://<host>/auth/confirmed` (COU-114). The app does not sign in
/// from the link: login goes through the Edge Function (rate limit, captcha).
class EmailConfirmedPage extends StatelessWidget {
  const EmailConfirmedPage({super.key, this.expired = false});

  final bool expired;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const AppTopBar(showWordmark: true, showBack: false),
      body: FormScreenBody(
        content: [
          const SizedBox(height: AppSpacing.xxl),
          if (expired)
            AuthResult(
              icon: Icons.link_off_rounded,
              iconColor: context.palette.expense,
              title: 'El enlace venció o ya fue usado',
              body: Text(
                'Inicia sesión: si tu correo sigue sin confirmar, te enviaremos un enlace nuevo.',
                style: AppTypography.body.copyWith(color: AppColors.muted),
              ),
            )
          else
            AuthResult(
              icon: Icons.verified_outlined,
              iconColor: context.palette.income,
              title: '¡Correo confirmado!',
              body: Text(
                'Tu cuenta está lista. Inicia sesión con tu correo y contraseña.',
                style: AppTypography.body.copyWith(color: AppColors.muted),
              ),
            ),
        ],
        footer: [AppButton(label: 'Iniciar sesión', onPressed: () => context.go(AppRoutes.login))],
      ),
    );
  }
}
