import 'package:flutter/material.dart';

import '../../app/theme/tokens.dart';

/// «Count It!» wordmark: «It!» in Lavender Grey.
class Wordmark extends StatelessWidget {
  const Wordmark({super.key, this.size = 26});

  final double size;

  @override
  Widget build(BuildContext context) {
    final base = TextStyle(
      fontFamily: AppTypography.family,
      fontSize: size,
      fontWeight: FontWeight.w800,
      letterSpacing: -0.5,
      height: 1,
      color: Theme.of(context).colorScheme.onSurface,
    );
    return Semantics(
      label: 'Count It!',
      excludeSemantics: true,
      child: Text.rich(
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
    );
  }
}
