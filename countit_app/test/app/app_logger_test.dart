import 'package:countit_app/app/logging/app_logger.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AppLogger.redact (COU-112)', () {
    test('JWTs and bearer tokens', () {
      final out = AppLogger.redact('token eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxIn0.abc-DEF_123 and Bearer abc.def');
      expect(out, isNot(contains('eyJ')));
      expect(out, isNot(contains('abc.def')));
    });

    test('sensitive keys in JSON and query strings', () {
      final out = AppLogger.redact(
        '{"email":"x","password": "Secreto1", "refreshToken":"r-123"} apikey=sb_publishable_1 captchaToken=XYZ',
      );
      expect(out, isNot(contains('Secreto1')));
      expect(out, isNot(contains('r-123')));
      expect(out, isNot(contains('sb_publishable_1')));
      expect(out, isNot(contains('XYZ')));
      expect(out, contains('"password": ‹oculto›'));
    });

    test('e-mail addresses', () {
      expect(AppLogger.redact('login failed for ana@test.com'), 'login failed for ‹oculto›');
    });

    test('plain diagnostics stay readable', () {
      expect(
        AppLogger.redact('rpc create_wallet → PT409 wallet_limit_exceeded'),
        'rpc create_wallet → PT409 wallet_limit_exceeded',
      );
    });
  });
}
