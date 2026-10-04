import 'dart:async';
import 'dart:io';

import 'package:countit_app/app/errors/app_failure.dart';
import 'package:countit_app/app/errors/error_mapper.dart';
import 'package:countit_app/data/remote/edge_function_exception.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  group('RPC / views (PostgrestException PT<status> + hint)', () {
    test('quota exceeded → conflict with the backend message and key', () {
      final f = ErrorMapper.map(
        const PostgrestException(
          code: 'PT409',
          message: 'Alcanzaste el límite de billeteras de tu plan',
          hint: 'wallet_limit_exceeded',
        ),
      );
      expect(f.kind, FailureKind.conflict);
      expect(f.status, 409);
      expect(f.key, 'wallet_limit_exceeded');
      expect(f.message, 'Alcanzaste el límite de billeteras de tu plan');
    });

    test('reauth_required and feature_not_in_plan win over the 403 status', () {
      expect(
        ErrorMapper.map(
          const PostgrestException(code: 'PT403', message: 'Confirma tu contraseña', hint: 'reauth_required'),
        ).kind,
        FailureKind.reauthRequired,
      );
      expect(
        ErrorMapper.map(const PostgrestException(code: 'PT403', message: 'x', hint: 'feature_not_in_plan')).kind,
        FailureKind.featureNotInPlan,
      );
      expect(
        ErrorMapper.map(const PostgrestException(code: 'PT403', message: 'x', hint: 'other')).kind,
        FailureKind.forbidden,
      );
    });

    test('session_revoked and expired JWT end the session', () {
      final revoked = ErrorMapper.map(
        const PostgrestException(code: 'PT401', message: 'Tu sesión ya no es válida', hint: 'session_revoked'),
      );
      expect(revoked.endsSession, isTrue);
      final expired = ErrorMapper.map(const PostgrestException(code: 'PGRST303', message: 'JWT expired'));
      expect(expired.kind, FailureKind.unauthenticated);
      expect(expired.message, ErrorMapper.messages['not_authenticated']);
    });

    test('validation and not found', () {
      expect(
        ErrorMapper.map(const PostgrestException(code: 'PT400', message: 'Monto inválido', hint: 'invalid_amount'))
            .kind,
        FailureKind.validation,
      );
      expect(
        ErrorMapper.map(
          const PostgrestException(code: 'PT404', message: 'Billetera no encontrada', hint: 'wallet_not_found'),
        ).kind,
        FailureKind.notFound,
      );
    });

    test('unknown database errors never leak their text', () {
      final f = ErrorMapper.map(const PostgrestException(code: 'XX000', message: 'internal: relation foo'));
      expect(f.kind, FailureKind.server);
      expect(f.message, ErrorMapper.genericMessage);
    });
  });

  group('Edge Functions (FunctionException)', () {
    test('field errors and Spanish message', () {
      final f = ErrorMapper.map(
        const FunctionException(
          status: 400,
          details: {
            'success': false,
            'error': 'Errores de validación',
            'code': 'validation_error',
            'validationErrors': [
              {'field': 'email', 'message': 'El correo electrónico es requerido'},
            ],
          },
        ),
      );
      expect(f.kind, FailureKind.validation);
      expect(f.key, 'validation_error');
      expect(f.fieldErrors, {'email': 'El correo electrónico es requerido'});
    });

    test('invalid credentials, locked account and rate limit', () {
      final creds = ErrorMapper.map(
        const FunctionException(
          status: 401,
          details: {'error': 'Credenciales inválidas', 'code': 'invalid_credentials'},
        ),
      );
      expect(creds.kind, FailureKind.invalidCredentials);
      expect(creds.endsSession, isFalse, reason: 'a failed login is not a closed session');
      expect(creds.message, 'Credenciales inválidas');
      expect(
        ErrorMapper.map(const FunctionException(status: 423, details: {'code': 'account_locked'})).kind,
        FailureKind.locked,
      );
      final limited = ErrorMapper.map(const FunctionException(status: 429, details: null));
      expect(limited.kind, FailureKind.rateLimited);
      expect(limited.message, isNotEmpty);
    });

    test('wrong password in reauthenticate keeps the session (audit A1)', () {
      final f = ErrorMapper.map(
        const FunctionException(status: 401, details: {'error': 'Contraseña incorrecta', 'code': 'invalid_password'}),
      );
      expect(f.kind, FailureKind.invalidCredentials);
      expect(f.endsSession, isFalse);
    });

    test('a missing or expired token in an Edge Function does end the session', () {
      for (final code in ['missing_token', 'invalid_token']) {
        final f = ErrorMapper.map(FunctionException(status: 401, details: {'code': code}));
        expect(f.endsSession, isTrue, reason: code);
      }
    });

    test('5xx shows the generic message even if the body has text', () {
      final f = ErrorMapper.map(
        const FunctionException(status: 500, details: {'error': 'Error de base de datos', 'code': 'database_error'}),
      );
      expect(f.kind, FailureKind.server);
      expect(f.message, ErrorMapper.genericMessage);
    });
  });

  test('Auth errors use the Spanish table', () {
    final f = ErrorMapper.map(
      const AuthException('Email not confirmed', statusCode: '400', code: 'email_not_confirmed'),
    );
    expect(f.key, 'email_not_confirmed');
    expect(f.message, ErrorMapper.messages['email_not_confirmed']);
  });

  test('network problems', () {
    for (final e in [const SocketException('down'), TimeoutException('slow')]) {
      expect(ErrorMapper.map(e).kind, FailureKind.network);
    }
  });

  test('an AppFailure passes through untouched', () {
    const f = AppFailure(kind: FailureKind.notFound, message: 'x');
    expect(ErrorMapper.map(f), same(f));
  });

  group('Edge Functions (own HTTP client, COU-63)', () {
    test('429 carries Retry-After to the UI', () {
      final f = ErrorMapper.map(
        const EdgeFunctionException(
          status: 429,
          body: {'error': 'Demasiados intentos', 'code': 'rate_limited'},
          retryAfter: Duration(seconds: 900),
        ),
      );
      expect(f.kind, FailureKind.rateLimited);
      expect(f.retryAfter, const Duration(seconds: 900));
      expect(f.message, 'Demasiados intentos');
    });

    test('validationErrors become per-field messages', () {
      final f = ErrorMapper.map(
        const EdgeFunctionException(
          status: 400,
          body: {
            'code': 'validation_error',
            'error': 'Errores de validación',
            'validationErrors': [
              {'field': 'username', 'message': 'El nombre de usuario debe tener al menos 5 caracteres'},
            ],
          },
        ),
      );
      expect(f.kind, FailureKind.validation);
      expect(f.fieldErrors['username'], 'El nombre de usuario debe tener al menos 5 caracteres');
    });

    test('captcha_failed has a Spanish fallback', () {
      final f = ErrorMapper.map(const EdgeFunctionException(status: 400, body: {'code': 'captcha_failed'}));
      expect(f.message, ErrorMapper.messages['captcha_failed']);
    });

    test('Retry-After parsing', () {
      expect(EdgeFunctionException.parseRetryAfter('42'), const Duration(seconds: 42));
      expect(EdgeFunctionException.parseRetryAfter(' 7 '), const Duration(seconds: 7));
      expect(EdgeFunctionException.parseRetryAfter('0'), isNull);
      expect(EdgeFunctionException.parseRetryAfter('Wed, 21 Oct 2026 07:28:00 GMT'), isNull);
      expect(EdgeFunctionException.parseRetryAfter(null), isNull);
    });

    test('a dropped connection is a network failure', () {
      expect(ErrorMapper.map(http.ClientException('Connection reset')).kind, FailureKind.network);
    });
  });

  group('Supabase Auth with the recovery session', () {
    test('same or weak password and expired links get Spanish messages', () {
      expect(
        ErrorMapper.map(
          const AuthException('New password should be different', statusCode: '422', code: 'same_password'),
        ).message,
        'La nueva contraseña debe ser diferente a la actual',
      );
      expect(
        ErrorMapper.map(AuthWeakPasswordException(message: 'weak', statusCode: '422', reasons: const [])).kind,
        FailureKind.validation,
      );
      expect(
        ErrorMapper.map(const AuthException('expired', statusCode: '403', code: 'otp_expired')).message,
        ErrorMapper.messages['otp_expired'],
      );
    });
  });
}
