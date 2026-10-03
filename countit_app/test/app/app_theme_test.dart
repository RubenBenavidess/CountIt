import 'package:countit_app/app/theme/app_theme.dart';
import 'package:countit_app/app/theme/tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// WCAG relative-luminance contrast ratio.
double contrast(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final hi = la > lb ? la : lb;
  final lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}

void main() {
  group('dark theme follows the design canvas', () {
    final theme = AppTheme.dark;

    test('palette', () {
      expect(theme.scaffoldBackgroundColor, AppColors.ink);
      expect(theme.colorScheme.surface, AppColors.prussian);
      expect(theme.colorScheme.primary, AppColors.alabaster);
      expect(theme.extension<AppPalette>(), AppPalette.dark);
    });

    test('Manrope everywhere', () {
      expect(theme.textTheme.bodyMedium!.fontFamily, AppTypography.family);
      expect(theme.textTheme.headlineMedium!.fontWeight, FontWeight.w800);
    });

    test('buttons are 52 px with radius 14', () {
      final style = theme.filledButtonTheme.style!;
      expect(style.minimumSize!.resolve({}), const Size.fromHeight(AppSizes.button));
      final shape = style.shape!.resolve({})! as RoundedRectangleBorder;
      expect(shape.borderRadius, const BorderRadius.all(Radius.circular(AppRadii.lg)));
    });
  });

  group('text contrast (WCAG AA)', () {
    test('dark: text, secondary text and amounts on background and surfaces', () {
      for (final bg in [AppColors.ink, AppColors.prussian]) {
        expect(contrast(AppColors.alabaster, bg), greaterThanOrEqualTo(4.5));
        expect(contrast(AppColors.muted, bg), greaterThanOrEqualTo(4.5));
        expect(contrast(AppColors.income, bg), greaterThanOrEqualTo(4.5));
        expect(contrast(AppColors.expense, bg), greaterThanOrEqualTo(4.5));
      }
      expect(contrast(AppColors.ink, AppColors.alabaster), greaterThanOrEqualTo(4.5), reason: 'primary button');
    });

    test('light: semantic colours on Alabaster', () {
      for (final c in [AppPalette.light.income, AppPalette.light.expense, AppPalette.light.muted, AppColors.ink]) {
        expect(contrast(c, AppColors.alabaster), greaterThanOrEqualTo(4.5));
      }
    });
  });
}
