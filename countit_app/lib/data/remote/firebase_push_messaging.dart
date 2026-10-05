import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

import '../../app/logging/app_logger.dart';
import '../../app/push/push_messaging.dart';

/// [PushMessaging] over Firebase Cloud Messaging (COU-28/COU-103).
///
/// Built only by [initPushMessaging] after `Firebase.initializeApp()`
/// succeeded. Never logs tokens or message contents.
class FirebasePushMessaging implements PushMessaging {
  FirebasePushMessaging(this._fcm);

  final FirebaseMessaging _fcm;

  @override
  bool get isAvailable => true;

  @override
  String? get platform => switch (defaultTargetPlatform) {
    TargetPlatform.android => 'android',
    TargetPlatform.iOS => 'ios',
    _ => null,
  };

  @override
  Future<String?> getToken() => _fcm.getToken();

  @override
  Stream<String> get onTokenRefresh => _fcm.onTokenRefresh;

  @override
  Future<void> deleteToken() => _fcm.deleteToken();

  @override
  Stream<PushMessage> get foregroundMessages => FirebaseMessaging.onMessage.map(toPushMessage);

  @override
  Stream<PushMessage> get openedMessages => FirebaseMessaging.onMessageOpenedApp.map(toPushMessage);

  @override
  Future<PushMessage?> initialMessage() async {
    final message = await _fcm.getInitialMessage();
    return message == null ? null : toPushMessage(message);
  }

  @visibleForTesting
  static PushMessage toPushMessage(RemoteMessage message) => PushMessage(
    title: message.notification?.title,
    body: message.notification?.body,
    data: Map.unmodifiable(message.data),
  );
}

/// Starts Firebase and returns the FCM-backed [PushMessaging], or
/// [NoopPushMessaging] when Firebase is not configured for this build (no
/// `google-services.json` for the flavor, unsupported platform) or fails to
/// start: push is optional, the app never crashes for it (docs/PUSH.md).
Future<PushMessaging> initPushMessaging({
  Future<void> Function()? initializeFirebase,
  PushMessaging Function()? createFirebase,
  bool? supported,
  Duration timeout = const Duration(seconds: 5),
}) async {
  final isSupported =
      supported ??
      (!kIsWeb && (defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS));
  if (!isSupported) return const NoopPushMessaging();
  try {
    await (initializeFirebase ?? _initializeFirebase)().timeout(timeout);
    return (createFirebase ?? () => FirebasePushMessaging(FirebaseMessaging.instance))();
  } catch (e) {
    // Expected for flavors without Firebase config; only the type is logged.
    AppLogger.warning('push disabled: ${e.runtimeType}');
    return const NoopPushMessaging();
  }
}

Future<void> _initializeFirebase() async {
  await Firebase.initializeApp();
  // iOS: the app shows foreground pushes itself (PushNoticeHost).
  await FirebaseMessaging.instance.setForegroundNotificationPresentationOptions(
    alert: false,
    badge: true,
    sound: false,
  );
}
