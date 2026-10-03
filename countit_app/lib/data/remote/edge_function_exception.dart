/// Non-2xx answer of an Edge Function: the decoded body
/// (`{success: false, error, code, validationErrors}`) plus the `Retry-After`
/// header, which `supabase.functions.invoke` does not expose (COU-63).
class EdgeFunctionException implements Exception {
  const EdgeFunctionException({required this.status, this.body = const {}, this.retryAfter});

  final int status;
  final Map<String, dynamic> body;
  final Duration? retryAfter;

  /// `Retry-After` in seconds (the only form the backend sends); null when absent or invalid.
  static Duration? parseRetryAfter(String? header) {
    final seconds = int.tryParse(header?.trim() ?? '');
    return seconds == null || seconds <= 0 ? null : Duration(seconds: seconds);
  }

  @override
  String toString() => 'EdgeFunctionException($status, code: ${body['code']})';
}
