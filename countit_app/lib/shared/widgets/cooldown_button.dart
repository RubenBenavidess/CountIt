import 'dart:async';

import 'package:clock/clock.dart';
import 'package:flutter/material.dart';

import 'app_button.dart';

/// [AppButton] that stays disabled until [until] (429 `Retry-After`, COU-63)
/// showing the remaining time. Only this widget rebuilds every second; the
/// form around it does not.
class CooldownButton extends StatefulWidget {
  const CooldownButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.until,
    this.loading = false,
    this.variant = AppButtonVariant.primary,
  });

  final String label;
  final VoidCallback? onPressed;
  final DateTime? until;
  final bool loading;
  final AppButtonVariant variant;

  /// `0:42`, `12:05`.
  static String format(Duration remaining) {
    final seconds = remaining.inSeconds;
    return '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';
  }

  @override
  State<CooldownButton> createState() => _CooldownButtonState();
}

class _CooldownButtonState extends State<CooldownButton> {
  Timer? _timer;

  Duration get _remaining {
    final until = widget.until;
    if (until == null) return Duration.zero;
    // `clock` follows the fake time of widget tests.
    final left = until.difference(clock.now());
    // Round up so the button never shows 0:00 while still blocked.
    return left.isNegative ? Duration.zero : Duration(seconds: (left.inMilliseconds / 1000).ceil());
  }

  @override
  void initState() {
    super.initState();
    _schedule();
  }

  @override
  void didUpdateWidget(CooldownButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.until != widget.until) _schedule();
  }

  void _schedule() {
    _timer?.cancel();
    if (_remaining == Duration.zero) return;
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_remaining == Duration.zero) timer.cancel();
      setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final remaining = _remaining;
    final blocked = remaining > Duration.zero;
    return AppButton(
      label: blocked ? 'Espera ${CooldownButton.format(remaining)}' : widget.label,
      variant: widget.variant,
      loading: widget.loading,
      onPressed: blocked ? null : widget.onPressed,
    );
  }
}
