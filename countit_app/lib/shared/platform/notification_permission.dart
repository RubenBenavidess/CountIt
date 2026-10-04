import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

enum NotificationPermissionStatus {
  granted,

  /// Refused (or switched off in the system settings): only Settings can change it.
  denied,

  /// Never asked: the system dialog can still be shown (Android 13+).
  notDetermined,

  /// This platform has no implementation yet (iOS until Firebase, tests).
  unsupported,
}

/// Permission to show notifications (COU-175). Asked at a meaningful moment
/// (the inbox), never at start-up.
abstract interface class NotificationPermission {
  Future<NotificationPermissionStatus> status();

  /// Shows the system dialog when it still can; returns the resulting status.
  Future<NotificationPermissionStatus> request();

  /// Opens the app's notification settings; false when it could not.
  Future<bool> openSettings();
}

/// Android: `ec.countit.app/notifications` in MainActivity (POST_NOTIFICATIONS
/// on Android 13+, the system switch before). iOS asks through
/// `firebase_messaging` once it is configured (docs/PUSH.md): until then it
/// reports [NotificationPermissionStatus.unsupported].
class PlatformNotificationPermission implements NotificationPermission {
  const PlatformNotificationPermission();

  static const channel = MethodChannel('ec.countit.app/notifications');

  @override
  Future<NotificationPermissionStatus> status() => _call('status');

  @override
  Future<NotificationPermissionStatus> request() => _call('request');

  @override
  Future<bool> openSettings() async {
    if (defaultTargetPlatform != TargetPlatform.android) return false;
    try {
      return await channel.invokeMethod<bool>('openSettings') ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  Future<NotificationPermissionStatus> _call(String method) async {
    if (defaultTargetPlatform != TargetPlatform.android) return NotificationPermissionStatus.unsupported;
    try {
      return parse(await channel.invokeMethod<String>(method));
    } on PlatformException {
      return NotificationPermissionStatus.unsupported;
    } on MissingPluginException {
      return NotificationPermissionStatus.unsupported;
    }
  }

  /// Native answer → status; anything unexpected is [NotificationPermissionStatus.unsupported].
  static NotificationPermissionStatus parse(String? value) => switch (value) {
    'granted' => NotificationPermissionStatus.granted,
    'denied' => NotificationPermissionStatus.denied,
    'notDetermined' => NotificationPermissionStatus.notDetermined,
    _ => NotificationPermissionStatus.unsupported,
  };
}
