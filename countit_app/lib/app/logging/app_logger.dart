import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';

/// The only logger of the app (COU-112): nothing is written in release builds
/// and every message is redacted, so tokens, passwords, e-mails or JWTs never
/// reach the device log. Never log amounts, balances or names either: pass
/// identifiers and error keys instead.
abstract final class AppLogger {
  static const _redacted = '‹oculto›';

  static final _patterns = <RegExp>[
    // JWT (header.payload.signature).
    RegExp(r'eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+'),
    // Bearer tokens.
    RegExp(r'Bearer\s+\S+', caseSensitive: false),
    // key=value / "key": "value" for sensitive keys.
    RegExp(
      r'''("?(?:password|currentPassword|newPassword|access_?token|refresh_?token|accessToken|refreshToken|apikey|api_key|authorization|captchaToken)"?\s*[:=]\s*)("[^"]*"|[^\s,}]+)''',
      caseSensitive: false,
    ),
    // E-mail addresses.
    RegExp(r'[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}'),
  ];

  /// Redacts sensitive values; exposed for tests.
  static String redact(String message) {
    var text = message;
    for (final pattern in _patterns) {
      text = text.replaceAllMapped(
        pattern,
        (m) => m.groupCount >= 2 && m.group(1) != null ? '${m.group(1)}$_redacted' : _redacted,
      );
    }
    return text;
  }

  static void debug(String message) => _write(message, level: 500);

  static void warning(String message) => _write(message, level: 900);

  static void _write(String message, {required int level}) {
    if (!kDebugMode) return;
    developer.log(redact(message), name: 'countit', level: level);
  }
}
