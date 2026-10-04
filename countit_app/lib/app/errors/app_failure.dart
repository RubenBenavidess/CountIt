import 'package:equatable/equatable.dart';

/// What the UI must do with a failure, independent of where it came from
/// (PostgREST RPC/view, Edge Function, Auth or the network).
enum FailureKind {
  /// 400: a field is missing or invalid; show [AppFailure.message] next to the form.
  validation,

  /// 401: no session, or the session was closed elsewhere → back to login.
  unauthenticated,

  /// 403 `reauth_required`: ask for the password, call `reauthenticate`, retry.
  reauthRequired,

  /// 403 `feature_not_in_plan`: offer the plans screen.
  featureNotInPlan,

  /// 403 other: not allowed.
  forbidden,

  /// 404: missing, someone else's or deleted (the API does not tell them apart).
  notFound,

  /// 409: plan quota reached, name taken, state conflict.
  conflict,

  /// 423: account locked for a while.
  locked,

  /// 429: too many attempts; [AppFailure.retryAfter] when the server says.
  rateLimited,

  /// No connection or timeout.
  network,

  /// 5xx or an unexpected response.
  server,
}

/// A failure the UI can show (always a Spanish [message]) and branch on
/// ([kind] and the stable backend [key], e.g. `wallet_limit_exceeded`).
class AppFailure extends Equatable implements Exception {
  const AppFailure({
    required this.kind,
    required this.message,
    this.key,
    this.status,
    this.fieldErrors = const {},
    this.retryAfter,
  });

  final FailureKind kind;

  /// Spanish, ready to show.
  final String message;

  /// Stable backend key (`hint` of RPC errors, `code` of Edge Functions).
  final String? key;
  final int? status;

  /// Per-field messages from Edge Function validation (`validationErrors`).
  final Map<String, String> fieldErrors;
  final Duration? retryAfter;

  /// True when the session is gone and the app must return to login.
  bool get endsSession => kind == FailureKind.unauthenticated;

  @override
  List<Object?> get props => [kind, message, key, status, fieldErrors, retryAfter];

  @override
  String toString() => 'AppFailure($kind, key: $key, status: $status)';
}
