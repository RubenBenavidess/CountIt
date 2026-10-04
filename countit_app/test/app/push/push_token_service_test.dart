import 'package:countit_app/app/errors/app_failure.dart';
import 'package:countit_app/app/push/push_messaging.dart';
import 'package:countit_app/app/push/push_token_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../../helpers/fake_push_messaging.dart';
import '../../helpers/mocks.dart';

const _network = AppFailure(kind: FailureKind.network, message: 'Sin conexión');

void main() {
  late FakePushMessaging messaging;
  late MockPushDeviceRepository devices;
  late PushTokenService service;
  late List<String> log;

  setUp(() {
    log = [];
    messaging = FakePushMessaging();
    devices = MockPushDeviceRepository();
    when(() => devices.register(any(), any())).thenAnswer((invocation) async {
      log.add('register ${invocation.positionalArguments[0]}');
    });
    when(() => devices.unregister(any())).thenAnswer((invocation) async {
      log.add('unregister ${invocation.positionalArguments[0]}');
    });
    service = PushTokenService(messaging: messaging, devices: devices);
  });

  group('register after sign-in (COU-176) and on rotation (COU-177)', () {
    test('signing in registers the token with the platform', () async {
      await service.setUser('u1');
      verify(() => devices.register('token-1', 'android')).called(1);
      expect(service.registeredToken, 'token-1');
    });

    test('a rotated token is registered again', () async {
      await service.setUser('u1');
      messaging.refresh.add('token-2');
      await pumpEventQueue();
      verify(() => devices.register('token-2', 'android')).called(1);
      expect(service.registeredToken, 'token-2');
    });

    test('after signing out, rotations are ignored', () async {
      await service.setUser('u1');
      await service.setUser(null);
      messaging.refresh.add('token-2');
      await pumpEventQueue();
      verifyNever(() => devices.register('token-2', any()));
    });

    test('quick user changes leave a single rotation listener, for the last user', () async {
      final first = service.setUser('u1');
      await service.setUser('u2');
      await first;
      messaging.refresh.add('token-2');
      await pumpEventQueue();
      verify(() => devices.register('token-2', 'android')).called(1);

      await service.setUser(null);
      expect(messaging.refresh.hasListener, isFalse);
    });

    test('no token yet: nothing is registered', () async {
      messaging.token = null;
      await service.setUser('u1');
      verifyNever(() => devices.register(any(), any()));
    });

    test('a failed registration never reaches the user', () async {
      when(() => devices.register(any(), any())).thenThrow(_network);
      await expectLater(service.setUser('u1'), completes);
      expect(service.registeredToken, isNull);
    });

    test('push not configured (no-op): no calls at all', () async {
      final noop = PushTokenService(messaging: const NoopPushMessaging(), devices: devices);
      await noop.setUser('u1');
      await noop.signingOut();
      await noop.sessionLost();
      verifyZeroInteractions(devices);
    });
  });

  group('sign-out (COU-178)', () {
    test('unregisters while the session works, then deletes the local token', () async {
      await service.setUser('u1');
      messaging.calls.clear();
      await service.signingOut();
      expect(log, ['register token-1', 'unregister token-1']);
      expect(messaging.calls, ['deleteToken']);
      expect(service.registeredToken, isNull);
    });

    test('a failed unregister still deletes the local token', () async {
      when(() => devices.unregister(any())).thenThrow(_network);
      await service.setUser('u1');
      await expectLater(service.signingOut(), completes);
      expect(messaging.calls, contains('deleteToken'));
    });

    test('a slow backend does not hold the sign-out', () async {
      final slow = PushTokenService(messaging: messaging, devices: devices, timeout: const Duration(milliseconds: 10));
      when(() => devices.unregister(any())).thenAnswer((_) => Future<void>.delayed(const Duration(seconds: 5)));
      await slow.setUser('u1');
      await expectLater(slow.signingOut().timeout(const Duration(seconds: 1)), completes);
    });

    test('session lost (401): only the local token goes', () async {
      await service.setUser('u1');
      await service.sessionLost();
      verifyNever(() => devices.unregister(any()));
      expect(messaging.calls, contains('deleteToken'));
    });
  });
}
