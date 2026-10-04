import 'package:flutter/material.dart';

import '../../../../app/theme/app_theme.dart';
import '../../../../app/theme/tokens.dart';
import '../../../../shared/widgets/app_card.dart';

/// Way into a screen of the wallet (programados, estadísticas…): icon,
/// title and a line of explanation, read as one button.
class EntryCard extends StatelessWidget {
  const EntryCard({super.key, required this.icon, required this.title, required this.subtitle, required this.onTap});

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      outlined: true,
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: AppSpacing.md),
      onTap: onTap,
      semanticLabel: '$title: $subtitle',
      child: ExcludeSemantics(
        child: Row(
          spacing: AppSpacing.md,
          children: [
            IconTile(icon),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: AppTypography.label),
                  Text(subtitle, style: AppTypography.caption.copyWith(color: context.palette.muted)),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded),
          ],
        ),
      ),
    );
  }
}
