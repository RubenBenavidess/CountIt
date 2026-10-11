import 'dart:async';

import '../../data/repositories/auth_repository.dart';
import '../config/app_config.dart';
import '../errors/app_failure.dart';
import '../logging/app_logger.dart';

/// A Supabase Auth e-mail link opened in the app (CountIt-Backend-Dev
/// `docs/API.md`, deep links). The backend sends implicit-flow links: tokens
/// or the error travel in the fragment (`#access_token=…&type=recovery`,
/// `#error=access_denied&error_code=otp_expired`).
///
/// Only verified Android App Links on [AppConfig.authLinkHost] are accepted
/// (COU-62, COU-109): a custom scheme could be registered by another app and
/// intercept the recovery token, so `countit://` is no longer handled.
sealed class AuthLink {
  const AuthLink();

  /// Parses `https://<host>/auth/<action>` (optionally with a trailing `/`);
  /// null for any other scheme, host, port, user info or path.
  static AuthLink? parse(Uri uri, {String host = AppConfig.authLinkHost}) {
    if (uri.scheme != 'https' ||
        uri.userInfo.isNotEmpty ||
        uri.hasPort ||
        uri.host.toLowerCase() != host.toLowerCase()) {
      return null;
    }
    final params = {...uri.queryParameters, ..._fragmentParameters(uri)};
    final failed = params.containsKey('error') || params.containsKey('error_code');
    return switch (uri.path) {
      '/auth/confirmed' || '/auth/confirmed/' => EmailConfirmedLink(expired: failed),
      '/auth/reset-password' ||
      '/auth/reset-password/' => PasswordResetLink(uri, expired: failed || !params.containsKey('access_token')),
      _ => null,
    };
  }

  static Map<String, String> _fragmentParameters(Uri uri) {
    if (uri.fragment.isEmpty) return const {};
    try {
      return Uri.splitQueryString(uri.fragment);
    } on FormatException {
      return const {};
    }
  }
}

/// `https://<host>/auth/confirmed`: the e-mail is confirmed (or the link expired).
/// The app does not sign in from it: the user logs in through the Edge Function.
class EmailConfirmedLink extends AuthLink {
  const EmailConfirmedLink({required this.expired});

  final bool expired;
}

/// `https://<host>/auth/reset-password`: carries a recovery session.
class PasswordResetLink extends AuthLink {
  const PasswordResetLink(this.uri, {required this.expired});

  final Uri uri;
  final bool expired;
}

/// Where the app goes after handling a link.
enum AuthLinkDestination { emailConfirmed, emailLinkExpired, resetPassword, resetLinkExpired }

/// Turns incoming links into navigation. Kept free of Flutter and plugins so
/// it is unit-tested; `main.dart` feeds it from `app_links`.
class AuthLinkHandler {
  AuthLinkHandler({required this.auth, required this.navigate});

  final AuthRepository auth;
  final void Function(AuthLinkDestination destination) navigate;
  StreamSubscription<Uri>? _subscription;
  Uri? _last;

  /// Handles the link that cold-started the app, then every later one.
  Future<void> listen({required Future<Uri?> initial, required Stream<Uri> links}) async {
    _subscription = links.listen(handle);
    final first = await initial;
    if (first != null) await handle(first);
  }

  Future<void> handle(Uri uri) async {
    // Some platforms deliver the cold-start link both as initial and on the stream.
    if (uri == _last) return;
    _last = uri;
    final link = AuthLink.parse(uri);
    switch (link) {
      case null:
        AppLogger.debug('ignored deep link ${uri.scheme}://${uri.host}${uri.path}');
      case EmailConfirmedLink(:final expired):
        navigate(expired ? AuthLinkDestination.emailLinkExpired : AuthLinkDestination.emailConfirmed);
      case PasswordResetLink(expired: true):
        navigate(AuthLinkDestination.resetLinkExpired);
      case PasswordResetLink(:final uri):
        try {
          // Emits passwordRecovery: the session layer and router take over.
          await auth.recoverSession(uri);
          navigate(AuthLinkDestination.resetPassword);
        } on AppFailure {
          navigate(AuthLinkDestination.resetLinkExpired);
        }
    }
  }

  Future<void> dispose() async => _subscription?.cancel();
}
