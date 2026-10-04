import 'package:flutter/material.dart';

import '../../app/theme/tokens.dart';

/// Title of a section inside a screen («Presupuestos», «Movimientos») with
/// optional trailing actions (44 px targets).
class SectionHeader extends StatelessWidget {
  const SectionHeader({super.key, required this.title, this.actions = const []});

  final String title;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: AppSizes.iconButton),
        child: Row(
          children: [
            Expanded(
              child: Semantics(header: true, child: Text(title, style: AppTypography.h2)),
            ),
            ...actions,
          ],
        ),
      ),
    );
  }
}

/// «Nuevo»-style text action for a [SectionHeader].
class SectionAction extends StatelessWidget {
  const SectionAction({super.key, required this.label, required this.icon, required this.onPressed});

  final String label;
  final IconData icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return TextButton.icon(
      onPressed: onPressed,
      icon: Icon(icon),
      label: Text(label),
      style: TextButton.styleFrom(minimumSize: const Size(AppSizes.iconButton, AppSizes.iconButton)),
    );
  }
}
