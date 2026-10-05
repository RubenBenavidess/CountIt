import 'package:countit_app/app/push/push_messaging.dart';
import 'package:countit_app/data/remote/firebase_push_messaging.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fake_push_messaging.dart';

void main() {
  group('initPushMessaging', () {
    test('falls back to the no-op when Firebase is not configured', () async {
      final messaging = await initPushMessaging(
        supported: true,
        initializeFirebase: () async =>
            throw FirebaseException(plugin: 'core', message: 'Failed to load FirebaseOptions from resource'),
        createFirebase: () => fail('must not build the FCM client without Firebase'),
      );
      expect(messaging, isA<NoopPushMessaging>());
      expect(messaging.isAvailable, isFalse);
    });

    test('falls back to the no-op when initialization never completes', () async {
      final messaging = await initPushMessaging(
        supported: true,
        initializeFirebase: () => Future.delayed(const Duration(seconds: 1)),
        createFirebase: FakePushMessaging.new,
        timeout: const Duration(milliseconds: 50),
      );
      expect(messaging, isA<NoopPushMessaging>());
    });

    test('uses the no-op on unsupported platforms without touching Firebase', () async {
      var initialized = false;
      final messaging = await initPushMessaging(supported: false, initializeFirebase: () async => initialized = true);
      expect(messaging, isA<NoopPushMessaging>());
      expect(initialized, isFalse);
    });

    test('uses the FCM client once Firebase started', () async {
      final fcm = FakePushMessaging();
      final messaging = await initPushMessaging(
        supported: true,
        initializeFirebase: () async {},
        createFirebase: () => fcm,
      );
      expect(messaging, same(fcm));
    });
  });

  test('maps a RemoteMessage to a PushMessage', () {
    const remote = RemoteMessage(
      notification: RemoteNotification(title: 'Presupuesto', body: 'Vas en 80 %'),
      data: {'kind': 'budget_warning', 'notification_id': '7'},
    );
    expect(
      FirebasePushMessaging.toPushMessage(remote),
      const PushMessage(
        title: 'Presupuesto',
        body: 'Vas en 80 %',
        data: {'kind': 'budget_warning', 'notification_id': '7'},
      ),
    );
  });
}
