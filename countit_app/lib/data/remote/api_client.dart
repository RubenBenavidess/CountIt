import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../app/errors/app_failure.dart';
import '../../app/errors/error_mapper.dart';
import '../../app/logging/app_logger.dart';
import 'edge_function_exception.dart';

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
  ApiClient(
    this._client, {
    required this.functionsUrl,
    this.deviceId,
    http.Client? httpClient,
    this.timeout = const Duration(seconds: 20),
  }) : _http = httpClient ?? http.Client();

  final SupabaseClient _client;
  final http.Client _http;

  /// `<SUPABASE_URL>/functions/v1`.
  final Uri functionsUrl;

  /// Stable install id sent as `x-device-id` to the Edge Functions (rate limiting per device).
  final String? deviceId;

  /// Upper bound for an Edge Function call; past it the UI shows the network error.
  final Duration timeout;

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
  ///
  /// Sent with our own HTTP client (same headers as the SDK: `apikey`, the
  /// current access token and client info) because the SDK hides the response
  /// headers and 429 answers carry the wait in `Retry-After` (COU-63).
  Future<Map<String, dynamic>> invoke(String name, {Map<String, dynamic>? body, ReauthPrompt? onReauth}) =>
      run(() async {
        // The SDK updates `functions.headers` from an auth listener, which may
        // lag right after setSession: read the current token at call time.
        final token = _client.auth.currentSession?.accessToken;
        final response = await _http
            .post(
              functionsUrl.replace(path: '${functionsUrl.path}/$name'),
              headers: {
                ..._client.functions.headers,
                'Authorization': ?(token == null ? null : 'Bearer $token'),
                'Content-Type': 'application/json',
                'x-device-id': ?deviceId,
              },
              body: jsonEncode(body ?? const <String, dynamic>{}),
            )
            .timeout(timeout);
        final decoded = _decode(response.body);
        if (response.statusCode >= 200 && response.statusCode < 300) return decoded;
        throw EdgeFunctionException(
          status: response.statusCode,
          body: decoded,
          retryAfter: EdgeFunctionException.parseRetryAfter(response.headers['retry-after']),
        );
      }, onReauth: onReauth);

  static Map<String, dynamic> _decode(String body) {
    if (body.isEmpty) return <String, dynamic>{};
    try {
      final decoded = jsonDecode(body);
      return decoded is Map ? Map<String, dynamic>.from(decoded) : <String, dynamic>{};
    } on FormatException {
      // A gateway error page: the status alone decides the failure.
      return <String, dynamic>{};
    }
  }

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
    // Only the classification: never messages, payloads or tokens.
    AppLogger.debug('api failure ${failure.kind.name} key=${failure.key} status=${failure.status}');
    if (failure.endsSession) onSessionEnded?.call(failure);
    return failure;
  }
}
