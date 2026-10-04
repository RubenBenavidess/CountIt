import 'package:flutter/painting.dart';

/// Colour palette of the design canvas «CountIt App» (Sistema de diseño):
/// Ink Black, Prussian Blue, Dusk Blue, Lavender Grey and Alabaster Grey.
abstract final class AppColors {
  static const ink = Color(0xFF0D1B2A); // background
  static const prussian = Color(0xFF1B263B); // surfaces, inputs, cards
  static const surface2 = Color(0xFF233048); // icon tiles, progress track, badges
  static const dusk = Color(0xFF415A77); // secondary action; wallet without bank
  static const lavender = Color(0xFF778DA9); // accents, focus, progress
  static const alabaster = Color(0xFFE0E1DD); // main text and primary action
  static const muted = Color(0xFFA7B4C6); // secondary text
  static const line = Color(0xFF2B3A54); // borders and dividers
  static const placeholder = Color(0xFF7F8EA5);
  static const income = Color(0xFF8FD3B6); // always with «+» sign, never colour alone
  static const expense = Color(0xFFF4A582); // always with «−» sign; also errors
  static const dangerBorder = Color(0xFF6B4A43);
  static const warnBackground = Color(0xFF4A3530);
  static const okBackground = Color(0xFF233F3A);
  static const errorBannerBorder = Color(0xFF7A4D42);
  static const errorBannerBackground = Color(0xFF2A2026);
  static const scrim = Color(0xB8050A12);
  static const white = Color(0xFFFFFFFF);

  /// Wallets without a bank use Dusk Blue (HU-08).
  static const defaultWallet = dusk;
}

/// Spacing scale (px) used by the design.
abstract final class AppSpacing {
  static const xs = 4.0;
  static const sm = 8.0;
  static const md = 12.0;
  static const lg = 16.0;
  static const xl = 20.0;
  static const xxl = 24.0;

  /// Horizontal padding of every screen.
  static const screen = 20.0;
}

/// Corner radii of the design.
abstract final class AppRadii {
  static const sm = 11.0; // segmented option
  static const md = 12.0; // icon buttons, small buttons, icon tiles
  static const lg = 14.0; // buttons, inputs, banners, segmented
  static const card = 18.0;
  static const wallet = 20.0;
  static const sheet = 24.0;
  static const pill = 999.0;
}

/// Fixed control sizes of the design (touch targets ≥ 44).
abstract final class AppSizes {
  static const button = 52.0;
  static const buttonSmall = 40.0;
  static const input = 52.0;
  static const iconButton = 44.0;
  static const chip = 36.0;
  static const borderWidth = 1.5;
}

/// Type scale of the design (Manrope).
abstract final class AppTypography {
  static const family = 'Manrope';

  static const display = TextStyle(
    fontFamily: family,
    fontSize: 44,
    fontWeight: FontWeight.w800,
    letterSpacing: -1,
    height: 1.05,
  );
  static const h1 = TextStyle(
    fontFamily: family,
    fontSize: 26,
    fontWeight: FontWeight.w800,
    letterSpacing: -0.4,
    height: 1.2,
  );
  static const title = TextStyle(fontFamily: family, fontSize: 20, fontWeight: FontWeight.w700);
  static const h2 = TextStyle(fontFamily: family, fontSize: 17, fontWeight: FontWeight.w700);
  static const body = TextStyle(fontFamily: family, fontSize: 15, fontWeight: FontWeight.w400, height: 1.5);
  static const label = TextStyle(fontFamily: family, fontSize: 14, fontWeight: FontWeight.w600);
  static const caption = TextStyle(fontFamily: family, fontSize: 13, fontWeight: FontWeight.w400, height: 1.45);
  static const overline = TextStyle(fontFamily: family, fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 0.8);
  static const button = TextStyle(fontFamily: family, fontSize: 16, fontWeight: FontWeight.w700);

  /// Amounts: tabular figures so columns of money line up.
  static const money = TextStyle(
    fontFamily: family,
    fontWeight: FontWeight.w700,
    fontFeatures: [FontFeature.tabularFigures()],
  );
}
