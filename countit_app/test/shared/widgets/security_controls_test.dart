import 'package:countit_app/app/session/session_cubit.dart';
import 'package:countit_app/app/session/session_secure_screen.dart';
import 'package:countit_app/app/session/session_state.dart';
import 'package:countit_app/data/dtos/profile.dart';
import 'package:countit_app/data/remote/fresh_install.dart';
import 'package:countit_app/shared/widgets/secure_screen.dart';
import 'package:countit_app/shared/widgets/turnstile_field.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/mocks.dart';

class _MockPreferences extends Mock implements SharedPreferencesAsync {}

const _profile = Profile(
  userId: 'u1',
  username: 'demo_ana',
  email: 'ana@correo.ec',
  role: UserRole.user,
  timezone: 'America/Guayaquil',
);

void main() {
  group('FLAG_SECURE for the whole signed-in app (MASVS-PLATFORM)', () {
    late List<String> calls;

    setUp(() {
      calls = [];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(SecureScreen.channel, (
        call,
      ) async {
        calls.add(call.method);
        return null;
      });
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
        SecureScreen.channel,
        null,
      );
    });

    testWidgets('on while authenticated or recovering the password, off when signed out; the child stays mounted', (
      tester,
    ) async {
      final auth = MockAuthRepository();
      when(() => auth.sessionChanges).thenAnswer((_) => const Stream.empty());
      final session = SessionCubit(auth: auth, profiles: MockProfileRepository());
      addTearDown(session.close);
      final child = GlobalKey();

      await tester.pumpWidget(
        SessionSecureScreen(
          session: session,
          child: SizedBox(key: child),
        ),
      );
      expect(calls, isEmpty);
      final element = child.currentContext;

      session.emit(const SessionState.authenticated(_profile));
      await tester.pump();
      await tester.pump();
      expect(calls, ['enable']);
      expect(SecureScreen.activeCount, 1);

      session.emit(const SessionState.unauthenticated());
      await tester.pump();
      await tester.pump();
      expect(calls, ['enable', 'disable']);

      session.emit(const SessionState.passwordRecovery());
      await tester.pump();
      await tester.pump();
      expect(calls, ['enable', 'disable', 'enable']);
      expect(child.currentContext, same(element));

      await tester.pumpWidget(const SizedBox());
      expect(calls.last, 'disable');
      expect(SecureScreen.activeCount, 0);
      debugDefaultTargetPlatformOverride = null;
    });

    testWidgets('a password screen inside the signed-in app keeps the flag until both are gone', (tester) async {
      final enabled = ValueNotifier(true);
      await tester.pumpWidget(
        ValueListenableBuilder<bool>(
          valueListenable: enabled,
          builder: (context, on, _) => SecureScreen(
            enabled: on,
            child: const SecureScreen(child: SizedBox()),
          ),
        ),
      );
      expect(calls, ['enable']);
      enabled.value = false;
      await tester.pump();
      expect(calls, ['enable'], reason: 'the inner screen still holds it');
      await tester.pumpWidget(const SizedBox());
      expect(calls, ['enable', 'disable']);
      debugDefaultTargetPlatformOverride = null;
    });
  });

  group('Turnstile webview (MASVS-PLATFORM)', () {
    final base = Uri.parse('https://countit.example.ec');

    test('navigation: the page, its https origin and the Cloudflare challenge only', () {
      expect(TurnstileField.allowsNavigation('about:blank', base), isTrue);
      expect(TurnstileField.allowsNavigation('https://countit.example.ec/', base), isTrue);
      expect(TurnstileField.allowsNavigation('https://challenges.cloudflare.com/cdn-cgi/x', base), isTrue);
      expect(TurnstileField.allowsNavigation('http://challenges.cloudflare.com/', base), isFalse);
      expect(TurnstileField.allowsNavigation('http://countit.example.ec/', base), isFalse);
      expect(TurnstileField.allowsNavigation('https://evil.example/', base), isFalse);
      expect(TurnstileField.allowsNavigation('file:///data/data/ec.countit.app/x', base), isFalse);
      expect(TurnstileField.allowsNavigation('javascript:alert(1)', base), isFalse);
      expect(TurnstileField.allowsNavigation('intent://scan/#Intent;end', base), isFalse);
    });

    test('only token-shaped messages are tokens', () {
      expect(TurnstileField.isToken('0.AbC-def_123.xyz'), isTrue);
      expect(TurnstileField.isToken(''), isFalse);
      expect(TurnstileField.isToken('a b'), isFalse);
      expect(TurnstileField.isToken('<script>'), isFalse);
      expect(TurnstileField.isToken('x' * 2049), isFalse);
    });
  });

  group('FreshInstall (MASVS-STORAGE)', () {
    late _MockPreferences preferences;
    late MockSecureStorage storage;

    setUp(() {
      preferences = _MockPreferences();
      storage = MockSecureStorage();
      when(() => storage.deleteAll()).thenAnswer((_) async {});
      when(() => preferences.setBool(any(), any())).thenAnswer((_) async {});
    });

    test('first run of an installation wipes what a previous one left in the Keychain', () async {
      when(() => preferences.getBool(FreshInstall.marker)).thenAnswer((_) async => null);
      await FreshInstall.forgetPreviousInstall(preferences: preferences, storage: storage);
      verify(() => storage.deleteAll()).called(1);
      verify(() => preferences.setBool(FreshInstall.marker, true)).called(1);
    });

    test('later runs keep the session', () async {
      when(() => preferences.getBool(FreshInstall.marker)).thenAnswer((_) async => true);
      await FreshInstall.forgetPreviousInstall(preferences: preferences, storage: storage);
      verifyNever(() => storage.deleteAll());
    });

    test('a failing check never blocks start-up', () async {
      when(() => preferences.getBool(FreshInstall.marker)).thenThrow(Exception('io'));
      await FreshInstall.forgetPreviousInstall(preferences: preferences, storage: storage);
      verifyNever(() => storage.deleteAll());
    });
  });
}
