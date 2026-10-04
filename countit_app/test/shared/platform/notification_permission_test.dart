import 'package:countit_app/shared/platform/notification_permission.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const permission = PlatformNotificationPermission();
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    messenger.setMockMethodCallHandler(PlatformNotificationPermission.channel, null);
  });

  test('parse: native answers; anything else is unsupported', () {
    expect(PlatformNotificationPermission.parse('granted'), NotificationPermissionStatus.granted);
    expect(PlatformNotificationPermission.parse('denied'), NotificationPermissionStatus.denied);
    expect(PlatformNotificationPermission.parse('notDetermined'), NotificationPermissionStatus.notDetermined);
    expect(PlatformNotificationPermission.parse('maybe'), NotificationPermissionStatus.unsupported);
    expect(PlatformNotificationPermission.parse(null), NotificationPermissionStatus.unsupported);
  });

  test('Android: status, request and settings through the channel', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    final calls = <String>[];
    messenger.setMockMethodCallHandler(PlatformNotificationPermission.channel, (call) async {
      calls.add(call.method);
      return switch (call.method) {
        'status' => 'notDetermined',
        'request' => 'granted',
        'openSettings' => true,
        _ => null,
      };
    });
    expect(await permission.status(), NotificationPermissionStatus.notDetermined);
    expect(await permission.request(), NotificationPermissionStatus.granted);
    expect(await permission.openSettings(), isTrue);
    expect(calls, ['status', 'request', 'openSettings']);
  });

  test('a native error or a missing channel is unsupported, never a crash', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    messenger.setMockMethodCallHandler(
      PlatformNotificationPermission.channel,
      (call) async => throw PlatformException(code: 'busy'),
    );
    expect(await permission.request(), NotificationPermissionStatus.unsupported);
    messenger.setMockMethodCallHandler(PlatformNotificationPermission.channel, null);
    expect(await permission.status(), NotificationPermissionStatus.unsupported);
  });

  test('iOS (until firebase_messaging asks): unsupported', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    expect(await permission.status(), NotificationPermissionStatus.unsupported);
    expect(await permission.openSettings(), isFalse);
  });
}
