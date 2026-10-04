import '../remote/api_client.dart';

/// This installation's push token on the backend (HU-31 · COU-176…178).
/// `register_push_device` moves a token to whoever signed in last; at most
/// 10 devices per user (the least recently seen go first).
abstract interface class PushDeviceRepository {
  /// [platform]: `android` | `ios` | `web`.
  Future<void> register(String token, String platform);

  /// Call before signing out, while the session is still valid.
  Future<void> unregister(String token);
}

class SupabasePushDeviceRepository implements PushDeviceRepository {
  SupabasePushDeviceRepository(this._api);

  final ApiClient _api;

  @override
  Future<void> register(String token, String platform) =>
      _api.rpc<dynamic>('register_push_device', params: {'p_token': token, 'p_platform': platform});

  @override
  Future<void> unregister(String token) => _api.rpc<dynamic>('unregister_push_device', params: {'p_token': token});
}
