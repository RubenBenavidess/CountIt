import 'package:flutter/material.dart';

import 'tokens.dart';

/// Semantic colours that Material's [ColorScheme] has no slot for.
@immutable
class AppPalette extends ThemeExtension<AppPalette> {
  const AppPalette({
    required this.income,
    required this.expense,
    required this.muted,
    required this.line,
    required this.surface2,
  });

  static const dark = AppPalette(
    income: AppColors.income,
    expense: AppColors.expense,
    muted: AppColors.muted,
    line: AppColors.line,
    surface2: AppColors.surface2,
  );

  /// Light variant: darker income/expense so they keep 4.5:1 on Alabaster.
  static const light = AppPalette(
    income: Color(0xFF1A6B4A),
    expense: Color(0xFF9E4523),
    muted: Color(0xFF4F5D72),
    line: Color(0xFFC9CCC5),
    surface2: Color(0xFFEEEFEA),
  );

  final Color income;
  final Color expense;
  final Color muted;
  final Color line;
  final Color surface2;

  @override
  AppPalette copyWith({Color? income, Color? expense, Color? muted, Color? line, Color? surface2}) => AppPalette(
    income: income ?? this.income,
    expense: expense ?? this.expense,
    muted: muted ?? this.muted,
    line: line ?? this.line,
    surface2: surface2 ?? this.surface2,
  );

  @override
  AppPalette lerp(AppPalette? other, double t) {
    if (other == null) return this;
    return AppPalette(
      income: Color.lerp(income, other.income, t)!,
      expense: Color.lerp(expense, other.expense, t)!,
      muted: Color.lerp(muted, other.muted, t)!,
      line: Color.lerp(line, other.line, t)!,
      surface2: Color.lerp(surface2, other.surface2, t)!,
    );
  }
}

extension AppThemeContext on BuildContext {
  AppPalette get palette => Theme.of(this).extension<AppPalette>()!;
}

/// Themes built from the design tokens. The design is dark-first; the light
/// theme keeps the same structure on an Alabaster background.
abstract final class AppTheme {
  static ThemeData get dark => _build(
    brightness: Brightness.dark,
    background: AppColors.ink,
    surface: AppColors.prussian,
    onSurface: AppColors.alabaster,
    primary: AppColors.alabaster,
    onPrimary: AppColors.ink,
    palette: AppPalette.dark,
  );

  static ThemeData get light => _build(
    brightness: Brightness.light,
    background: AppColors.alabaster,
    surface: AppColors.white,
    onSurface: AppColors.ink,
    primary: AppColors.ink,
    onPrimary: AppColors.alabaster,
    palette: AppPalette.light,
  );

  static ThemeData _build({
    required Brightness brightness,
    required Color background,
    required Color surface,
    required Color onSurface,
    required Color primary,
    required Color onPrimary,
    required AppPalette palette,
  }) {
    final scheme = ColorScheme(
      brightness: brightness,
      primary: primary,
      onPrimary: onPrimary,
      secondary: AppColors.dusk,
      onSecondary: AppColors.white,
      tertiary: AppColors.lavender,
      onTertiary: AppColors.ink,
      error: palette.expense,
      onError: AppColors.ink,
      surface: surface,
      onSurface: onSurface,
      onSurfaceVariant: palette.muted,
      outline: palette.line,
      outlineVariant: palette.line,
      surfaceContainerHighest: palette.surface2,
    );

    final textTheme = TextTheme(
      displayLarge: AppTypography.display,
      headlineMedium: AppTypography.h1,
      titleLarge: AppTypography.title,
      titleMedium: AppTypography.h2,
      bodyLarge: AppTypography.body,
      bodyMedium: AppTypography.body,
      bodySmall: AppTypography.caption.copyWith(color: palette.muted),
      labelLarge: AppTypography.button,
      labelMedium: AppTypography.label,
      labelSmall: AppTypography.overline.copyWith(color: palette.muted),
    ).apply(bodyColor: onSurface, displayColor: onSurface);

    const buttonShape = RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(AppRadii.lg)));
    const buttonSize = Size.fromHeight(AppSizes.button);
    const buttonPadding = EdgeInsets.symmetric(horizontal: AppSpacing.xl);

    OutlineInputBorder inputBorder(Color color) => OutlineInputBorder(
      borderRadius: const BorderRadius.all(Radius.circular(AppRadii.lg)),
      borderSide: BorderSide(color: color, width: AppSizes.borderWidth),
    );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: background,
      fontFamily: AppTypography.family,
      textTheme: textTheme,
      extensions: [palette],
      appBarTheme: AppBarTheme(
        backgroundColor: background,
        foregroundColor: onSurface,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: AppTypography.title.copyWith(color: onSurface),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: primary,
          foregroundColor: onPrimary,
          minimumSize: buttonSize,
          padding: buttonPadding,
          shape: buttonShape,
          textStyle: AppTypography.button,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: onSurface,
          minimumSize: buttonSize,
          padding: buttonPadding,
          shape: buttonShape,
          side: BorderSide(color: palette.line, width: AppSizes.borderWidth),
          textStyle: AppTypography.button,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: onSurface,
          textStyle: AppTypography.label.copyWith(fontWeight: FontWeight.w700, decoration: TextDecoration.underline),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surface,
        contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.lg),
        hintStyle: AppTypography.body.copyWith(color: AppColors.placeholder),
        helperStyle: AppTypography.caption.copyWith(color: palette.muted),
        errorStyle: AppTypography.caption.copyWith(color: palette.expense),
        border: inputBorder(palette.line),
        enabledBorder: inputBorder(palette.line),
        focusedBorder: inputBorder(AppColors.lavender),
        errorBorder: inputBorder(palette.expense),
        focusedErrorBorder: inputBorder(palette.expense),
        disabledBorder: inputBorder(palette.line.withValues(alpha: 0.6)),
      ),
      cardTheme: CardThemeData(
        color: surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(AppRadii.card))),
      ),
      dividerTheme: DividerThemeData(color: palette.line, thickness: 1, space: 1),
      chipTheme: ChipThemeData(
        backgroundColor: Colors.transparent,
        selectedColor: primary,
        side: BorderSide(color: palette.line, width: AppSizes.borderWidth),
        shape: const StadiumBorder(),
        labelStyle: AppTypography.label.copyWith(color: onSurface),
        secondaryLabelStyle: AppTypography.label.copyWith(color: onPrimary),
        showCheckmark: false,
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: AppColors.lavender,
        linearTrackColor: palette.surface2,
        linearMinHeight: 8,
        borderRadius: const BorderRadius.all(Radius.circular(4)),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: surface,
        modalBarrierColor: AppColors.scrim,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadii.sheet))),
        showDragHandle: true,
        dragHandleColor: palette.line,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: surface,
        indicatorColor: palette.surface2,
        surfaceTintColor: Colors.transparent,
        height: 68,
        labelTextStyle: WidgetStatePropertyAll(AppTypography.overline.copyWith(letterSpacing: 0, color: onSurface)),
        iconTheme: WidgetStateProperty.resolveWith(
          (states) => IconThemeData(color: states.contains(WidgetState.selected) ? onSurface : palette.muted),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: surface,
        contentTextStyle: AppTypography.body.copyWith(color: onSurface),
        shape: RoundedRectangleBorder(
          borderRadius: const BorderRadius.all(Radius.circular(AppRadii.lg)),
          side: BorderSide(color: palette.line, width: AppSizes.borderWidth),
        ),
      ),
    );
  }
}
