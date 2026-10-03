import 'package:flutter/material.dart';

import '../../app/theme/app_theme.dart';
import '../../app/theme/tokens.dart';

/// Card of the design: Prussian Blue surface (or outlined), radius 18, 18 px padding.
class AppCard extends StatelessWidget {
  const AppCard({
    super.key,
    required this.child,
    this.outlined = false,
    this.padding = const EdgeInsets.all(18),
    this.onTap,
    this.semanticLabel,
  });

  final Widget child;
  final bool outlined;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(AppRadii.card);
    final card = Material(
      color: outlined ? Colors.transparent : Theme.of(context).colorScheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: radius,
        side: outlined ? BorderSide(color: context.palette.line, width: AppSizes.borderWidth) : BorderSide.none,
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(padding: padding, child: child),
      ),
    );
    return onTap == null && semanticLabel == null
        ? card
        : Semantics(button: onTap != null, label: semanticLabel, child: card);
  }
}

enum BadgeTone { neutral, pro, warn, ok }

/// Small pill: «Pro», «Excedido», «Aceptada», «Programada».
class AppBadge extends StatelessWidget {
  const AppBadge(this.label, {super.key, this.tone = BadgeTone.neutral});

  final String label;
  final BadgeTone tone;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final (background, foreground) = switch (tone) {
      BadgeTone.neutral => (palette.surface2, Theme.of(context).colorScheme.onSurface),
      BadgeTone.pro => (AppColors.lavender, AppColors.ink),
      BadgeTone.warn => (AppColors.warnBackground, AppColors.expense),
      BadgeTone.ok => (AppColors.okBackground, AppColors.income),
    };
    return Container(
      height: 24,
      padding: const EdgeInsets.symmetric(horizontal: 9),
      alignment: Alignment.center,
      decoration: BoxDecoration(color: background, borderRadius: BorderRadius.circular(12)),
      child: Text(label, style: AppTypography.overline.copyWith(letterSpacing: 0, color: foreground)),
    );
  }
}

enum ProgressTone { normal, over, income }

/// 8 px progress bar (budgets): Lavender, expense colour when exceeded, income colour for income budgets.
class AppProgressBar extends StatelessWidget {
  const AppProgressBar({super.key, required this.value, this.tone = ProgressTone.normal, this.semanticLabel});

  /// 0..1 (clamped; an exceeded budget passes >1 and shows full).
  final double value;
  final ProgressTone tone;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final color = switch (tone) {
      ProgressTone.normal => AppColors.lavender,
      ProgressTone.over => palette.expense,
      ProgressTone.income => palette.income,
    };
    return Semantics(
      label: semanticLabel,
      value: '${(value * 100).round()} %',
      child: ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: LinearProgressIndicator(
          value: value.clamp(0, 1),
          minHeight: 8,
          color: color,
          backgroundColor: palette.surface2,
        ),
      ),
    );
  }
}
