import 'package:flutter/material.dart';

import '../../app/theme/app_theme.dart';
import '../../app/theme/tokens.dart';
import '../utils/validators.dart';

/// Live checklist of the password policy under a new-password field (design
/// Registro/Restablecer). Listens to [controller] itself, so typing rebuilds
/// only these three rows.
class PasswordChecklist extends StatelessWidget {
  const PasswordChecklist({super.key, required this.controller});

  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: controller,
      builder: (context, value, _) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 6,
        children: [
          for (final rule in PasswordRule.values)
            _Rule(label: rule.label, met: rule.isMetBy(value.text), metColor: palette.income),
        ],
      ),
    );
  }
}

class _Rule extends StatelessWidget {
  const _Rule({required this.label, required this.met, required this.metColor});

  final String label;
  final bool met;
  final Color metColor;

  @override
  Widget build(BuildContext context) {
    final color = met ? metColor : AppColors.muted;
    return Semantics(
      label: '$label: ${met ? 'cumplido' : 'pendiente'}',
      excludeSemantics: true,
      child: Row(
        spacing: AppSpacing.sm,
        children: [
          Icon(met ? Icons.check_rounded : Icons.circle_outlined, size: 16, color: color),
          Text(label, style: AppTypography.caption.copyWith(color: color)),
        ],
      ),
    );
  }
}
