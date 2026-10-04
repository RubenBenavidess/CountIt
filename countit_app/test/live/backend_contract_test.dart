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
final _functionsUrl = Uri.parse('$_url/functions/v1');

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
    api = ApiClient(client, functionsUrl: _functionsUrl, deviceId: 'live-contract-test')..onSessionEnded = ended.add;
    auth = SupabaseAuthRepository(api);
    profiles = SupabaseProfileRepository(api);
  });

  test('wrong password → invalid_credentials in Spanish', () async {
    await expectLater(
      auth.login(email: _email, password: 'Wrong2026x'),
      throwsA(isA<AppFailure>().having((f) => f.key, 'key', 'invalid_credentials')),
    );
  }, skip: skip);

  test('register validation errors arrive per field (COU-105)', () async {
    await expectLater(
      auth.register(
        email: 'live-contract@example.com',
        password: 'Quito2026',
        username: 'x',
        firstName: 'Live',
        lastName: 'Contract',
      ),
      throwsA(
        isA<AppFailure>()
            .having((f) => f.kind, 'kind', FailureKind.validation)
            .having((f) => f.fieldErrors.keys, 'fields', contains('username')),
      ),
    );
  }, skip: skip);

  test('password reset request answers generically (COU-133)', () async {
    await auth.requestPasswordReset(email: 'nobody-${DateTime.now().millisecondsSinceEpoch}@example.com');
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

  test('profile update round trip and data export (COU-146, COU-148)', () async {
    final before = await profiles.fetchMyProfile();
    await profiles.updateMyProfile(
      firstName: before.firstName ?? 'Demo',
      lastName: before.lastName ?? 'Demo',
      timezone: 'Europe/Madrid',
    );
    expect((await profiles.fetchMyProfile()).timezone, 'Europe/Madrid');
    await profiles.updateMyProfile(
      firstName: before.firstName ?? 'Demo',
      lastName: before.lastName ?? 'Demo',
      timezone: before.timezone,
    );
    await expectLater(
      profiles.updateMyProfile(firstName: 'Demo', lastName: 'Demo', timezone: 'Mars/Olympus'),
      throwsA(isA<AppFailure>().having((f) => f.key, 'key', 'invalid_timezone')),
    );
    final export = await profiles.exportMyData();
    expect(export.keys, isNotEmpty);
  }, skip: skip);

  test('change password keeps this device signed in, then back (COU-142)', () async {
    const temporary = 'Contrato2026Tmp';
    expect(await auth.changePassword(currentPassword: _password, newPassword: temporary), isTrue);
    expect((await profiles.fetchMyProfile()).email, _email, reason: 'the fresh session works');
    expect(await auth.changePassword(currentPassword: temporary, newPassword: _password), isTrue);
    expect(ended, isEmpty);
  }, skip: skip);

  test('delete-account with a wrong password deletes nothing (COU-150)', () async {
    await expectLater(
      auth.deleteAccount('Wrong2026x'),
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
    final otherApi = ApiClient(other, functionsUrl: _functionsUrl, deviceId: 'live-contract-test-b')
      ..onSessionEnded = otherEnded.add;
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
