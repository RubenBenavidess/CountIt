import 'package:flutter/material.dart';

import '../../app/theme/app_theme.dart';
import '../../app/theme/tokens.dart';
import 'motion.dart';

enum AppButtonVariant {
  /// Alabaster on dark: the main action of a screen.
  primary,

  /// Dusk Blue.
  secondary,

  /// Outlined, transparent: tertiary actions.
  ghost,

  /// Outlined in the expense colour: destructive action that still asks for confirmation.
  danger,

  /// Filled in the expense colour: the final «Eliminar» inside a confirmation.
  dangerSolid,
}

/// Button of the design (52 px, radius 14; small = 40 px). While [loading] it
/// shows a spinner, keeps its size and ignores taps.
class AppButton extends StatelessWidget {
  const AppButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.variant = AppButtonVariant.primary,
    this.icon,
    this.loading = false,
    this.small = false,
    this.expand = true,
  });

  final String label;
  final VoidCallback? onPressed;
  final AppButtonVariant variant;
  final IconData? icon;
  final bool loading;
  final bool small;
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final palette = context.palette;
    final height = small ? AppSizes.buttonSmall : AppSizes.button;
    final radius = BorderRadius.circular(small ? AppRadii.md : AppRadii.lg);

    final (Color? background, Color foreground, BorderSide? border) = switch (variant) {
      AppButtonVariant.primary => (scheme.primary, scheme.onPrimary, null),
      AppButtonVariant.secondary => (AppColors.dusk, AppColors.white, null),
      AppButtonVariant.ghost => (null, scheme.onSurface, BorderSide(color: palette.line, width: AppSizes.borderWidth)),
      AppButtonVariant.danger => (
        null,
        palette.expense,
        const BorderSide(color: AppColors.dangerBorder, width: AppSizes.borderWidth),
      ),
      AppButtonVariant.dangerSolid => (palette.expense, AppColors.ink, null),
    };

    final style = ButtonStyle(
      minimumSize: WidgetStatePropertyAll(Size(expand ? double.infinity : 0, height)),
      padding: WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: small ? 14 : AppSpacing.xl)),
      shape: WidgetStatePropertyAll(RoundedRectangleBorder(borderRadius: radius)),
      side: border == null ? null : WidgetStatePropertyAll(border),
      backgroundColor: WidgetStateProperty.resolveWith(
        (states) => background == null
            ? Colors.transparent
            : states.contains(WidgetState.disabled) && !loading
            ? background.withValues(alpha: 0.4)
            : background,
      ),
      foregroundColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.disabled) && !loading ? foreground.withValues(alpha: 0.5) : foreground,
      ),
      textStyle: WidgetStatePropertyAll(AppTypography.button.copyWith(fontSize: small ? 14 : 16)),
      elevation: const WidgetStatePropertyAll(0),
    );

    final child = loading
        ? Semantics(
            label: '$label, cargando',
            child: SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2, color: foreground)),
          )
        : Row(
            mainAxisSize: MainAxisSize.min,
            spacing: AppSpacing.sm,
            children: [
              if (icon != null) Icon(icon, size: 20),
              Flexible(child: Text(label, overflow: TextOverflow.ellipsis)),
            ],
          );

    // FilledButton already exposes button semantics; wrapping it again would
    // announce two buttons to screen readers.
    final enabled = !loading && onPressed != null;
    return PressScale(
      enabled: enabled,
      child: FilledButton(onPressed: enabled ? onPressed : null, style: style, child: child),
    );
  }
}
