import 'package:supabase_flutter/supabase_flutter.dart';

import '../remote/api_client.dart';

/// The word the user types to confirm deleting the account (and the API expects).
const accountDeletionWord = 'ELIMINAR';

/// What happened to the SDK session; [SessionCubit] decides what it means.
enum SessionChange {
  signedIn,

  /// Opened from the password-reset e-mail: only a new password may be set.
  passwordRecovery,

  /// Tokens refreshed or user updated: same person, same state.
  updated,
  signedOut,
}

/// Authentication through the backend Edge Functions (rate limiting, captcha
/// and lockout live there) with the session kept by the Supabase SDK.
abstract interface class AuthRepository {
  /// True when a session (restored from secure storage or fresh) exists.
  bool get hasSession;

  /// Emits whenever the SDK session changes.
  Stream<SessionChange> get sessionChanges;

  Future<void> login({required String email, required String password, String? captchaToken});

  Future<void> register({
    required String email,
    required String password,
    required String username,
    required String firstName,
    required String lastName,
    String? captchaToken,
  });

  Future<void> requestPasswordReset({required String email, String? captchaToken});

  /// Opens the 5-minute safe mode for the current session (HU-06).
  Future<DateTime> reauthenticate(String password);

  /// Adopts the recovery session carried by `countit://auth/reset-password#…`
  /// (emits [SessionChange.passwordRecovery]). Throws when the link expired.
  Future<void> recoverSession(Uri link);

  /// Sets the password with the current (recovery) session; Auth applies its policy.
  Future<void> setNewPassword(String password);

  /// HU-04: Auth closes every session; the Edge Function returns a fresh one
  /// that replaces the local session. Returns false when no session came back
  /// (the user must sign in again).
  Future<bool> changePassword({required String currentPassword, required String newPassword});

  /// HU-30: anonymizes the account; afterwards its tokens get 401.
  Future<void> deleteAccount(String password);

  /// Local sign-out: forgets the session on this device.
  Future<void> signOut();
}

class SupabaseAuthRepository implements AuthRepository {
  SupabaseAuthRepository(this._api);

  final ApiClient _api;

  GoTrueClient get _auth => _api.supabase.auth;

  @override
  bool get hasSession => _auth.currentSession != null;

  @override
  Stream<SessionChange> get sessionChanges => _auth.onAuthStateChange.map(
    (state) => switch (state.event) {
      AuthChangeEvent.passwordRecovery => SessionChange.passwordRecovery,
      AuthChangeEvent.signedOut => SessionChange.signedOut,
      AuthChangeEvent.initialSession || AuthChangeEvent.signedIn when state.session != null => SessionChange.signedIn,
      AuthChangeEvent.initialSession || AuthChangeEvent.signedIn => SessionChange.signedOut,
      _ => SessionChange.updated,
    },
  );

  @override
  Future<void> login({required String email, required String password, String? captchaToken}) async {
    final body = await _api.invoke(
      'login',
      body: {'email': email, 'password': password, 'captchaToken': ?captchaToken},
    );
    await _adoptSession(body);
  }

  @override
  Future<void> register({
    required String email,
    required String password,
    required String username,
    required String firstName,
    required String lastName,
    String? captchaToken,
  }) async {
    await _api.invoke(
      'register',
      body: {
        'email': email,
        'password': password,
        'username': username,
        'firstName': firstName,
        'lastName': lastName,
        'captchaToken': ?captchaToken,
      },
    );
  }

  @override
  Future<void> requestPasswordReset({required String email, String? captchaToken}) async {
    await _api.invoke('request-password-reset', body: {'email': email, 'captchaToken': ?captchaToken});
  }

  @override
  Future<DateTime> reauthenticate(String password) async {
    final body = await _api.invoke('reauthenticate', body: {'password': password});
    final data = body['data'];
    final expiresAt = data is Map ? data['expiresAt'] : null;
    return expiresAt is String ? DateTime.parse(expiresAt) : DateTime.now().add(const Duration(minutes: 5));
  }

  @override
  Future<void> recoverSession(Uri link) => _api.run(() => _auth.getSessionFromUrl(link));

  @override
  Future<void> setNewPassword(String password) => _api.run(() => _auth.updateUser(UserAttributes(password: password)));

  @override
  Future<bool> changePassword({required String currentPassword, required String newPassword}) async {
    final body = await _api.invoke(
      'change-password',
      body: {'currentPassword': currentPassword, 'newPassword': newPassword},
    );
    if (body['session'] is! Map) return false;
    await _adoptSession(body);
    return true;
  }

  @override
  Future<void> deleteAccount(String password) =>
      _api.invoke('delete-account', body: {'password': password, 'confirmation': accountDeletionWord});

  @override
  Future<void> signOut() => _api.run(() => _auth.signOut());

  /// The Edge Functions return their own token shape; hand the refresh token
  /// to the SDK so it owns renewal, secure persistence and Realtime auth.
  Future<void> _adoptSession(Map<String, dynamic> body) async {
    final session = body['session'];
    final refreshToken = session is Map ? session['refreshToken'] : null;
    if (refreshToken is! String || refreshToken.isEmpty) {
      throw StateError('login response without a session');
    }
    await _api.run(() => _auth.setSession(refreshToken));
  }
}
