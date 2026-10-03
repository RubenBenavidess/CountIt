import 'package:countit_app/app/config/app_config.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AppConfig.fromValues', () {
    test('accepts a local http URL', () {
      final config = AppConfig.fromValues(env: 'local', url: 'http://10.0.2.2:54321', anonKey: 'key');
      expect(config.environment, AppEnvironment.local);
      expect(config.isProduction, isFalse);
    });

    test('requires https outside local', () {
      expect(
        () => AppConfig.fromValues(env: 'staging', url: 'http://example.supabase.co', anonKey: 'key'),
        throwsArgumentError,
      );
      final prod = AppConfig.fromValues(env: 'prod', url: 'https://example.supabase.co', anonKey: 'key');
      expect(prod.isProduction, isTrue);
    });

    test('fails fast when a define is missing', () {
      expect(() => AppConfig.fromValues(env: '', url: 'https://x.supabase.co', anonKey: 'k'), throwsStateError);
      expect(() => AppConfig.fromValues(env: 'prod', url: '', anonKey: 'k'), throwsStateError);
      expect(() => AppConfig.fromValues(env: 'prod', url: 'https://x.supabase.co', anonKey: ''), throwsStateError);
    });

    test('rejects unknown environments and relative URLs', () {
      expect(() => AppConfig.fromValues(env: 'qa', url: 'https://x.supabase.co', anonKey: 'k'), throwsArgumentError);
      expect(() => AppConfig.fromValues(env: 'local', url: 'localhost', anonKey: 'k'), throwsArgumentError);
    });
  });
}
