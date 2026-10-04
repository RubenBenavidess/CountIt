import 'package:flutter/material.dart';

import '../../../app/theme/tokens.dart';

/// Title and subtitle at the top of the auth screens (design `.h1` + caption).
class AuthHeader extends StatelessWidget {
  const AuthHeader({super.key, required this.title, this.subtitle});

  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: AppSpacing.sm,
      children: [
        Semantics(header: true, child: Text(title, style: AppTypography.h1)),
        if (subtitle != null) Text(subtitle!, style: AppTypography.body.copyWith(color: AppColors.muted)),
      ],
    );
  }
}

/// Large icon tile + title + body, for result screens (correo enviado,
/// correo confirmado).
class AuthResult extends StatelessWidget {
  const AuthResult({super.key, required this.icon, required this.title, required this.body, this.iconColor});

  final IconData icon;
  final String title;
  final Widget body;
  final Color? iconColor;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: 18,
      children: [
        Container(
          width: 88,
          height: 88,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(28),
          ),
          child: Icon(icon, size: 44, color: iconColor ?? AppColors.lavender),
        ),
        Semantics(header: true, child: Text(title, style: AppTypography.h1)),
        body,
      ],
    );
  }
}
