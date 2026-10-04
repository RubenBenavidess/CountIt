import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../data/remote/edge_function_exception.dart';
import 'app_failure.dart';

/// Turns any error raised by the backend client into an [AppFailure]
/// following the contract in CountIt-Backend-Dev `docs/API.md`:
///
/// * RPC / views: `PostgrestException` with `code = PT<status>`, a Spanish
///   `message` and the stable key in `hint`.
/// * Edge Functions: `FunctionException` with the HTTP status and the body
///   `{success: false, error, code, validationErrors: [{field, message}]}`.
/// * Auth: `AuthException`.
///
/// Backend messages are already Spanish and safe to show; the table below only
/// fills the gaps (no message, transport errors) and never exposes internals.
abstract final class ErrorMapper {
  static const genericMessage = 'Ocurrió un error inesperado. Intenta nuevamente.';
  static const networkMessage = 'No hay conexión. Revisa tu internet e intenta nuevamente.';

  /// Spanish fallback per backend key, used when the response has no message.
  static const messages = <String, String>{
    'required_field': 'Este campo no puede quedar vacío',
    'not_authenticated': 'Debes iniciar sesión',
    'session_revoked': 'Tu sesión ya no es válida. Inicia sesión nuevamente',
    'reauth_required': 'Confirma tu contraseña para continuar',
    'feature_not_in_plan': 'Tu plan no incluye esta función',
    'invalid_credentials': 'Correo o contraseña incorrectos',
    'invalid_password': 'Contraseña incorrecta',
    'email_not_confirmed': 'Confirma tu correo para iniciar sesión',
    'account_locked': 'Tu cuenta está bloqueada temporalmente',
    'rate_limited': 'Demasiados intentos. Intenta nuevamente más tarde',
    'invitation_limit': 'Alcanzaste el máximo de invitaciones por hoy',
    'validation_error': 'Revisa los datos ingresados',
    'captcha_failed': 'La verificación anti-bots falló. Inténtalo de nuevo',
    'username_taken': 'Ese nombre de usuario ya está en uso',
    // Supabase Auth (new password with the recovery session, links).
    'weak_password': 'La contraseña no cumple los requisitos de seguridad',
    'same_password': 'La nueva contraseña debe ser diferente a la actual',
    'otp_expired': 'El enlace venció o ya fue usado. Solicita uno nuevo',
    'session_expired': 'El enlace venció. Solicita uno nuevo',
    'session_not_found': 'El enlace venció. Solicita uno nuevo',
  };

  static AppFailure map(Object error) => switch (error) {
    AppFailure() => error,
    PostgrestException() => _fromPostgrest(error),
    EdgeFunctionException() => _fromEdgeFunction(error.status, error.body, error.retryAfter),
    FunctionException() => _fromEdgeFunction(
      error.status,
      error.details is Map ? Map<String, dynamic>.from(error.details as Map) : const {},
      null,
    ),
    AuthException() => _fromAuth(error),
    SocketException() ||
    TimeoutException() ||
    HttpException() ||
    http.ClientException() => const AppFailure(kind: FailureKind.network, message: networkMessage),
    _ => const AppFailure(kind: FailureKind.server, message: genericMessage),
  };

  static AppFailure _fromPostgrest(PostgrestException e) {
    final code = e.code ?? '';
    // Business errors: PT<status> with the key in hint.
    final status = code.startsWith('PT') ? int.tryParse(code.substring(2)) : null;
    if (status != null) {
      return _build(status: status, key: e.hint, message: e.message);
    }
    // PostgREST's own errors: an expired or invalid JWT ends the session.
    if (code == 'PGRST301' || code == 'PGRST302' || code == 'PGRST303') {
      return _build(status: 401, key: 'not_authenticated');
    }
    if (code == '42501') return _build(status: 403, key: 'forbidden');
    return const AppFailure(kind: FailureKind.server, message: genericMessage);
  }

  static AppFailure _fromEdgeFunction(int status, Map<String, dynamic> body, Duration? retryAfter) {
    final fieldErrors = <String, String>{};
    final raw = body['validationErrors'];
    if (raw is List) {
      for (final item in raw.whereType<Map<dynamic, dynamic>>()) {
        final field = item['field'];
        final message = item['message'];
        if (field is String && message is String) fieldErrors[field] = message;
      }
    }
    return _build(
      status: status,
      key: body['code'] as String?,
      message: body['error'] as String?,
      fieldErrors: fieldErrors,
      retryAfter: retryAfter,
    );
  }

  static AppFailure _fromAuth(AuthException e) {
    final status = int.tryParse(e.statusCode ?? '');
    return _build(status: status ?? 400, key: e.code, message: messages[e.code]);
  }

  static AppFailure _build({
    required int status,
    String? key,
    String? message,
    Map<String, String> fieldErrors = const {},
    Duration? retryAfter,
  }) {
    final kind = _kindFor(status, key);
    final text = (message != null && message.trim().isNotEmpty)
        ? message
        : messages[key] ?? (kind == FailureKind.server ? genericMessage : messages['validation_error']!);
    return AppFailure(
      kind: kind,
      message: status >= 500 ? genericMessage : text,
      key: key,
      status: status,
      fieldErrors: fieldErrors,
      retryAfter: retryAfter,
    );
  }

  static FailureKind _kindFor(int status, String? key) {
    switch (key) {
      case 'reauth_required':
        return FailureKind.reauthRequired;
      case 'feature_not_in_plan':
        return FailureKind.featureNotInPlan;
      case 'session_revoked' || 'not_authenticated' || 'missing_token' || 'invalid_token':
        return FailureKind.unauthenticated;
      // A wrong password must never end the session (e.g. a typo in the
      // reauthenticate dialog answers 401 invalid_password).
      case 'invalid_credentials' || 'invalid_password':
        return FailureKind.invalidCredentials;
    }
    return switch (status) {
      400 || 422 => FailureKind.validation,
      401 => FailureKind.unauthenticated,
      403 => FailureKind.forbidden,
      404 => FailureKind.notFound,
      409 => FailureKind.conflict,
      423 => FailureKind.locked,
      429 => FailureKind.rateLimited,
      _ => FailureKind.server,
    };
  }
}
