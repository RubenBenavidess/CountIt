import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../../app/logging/app_logger.dart';
import '../../app/theme/tokens.dart';
import 'wordmark.dart';

/// Blocks screenshots and screen recording while [child] is on screen
/// (Android `FLAG_SECURE`; COU-115). Wrap screens that show passwords or
/// financial data. Nested or overlapping uses are reference-counted.
class SecureScreen extends StatefulWidget {
  const SecureScreen({super.key, required this.child});

  final Widget child;

  static const channel = MethodChannel('ec.countit.app/secure_screen');
  static int _active = 0;

  @visibleForTesting
  static int get activeCount => _active;

  static Future<void> _call(String method) async {
    if (defaultTargetPlatform != TargetPlatform.android) return;
    try {
      await channel.invokeMethod<void>(method);
    } on PlatformException catch (e) {
      AppLogger.warning('secure_screen $method failed: ${e.code}');
    } on MissingPluginException {
      // Widget tests and platforms without the channel.
    }
  }

  @override
  State<SecureScreen> createState() => _SecureScreenState();
}

class _SecureScreenState extends State<SecureScreen> {
  @override
  void initState() {
    super.initState();
    if (SecureScreen._active++ == 0) unawaited(SecureScreen._call('enable'));
  }

  @override
  void dispose() {
    if (--SecureScreen._active == 0) unawaited(SecureScreen._call('disable'));
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// Covers the whole app with the brand while it is not in the foreground, so
/// the app-switcher snapshot never shows balances (both platforms; COU-115).
class PrivacyCurtain extends StatefulWidget {
  const PrivacyCurtain({super.key, required this.child});

  final Widget child;

  @override
  State<PrivacyCurtain> createState() => _PrivacyCurtainState();
}

class _PrivacyCurtainState extends State<PrivacyCurtain> with WidgetsBindingObserver {
  bool _covered = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final covered = state != AppLifecycleState.resumed;
    if (covered != _covered) setState(() => _covered = covered);
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      textDirection: TextDirection.ltr,
      children: [
        widget.child,
        if (_covered)
          const Positioned.fill(
            child: ColoredBox(
              color: AppColors.ink,
              child: Center(child: Wordmark(size: 36)),
            ),
          ),
      ],
    );
  }
}
