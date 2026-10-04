import 'package:flutter/material.dart';

import '../../app/theme/app_theme.dart';
import '../../app/theme/tokens.dart';

enum BannerTone { info, success, error }

/// Inline banner of the design (radius 14, icon + caption): errors under a
/// form, confirmations, explanations. Announced by screen readers when it
/// appears (`liveRegion`).
class AppBanner extends StatelessWidget {
  const AppBanner({super.key, required this.message, this.tone = BannerTone.info, this.action});

  final String message;
  final BannerTone tone;

  /// Optional link-style action under the text (e.g. «Revisar mi correo»).
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final scheme = Theme.of(context).colorScheme;
    final (IconData icon, Color iconColor, Color background, Color border) = switch (tone) {
      BannerTone.error => (
        Icons.warning_amber_rounded,
        palette.expense,
        AppColors.errorBannerBackground,
        AppColors.errorBannerBorder,
      ),
      BannerTone.success => (Icons.check_rounded, palette.income, scheme.surface, palette.line),
      BannerTone.info => (Icons.info_outline_rounded, AppColors.lavender, scheme.surface, palette.line),
    };
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Semantics(
      liveRegion: true,
      container: true,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: isDark ? background : scheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(AppRadii.lg),
          border: Border.all(color: border),
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: AppSpacing.md,
            children: [
              Icon(icon, size: 20, color: iconColor),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  spacing: AppSpacing.xs,
                  children: [
                    Text(message, style: AppTypography.caption.copyWith(color: scheme.onSurface)),
                    ?action,
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
