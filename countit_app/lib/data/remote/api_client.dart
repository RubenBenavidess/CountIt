import 'package:supabase_flutter/supabase_flutter.dart';

import '../../app/errors/app_failure.dart';
import '../../app/errors/error_mapper.dart';

/// Asks the user to confirm their password (modal + `reauthenticate`).
/// Returns true when the identity was confirmed and the action can be retried.
typedef ReauthPrompt = Future<bool> Function();

/// Single entry point to the backend for repositories.
///
/// * Every call is wrapped by [run]: errors become [AppFailure] (Spanish
///   message + stable key), never raw transport exceptions.
/// * A 401 (`session_revoked`, `not_authenticated`, expired JWT) notifies
///   [onSessionEnded] once, so the session layer can sign out and route to
///   login (COU-57).
/// * Destructive actions pass `onReauth`: on `403 reauth_required` the prompt
///   runs and the call is retried once after a successful confirmation (COU-59).
class ApiClient {
  ApiClient(this._client, {this.deviceId});

  final SupabaseClient _client;

  /// Stable install id sent as `x-device-id` to the Edge Functions (rate limiting per device).
  final String? deviceId;

  /// Set by the session layer; called when a request proves the session is gone.
  void Function(AppFailure failure)? onSessionEnded;

  SupabaseClient get supabase => _client;

  /// `POST /rest/v1/rpc/<function>` on the `api` schema.
  Future<T> rpc<T>(String function, {Map<String, dynamic>? params, ReauthPrompt? onReauth}) =>
      run(() async => await _client.rpc<T>(function, params: params), onReauth: onReauth);

  /// `GET /rest/v1/<view>`: [query] receives the builder for filters, order and paging.
  Future<List<Map<String, dynamic>>> select(
    String view, {
    String columns = '*',
    PostgrestTransformBuilder<List<Map<String, dynamic>>> Function(
      PostgrestFilterBuilder<List<Map<String, dynamic>>> builder,
    )?
    query,
  }) => run(() async {
    final builder = _client.from(view).select(columns);
    return await (query == null ? builder : query(builder));
  });

  /// `POST /functions/v1/<name>`; returns the decoded JSON body.
  Future<Map<String, dynamic>> invoke(String name, {Map<String, dynamic>? body}) => run(() async {
    final response = await _client.functions.invoke(name, body: body, headers: {'x-device-id': ?deviceId});
    final data = response.data;
    return data is Map ? Map<String, dynamic>.from(data) : <String, dynamic>{};
  });

  /// Runs [call] mapping its errors; see the class doc for 401 and reauth handling.
  Future<T> run<T>(Future<T> Function() call, {ReauthPrompt? onReauth}) async {
    try {
      return await call();
    } catch (error) {
      final failure = ErrorMapper.map(error);
      if (failure.kind == FailureKind.reauthRequired && onReauth != null && await onReauth()) {
        try {
          return await call();
        } catch (retryError) {
          throw _report(ErrorMapper.map(retryError));
        }
      }
      throw _report(failure);
    }
  }

  AppFailure _report(AppFailure failure) {
    if (failure.endsSession) onSessionEnded?.call(failure);
    return failure;
  }
}
