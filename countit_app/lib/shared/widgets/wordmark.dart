import 'package:flutter/material.dart';

import '../../app/theme/tokens.dart';

/// «Count It!» brand lockup: the wordmark (with «It!» in Lavender Grey) and
/// the logo. In headers ([spread], default) the text sits on the left and the
/// logo on the right edge; centred places (splash, privacy curtain) keep them
/// together. The logo's «C» is light, so light theme uses a dark variant.
class Wordmark extends StatelessWidget {
  const Wordmark({super.key, this.size = 26, this.spread = true});

  /// Font size of the text; the logo scales with it.
  final double size;

  /// Text left and logo right across the available width.
  final bool spread;

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
    final text = Text.rich(
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
      maxLines: 1,
      overflow: TextOverflow.fade,
      softWrap: false,
    );
    final logo = Image.asset(
      theme.brightness == Brightness.dark ? darkBackgroundLogo : lightBackgroundLogo,
      height: size * 1.3,
      filterQuality: FilterQuality.medium,
    );
    return Semantics(
      label: 'Count It!',
      excludeSemantics: true,
      child: spread
          ? Row(
              spacing: size * 0.4,
              children: [
                Expanded(child: text),
                logo,
              ],
            )
          // Never overflow narrow centred slots.
          : FittedBox(
              fit: BoxFit.scaleDown,
              child: Row(mainAxisSize: MainAxisSize.min, spacing: size * 0.4, children: [text, logo]),
            ),
    );
  }
}
