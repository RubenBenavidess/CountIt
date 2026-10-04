// Live contract test against a running CountIt backend (local stack or staging).
// Skipped unless the defines are passed; never runs in CI by default:
//
//   flutter test test/live --dart-define=LIVE_API_URL=http://127.0.0.1:54321 \
//     --dart-define=LIVE_ANON_KEY=<anon key> --dart-define=LIVE_EMAIL=<demo e-mail> \
//     --dart-define=LIVE_PASSWORD=<DEMO_PASSWORD>
//
// Use a demo account (CountIt-Backend-Dev scripts/seed-demo.sh): it creates and
// deletes one wallet of its own.
@Tags(['live'])
library;

import 'package:countit_app/app/errors/app_failure.dart';
import 'package:countit_app/data/remote/api_client.dart';
import 'package:countit_app/data/repositories/auth_repository.dart';
import 'package:countit_app/data/repositories/profile_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const _url = String.fromEnvironment('LIVE_API_URL');
const _anonKey = String.fromEnvironment('LIVE_ANON_KEY');
const _email = String.fromEnvironment('LIVE_EMAIL');
const _password = String.fromEnvironment('LIVE_PASSWORD');

void main() {
  final skip = _url.isEmpty || _anonKey.isEmpty || _email.isEmpty || _password.isEmpty
      ? 'pass LIVE_API_URL, LIVE_ANON_KEY, LIVE_EMAIL and LIVE_PASSWORD to run'
      : null;

  late ApiClient api;
  late SupabaseAuthRepository auth;
  late SupabaseProfileRepository profiles;
  final ended = <AppFailure>[];

  setUpAll(() {
    if (skip != null) return;
    final client = SupabaseClient(
      _url,
      _anonKey,
      postgrestOptions: const PostgrestClientOptions(schema: 'api'),
      authOptions: const AuthClientOptions(autoRefreshToken: false),
    );
    api = ApiClient(client, deviceId: 'live-contract-test')..onSessionEnded = ended.add;
    auth = SupabaseAuthRepository(api);
    profiles = SupabaseProfileRepository(api);
  });

  test('wrong password → invalid_credentials in Spanish', () async {
    await expectLater(
      auth.login(email: _email, password: 'Wrong2026x'),
      throwsA(isA<AppFailure>().having((f) => f.key, 'key', 'invalid_credentials')),
    );
  }, skip: skip);

  test('login through the Edge Function hands the session to the SDK; profile over schema api', () async {
    await auth.login(email: _email, password: _password);
    expect(auth.hasSession, isTrue);
    final profile = await profiles.fetchMyProfile();
    expect(profile.email, _email);
    expect(profile.plan, isNotNull);
  }, skip: skip);

  test('business errors arrive as typed failures with the backend key', () async {
    await expectLater(
      api.rpc<dynamic>('create_wallet', params: {'p_name': ''}),
      throwsA(isA<AppFailure>().having((f) => f.key, 'key', 'required_field')),
    );
  }, skip: skip);

  test('destructive action: reauth_required → confirm password → retried (COU-59)', () async {
    final wallet = await api.rpc<Map<String, dynamic>>(
      'create_wallet',
      params: {'p_name': 'Contrato ${DateTime.now().millisecondsSinceEpoch % 100000}'},
    );
    var prompts = 0;
    final deleted = await api.rpc<Map<String, dynamic>>(
      'delete_wallet',
      params: {'p_wallet_id': wallet['wallet_id']},
      onReauth: () async {
        prompts++;
        await auth.reauthenticate(_password);
        return true;
      },
    );
    expect(prompts, 1);
    expect(deleted['wallet_id'], wallet['wallet_id']);
  }, skip: skip);

  test('a wrong password while reauthenticating keeps the session (audit A1)', () async {
    await expectLater(
      auth.reauthenticate('Wrong2026x'),
      throwsA(isA<AppFailure>().having((f) => f.kind, 'kind', FailureKind.invalidCredentials)),
    );
    expect(auth.hasSession, isTrue);
    expect(ended, isEmpty);
  }, skip: skip);

  test('a session closed from another device gets 401 session_revoked and the app is told (COU-57)', () async {
    // Device B signs in with its own session.
    final other = SupabaseClient(
      _url,
      _anonKey,
      postgrestOptions: const PostgrestClientOptions(schema: 'api'),
      authOptions: const AuthClientOptions(autoRefreshToken: false),
    );
    final otherEnded = <AppFailure>[];
    final otherApi = ApiClient(other, deviceId: 'live-contract-test-b')..onSessionEnded = otherEnded.add;
    await SupabaseAuthRepository(otherApi).login(email: _email, password: _password);
    await SupabaseProfileRepository(otherApi).fetchMyProfile();

    // Device A closes every session (as a password change does).
    await api.run(() => api.supabase.auth.signOut(scope: SignOutScope.global));
    expect(auth.hasSession, isFalse);

    // B still holds an unexpired JWT, but the backend rejects it.
    await expectLater(
      SupabaseProfileRepository(otherApi).fetchMyProfile(),
      throwsA(isA<AppFailure>().having((f) => f.key, 'key', 'session_revoked')),
    );
    expect(otherEnded.single.endsSession, isTrue);
  }, skip: skip);
}
