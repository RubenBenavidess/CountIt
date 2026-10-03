import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../app/config/app_config.dart';
import '../../../shared/widgets/turnstile_field.dart';

/// Captcha plumbing shared by the public auth forms (login, register,
/// password reset): token, reset after each attempt and the slot widget.
mixin CaptchaForm<T extends StatefulWidget> on State<T> {
  final captchaController = TurnstileController();
  String? captchaToken;

  late final AppConfig _config = context.read<AppConfig>();

  /// True when the form may be sent: captcha solved or not configured.
  bool get captchaReady => !_config.captchaEnabled || captchaToken != null;

  /// Tokens are single use: ask for a new one after every attempt.
  void resetCaptcha() {
    if (_config.captchaEnabled) captchaController.reset();
  }

  Widget captchaSlot() => CaptchaSlot(
    siteKey: _config.turnstileSiteKey,
    baseUrl: _config.turnstileBaseUrl,
    controller: captchaController,
    onToken: (token) => setState(() => captchaToken = token),
  );

  @override
  void dispose() {
    captchaController.dispose();
    super.dispose();
  }
}
