import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:countit_app/app/errors/app_failure.dart';
import 'package:countit_app/app/session/session_cubit.dart';
import 'package:countit_app/app/session/session_state.dart';
import 'package:countit_app/data/dtos/profile.dart';
import 'package:countit_app/data/repositories/auth_repository.dart';
import 'package:countit_app/data/repositories/profile_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockAuth extends Mock implements AuthRepository {}

class _MockProfiles extends Mock implements ProfileRepository {}

const _profile = Profile(
  userId: 'u1',
  username: 'ana',
  email: 'ana@test.com',
  role: UserRole.user,
  timezone: 'America/Guayaquil',
);
const _revoked = AppFailure(
  kind: FailureKind.unauthenticated,
  message: 'Tu sesión ya no es válida. Inicia sesión nuevamente',
  key: 'session_revoked',
  status: 401,
);

void main() {
  late _MockAuth auth;
  late _MockProfiles profiles;
  late StreamController<SessionChange> changes;

  setUp(() {
    auth = _MockAuth();
    profiles = _MockProfiles();
    changes = StreamController<SessionChange>.broadcast();
    when(() => auth.sessionChanges).thenAnswer((_) => changes.stream);
    when(() => auth.signOut()).thenAnswer((_) async {});
  });

  tearDown(() => changes.close());

  SessionCubit build() => SessionCubit(auth: auth, profiles: profiles);

  blocTest<SessionCubit, SessionState>(
    'restore without a session → unauthenticated',
    setUp: () => when(() => auth.hasSession).thenReturn(false),
    build: build,
    act: (c) => c.restore(),
    expect: () => [const SessionState.unauthenticated()],
  );

  blocTest<SessionCubit, SessionState>(
    'restore with a session → loads the profile',
    setUp: () {
      when(() => auth.hasSession).thenReturn(true);
      when(() => profiles.fetchMyProfile()).thenAnswer((_) async => _profile);
    },
    build: build,
    act: (c) => c.restore(),
    expect: () => [const SessionState.authenticated(_profile)],
  );

  blocTest<SessionCubit, SessionState>(
    'restore with a revoked session → signs out with the reason',
    setUp: () {
      when(() => auth.hasSession).thenReturn(true);
      when(() => profiles.fetchMyProfile()).thenThrow(_revoked);
    },
    build: build,
    act: (c) => c.restore(),
    expect: () => [SessionState.unauthenticated(message: _revoked.message)],
    verify: (_) => verify(() => auth.signOut()).called(1),
  );

  blocTest<SessionCubit, SessionState>(
    'offline at start-up does not trap the user on the splash',
    setUp: () {
      when(() => auth.hasSession).thenReturn(true);
      when(() => profiles.fetchMyProfile())
          .thenThrow(const AppFailure(kind: FailureKind.network, message: 'No hay conexión'));
    },
    build: build,
    act: (c) => c.restore(),
    expect: () => [const SessionState.unauthenticated(message: 'No hay conexión')],
  );

  blocTest<SessionCubit, SessionState>(
    'a 401 from any request ends the session once (COU-57)',
    build: build,
    seed: () => const SessionState.authenticated(_profile),
    act: (c) async {
      await c.sessionEnded(_revoked);
      await c.sessionEnded(_revoked);
    },
    expect: () => [SessionState.unauthenticated(message: _revoked.message)],
    verify: (_) => verify(() => auth.signOut()).called(1),
  );

  blocTest<SessionCubit, SessionState>(
    'the SDK dropping the session (e.g. refresh token revoked) signs out',
    build: build,
    seed: () => const SessionState.authenticated(_profile),
    act: (c) => changes.add(SessionChange.signedOut),
    expect: () => [const SessionState.unauthenticated()],
  );

  blocTest<SessionCubit, SessionState>(
    'explicit sign-out always ends locally, even if the server call fails',
    setUp: () =>
        when(() => auth.signOut()).thenThrow(const AppFailure(kind: FailureKind.network, message: 'No hay conexión')),
    build: build,
    seed: () => const SessionState.authenticated(_profile),
    act: (c) => c.signOut(),
    expect: () => [const SessionState.unauthenticated()],
  );

  blocTest<SessionCubit, SessionState>(
    'the reset-password link opens the recovery state, not the app',
    build: build,
    seed: () => const SessionState.unauthenticated(),
    act: (c) async {
      changes.add(SessionChange.passwordRecovery);
      await Future<void>.delayed(Duration.zero);
      // Token refreshes or a late signedIn event must not leave the recovery screen.
      changes
        ..add(SessionChange.updated)
        ..add(SessionChange.signedIn);
    },
    expect: () => [const SessionState.passwordRecovery()],
    verify: (_) => verifyNever(() => profiles.fetchMyProfile()),
  );

  blocTest<SessionCubit, SessionState>(
    'after the new password is saved the profile loads and the app opens',
    setUp: () => when(() => profiles.fetchMyProfile()).thenAnswer((_) async => _profile),
    build: build,
    seed: () => const SessionState.passwordRecovery(),
    act: (c) => c.recoveryCompleted(),
    expect: () => [const SessionState.authenticated(_profile)],
  );

  blocTest<SessionCubit, SessionState>(
    'a sign-in event loads the profile once',
    setUp: () => when(() => profiles.fetchMyProfile()).thenAnswer((_) async => _profile),
    build: build,
    seed: () => const SessionState.unauthenticated(),
    act: (c) => changes.add(SessionChange.signedIn),
    expect: () => [const SessionState.authenticated(_profile)],
  );

  group('push hooks (COU-178)', () {
    late List<String> order;

    SessionCubit withHooks() => SessionCubit(
      auth: auth,
      profiles: profiles,
      beforeSignOut: () async => order.add('unregister'),
      onSessionLost: () async => order.add('lost'),
    );

    setUp(() {
      order = [];
      when(() => auth.signOut()).thenAnswer((_) async => order.add('signOut'));
      when(() => auth.hasSession).thenReturn(true);
      when(() => profiles.fetchMyProfile()).thenAnswer((_) async => _profile);
    });

    test('signing out unregisters the device before the session is closed', () async {
      final cubit = withHooks();
      addTearDown(cubit.close);
      await cubit.restore();
      await cubit.signOut();
      expect(order, ['unregister', 'signOut']);
    });

    test('a 401 only reports the lost session (no server call is possible)', () async {
      final cubit = withHooks();
      addTearDown(cubit.close);
      await cubit.restore();
      await cubit.sessionEnded(_revoked);
      expect(order, ['lost', 'signOut']);
    });

    test('signed out by the SDK (refresh rejected): session lost', () async {
      final cubit = withHooks();
      addTearDown(cubit.close);
      await cubit.restore();
      changes.add(SessionChange.signedOut);
      await pumpEventQueue();
      expect(order, ['lost']);
    });
  });
}
