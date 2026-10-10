import 'dart:math' as math;

import 'package:equatable/equatable.dart';
import 'package:flutter/painting.dart';

import '../../../../app/theme/tokens.dart';

/// How much of the app's surface ([AppColors.prussian]) is mixed into a bank
/// colour by [mutedBankAccent].
const bankAccentBlend = 0.7;

/// Saturation cap of [mutedBankAccent].
const bankAccentMaxSaturation = 0.35;

/// Lightness range of [mutedBankAccent]: always a dark surface of the app's
/// palette, so white text keeps WCAG AA on it.
const bankAccentMinLightness = 0.12;
const bankAccentMaxLightness = 0.3;

/// The bank's brand colour turned into a muted accent of the app's palette.
///
/// Bank names are shown only so users can identify their accounts; the app
/// never reproduces a bank's trade dress. The brand colour is blended heavily
/// toward the app's dark surface, desaturated and kept dark, so every card
/// looks like Count It! with only a hint of the bank's hue. Pure: the same
/// input always gives the same colour (used by cards, the bank picker and
/// the wallet form).
Color mutedBankAccent(Color brand) {
  final blended = Color.lerp(brand.withValues(alpha: 1), AppColors.prussian, bankAccentBlend)!;
  final hsl = HSLColor.fromColor(blended);
  return hsl
      .withSaturation(math.min(hsl.saturation, bankAccentMaxSaturation))
      .withLightness(hsl.lightness.clamp(bankAccentMinLightness, bankAccentMaxLightness))
      .toColor();
}

/// Colour of a bank swatch or card: [mutedBankAccent] of [bankColor], or the
/// app's default wallet colour when there is no bank colour.
Color bankAccentOf(int? bankColor) => bankColor == null ? AppColors.defaultWallet : mutedBankAccent(Color(bankColor));

/// Colours of a wallet card derived from its bank colour (COU-170).
///
/// The card background is the bank's muted accent ([mutedBankAccent]), never
/// the raw brand colour. The fragments use tones of the same hue (lighter and
/// darker), and the text switches between ink and white by contrast so it
/// stays readable. A wallet without bank (or a bank without colour) uses the
/// app's default wallet colour.
class WalletColors extends Equatable {
  const WalletColors._({required this.base, required this.tones, required this.foreground});

  factory WalletColors.of(int? bankColor) {
    final base = readable(bankAccentOf(bankColor));
    final hsl = HSLColor.fromColor(base);
    Color shade(double delta) => hsl.withLightness((hsl.lightness + delta).clamp(0.0, 1.0)).toColor();
    return WalletColors._(
      base: base,
      tones: [shade(0.16), shade(0.08), shade(-0.08), shade(-0.16)],
      foreground: isLight(base) ? AppColors.ink : AppColors.white,
    );
  }

  /// WCAG AA for normal text.
  static const minContrast = 4.5;

  /// True when ink text has more contrast than white on [color].
  static bool isLight(Color color) => contrast(color, AppColors.ink) > contrast(color, AppColors.white);

  /// WCAG contrast ratio between two colours (1..21).
  static double contrast(Color a, Color b) {
    final la = a.computeLuminance();
    final lb = b.computeLuminance();
    return (la > lb ? la + 0.05 : lb + 0.05) / (la > lb ? lb + 0.05 : la + 0.05);
  }

  /// [brand] itself when ink or white text reaches [minContrast] on it;
  /// otherwise the same hue slightly darker, so the text is always legible
  /// (a safety net: muted accents are already dark).
  static Color readable(Color brand) {
    var hsl = HSLColor.fromColor(brand);
    var color = brand;
    while (contrast(color, AppColors.ink) < minContrast &&
        contrast(color, AppColors.white) < minContrast &&
        hsl.lightness > 0) {
      hsl = hsl.withLightness((hsl.lightness - 0.02).clamp(0.0, 1.0));
      color = hsl.toColor();
    }
    return color;
  }

  /// Card background: the bank's muted accent (see [mutedBankAccent], [readable]).
  final Color base;

  /// Four tones of the same hue, lightest first, for the fragments.
  final List<Color> tones;

  /// Text and icons on [base].
  final Color foreground;

  /// Secondary text on [base].
  Color get mutedForeground => foreground.withValues(alpha: 0.78);

  /// Translucent panel behind the month figures: dark enough for the income
  /// and expense colours of the dark palette on any bank colour.
  Color get panel => AppColors.ink.withValues(alpha: 0.72);

  /// Pill behind badges («Compartida»).
  Color get chip => foreground.withValues(alpha: 0.16);

  @override
  List<Object?> get props => [base, tones, foreground];
}
