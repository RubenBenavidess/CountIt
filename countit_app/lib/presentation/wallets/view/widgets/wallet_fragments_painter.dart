import 'dart:math' as math;

import 'package:flutter/rendering.dart';

import 'wallet_colors.dart';

/// «Fragmentos» of the wallet card (COU-170): overlapping geometric shapes in
/// tones of the bank colour, drawn over the card background.
///
/// Shapes are laid out relative to the card size, so the composition is the
/// same on a phone list card and on the larger detail header. Wrap the card in
/// a [RepaintBoundary]: the painter only repaints when the colours change.
class WalletFragmentsPainter extends CustomPainter {
  const WalletFragmentsPainter(this.colors);

  final WalletColors colors;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final tones = colors.tones;
    final paint = Paint()..isAntiAlias = true;

    canvas.drawRect(Offset.zero & size, paint..color = colors.base);

    // Large disc leaving the top-right corner.
    paint.color = tones[0].withValues(alpha: 0.55);
    canvas.drawCircle(Offset(w * 0.92, h * 0.05), h * 0.62, paint);

    // Shard crossing the card diagonally.
    paint.color = tones[1].withValues(alpha: 0.6);
    canvas.drawPath(
      Path()
        ..moveTo(w * 0.42, h)
        ..lineTo(w * 0.78, h * 0.18)
        ..lineTo(w * 1.02, h * 0.42)
        ..lineTo(w * 0.86, h)
        ..close(),
      paint,
    );

    // Rotated rounded square in the bottom-left corner.
    paint.color = tones[3].withValues(alpha: 0.45);
    canvas
      ..save()
      ..translate(w * 0.1, h * 0.98)
      ..rotate(math.pi / 5);
    final side = h * 0.55;
    canvas
      ..drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(center: Offset.zero, width: side, height: side),
          Radius.circular(side * 0.18),
        ),
        paint,
      )
      ..restore();

    // Small triangle and dot as accents.
    paint.color = tones[2].withValues(alpha: 0.5);
    canvas.drawPath(
      Path()
        ..moveTo(w * 0.6, h * 0.02)
        ..lineTo(w * 0.7, h * 0.24)
        ..lineTo(w * 0.52, h * 0.2)
        ..close(),
      paint,
    );
    paint.color = tones[0].withValues(alpha: 0.35);
    canvas.drawCircle(Offset(w * 0.34, h * 0.86), h * 0.07, paint);
  }

  @override
  bool shouldRepaint(WalletFragmentsPainter oldDelegate) => oldDelegate.colors != colors;
}
