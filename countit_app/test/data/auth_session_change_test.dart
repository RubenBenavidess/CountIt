import 'package:countit_app/data/repositories/auth_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  const user = User(id: 'u1', appMetadata: {}, userMetadata: {}, aud: 'authenticated', createdAt: '2026-10-04');
  final session = Session(accessToken: 'token', tokenType: 'bearer', user: user);

  SessionChange map(AuthChangeEvent event, {Session? withSession}) =>
      SupabaseAuthRepository.sessionChangeFor(AuthState(event, withSession));

  group('sessionChangeFor', () {
    test('adopting an Edge Function login (setSession → tokenRefreshed) signs in', () {
      expect(map(AuthChangeEvent.tokenRefreshed, withSession: session), SessionChange.signedIn);
    });

    test('restored and fresh sessions sign in', () {
      expect(map(AuthChangeEvent.initialSession, withSession: session), SessionChange.signedIn);
      expect(map(AuthChangeEvent.signedIn, withSession: session), SessionChange.signedIn);
    });

    test('no session means signed out', () {
      expect(map(AuthChangeEvent.initialSession), SessionChange.signedOut);
      expect(map(AuthChangeEvent.signedOut), SessionChange.signedOut);
    });

    test('recovery and other events keep their meaning', () {
      expect(map(AuthChangeEvent.passwordRecovery, withSession: session), SessionChange.passwordRecovery);
      expect(map(AuthChangeEvent.userUpdated, withSession: session), SessionChange.updated);
      expect(map(AuthChangeEvent.tokenRefreshed), SessionChange.updated);
    });
  });
}
