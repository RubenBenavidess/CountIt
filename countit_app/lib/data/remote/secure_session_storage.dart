import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Persists the Supabase session in the platform keystore (Android Keystore /
/// iOS Keychain) instead of shared preferences (COU-19, Q2 · COU-107).
class SecureSessionStorage extends LocalStorage {
  SecureSessionStorage({FlutterSecureStorage? storage}) : _storage = storage ?? const FlutterSecureStorage();

  static const key = 'countit.supabase.session';

  final FlutterSecureStorage _storage;

  @override
  Future<void> initialize() async {}

  @override
  Future<bool> hasAccessToken() => _storage.containsKey(key: key);

  @override
  Future<String?> accessToken() => _storage.read(key: key);

  @override
  Future<void> persistSession(String persistSessionString) => _storage.write(key: key, value: persistSessionString);

  @override
  Future<void> removePersistedSession() => _storage.delete(key: key);
}
