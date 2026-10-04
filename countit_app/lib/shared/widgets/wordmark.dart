import 'package:flutter/material.dart';

import '../../app/theme/tokens.dart';

/// «Count It!» brand lockup: the wordmark (with «It!» in Lavender Grey) and
/// the logo on its right. The logo's «C» is light, so light theme uses a dark variant.
class Wordmark extends StatelessWidget {
  const Wordmark({super.key, this.size = 26});

  /// Font size of the text; the logo scales with it.
  final double size;

  static const darkBackgroundLogo = 'assets/brand/logo_dark.png';
  static const lightBackgroundLogo = 'assets/brand/logo_light.png';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final base = TextStyle(
      fontFamily: AppTypography.family,
      fontSize: size,
      fontWeight: FontWeight.w800,
      letterSpacing: -0.5,
      height: 1,
      color: theme.colorScheme.onSurface,
    );
    return Semantics(
      label: 'Count It!',
      excludeSemantics: true,
      // Never overflow narrow slots (app bar titles, the privacy curtain).
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          spacing: size * 0.4,
          children: [
            Text.rich(
              TextSpan(
                text: 'Count ',
                style: base,
                children: const [
                  TextSpan(
                    text: 'It!',
                    style: TextStyle(color: AppColors.lavender),
                  ),
                ],
              ),
            ),
            Image.asset(
              theme.brightness == Brightness.dark ? darkBackgroundLogo : lightBackgroundLogo,
              height: size * 1.3,
              filterQuality: FilterQuality.medium,
            ),
          ],
        ),
      ),
    );
  }
}
