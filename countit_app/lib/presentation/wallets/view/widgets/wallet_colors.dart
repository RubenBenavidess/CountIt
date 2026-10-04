import 'package:equatable/equatable.dart';
import 'package:flutter/painting.dart';

import '../../../../app/theme/tokens.dart';

/// Colours of a wallet card derived from its bank colour (COU-170).
///
/// The fragments use tones of the same hue (lighter and darker), and the text
/// switches between ink and white by contrast so it stays readable on any
/// brand colour. A wallet without bank (or a bank without colour) uses the
/// app's default wallet colour.
class WalletColors extends Equatable {
  const WalletColors._({required this.base, required this.tones, required this.foreground});

  factory WalletColors.of(int? bankColor) {
    final brand = bankColor == null ? AppColors.defaultWallet : Color(bankColor);
    final base = readable(brand);
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
  /// otherwise the same hue slightly darker (mid tones such as BanEcuador's
  /// green), so the text is always legible.
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

  /// Card background: the bank colour (see [readable]).
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
