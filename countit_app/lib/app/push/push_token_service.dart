import 'dart:async';

import '../../data/repositories/push_device_repository.dart';
import '../errors/app_failure.dart';
import '../logging/app_logger.dart';
import 'push_messaging.dart';

/// Keeps this installation's push token on the backend in step with the
/// session (HU-31):
///
/// * signed in → `register_push_device` (COU-176), again on every rotation
///   (COU-177);
/// * signing out → `unregister_push_device` while the session still works,
///   then the token is deleted locally (COU-178), so a push that was already
///   on its way to the old token fails and the backend drops it;
/// * session lost (401, revoked elsewhere) → the server call is impossible:
///   only the local token is deleted, with the same effect.
///
/// Failures never block the user (push is best effort) and tokens never
/// reach the logs.
class PushTokenService {
  PushTokenService({required this._messaging, required this._devices, Duration? timeout})
    : _timeout = timeout ?? const Duration(seconds: 5);

  final PushMessaging _messaging;
  final PushDeviceRepository _devices;
  final Duration _timeout;

  String? _userId;
  String? _registered;
  StreamSubscription<String>? _refresh;

  /// The token the backend has for this installation (tests).
  String? get registeredToken => _registered;

  /// Follows the signed-in user (null when signed out).
  Future<void> setUser(String? userId) async {
    if (userId == _userId) return;
    _userId = userId;
    await _refresh?.cancel();
    _refresh = null;
    if (userId == null || !_messaging.isAvailable || _messaging.platform == null) return;
    _refresh = _messaging.onTokenRefresh.listen((token) => unawaited(_register(userId, token)));
    try {
      final token = await _messaging.getToken();
      if (token != null) await _register(userId, token);
    } catch (_) {
      AppLogger.debug('push token unavailable');
    }
  }

  Future<void> _register(String userId, String token) async {
    if (userId != _userId || token.isEmpty) return;
    try {
      await _devices.register(token, _messaging.platform!).timeout(_timeout);
      if (userId == _userId) _registered = token;
    } on AppFailure catch (failure) {
      AppLogger.debug('push register failed key=${failure.key}');
    } on TimeoutException {
      AppLogger.debug('push register timed out');
    }
  }

  /// Before `auth.signOut()`: unregisters (bounded by the timeout) and
  /// deletes the local token. Never throws.
  Future<void> signingOut() async {
    if (!_messaging.isAvailable) return;
    final token = _registered;
    _registered = null;
    await _refresh?.cancel();
    _refresh = null;
    if (token != null) {
      try {
        await _devices.unregister(token).timeout(_timeout);
      } on AppFailure catch (failure) {
        AppLogger.debug('push unregister failed key=${failure.key}');
      } on TimeoutException {
        AppLogger.debug('push unregister timed out');
      }
    }
    await _deleteLocal();
  }

  /// The session ended without us (401): the device must stop receiving the
  /// previous user's pushes.
  Future<void> sessionLost() async {
    if (!_messaging.isAvailable) return;
    _registered = null;
    await _refresh?.cancel();
    _refresh = null;
    await _deleteLocal();
  }

  Future<void> _deleteLocal() async {
    try {
      await _messaging.deleteToken().timeout(_timeout);
    } catch (_) {
      AppLogger.debug('push token delete failed');
    }
  }
}
