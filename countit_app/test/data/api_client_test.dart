import 'dart:convert';

import 'package:countit_app/app/errors/app_failure.dart';
import 'package:countit_app/data/remote/api_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class _MockSupabase extends Mock implements SupabaseClient {}

class _MockFunctions extends Mock implements FunctionsClient {}

class _MockAuth extends Mock implements GoTrueClient {}

class _MockSession extends Mock implements Session {}

final _functionsUrl = Uri.parse('https://api.test/functions/v1');

const _reauth = PostgrestException(code: 'PT403', message: 'Confirma tu contraseña', hint: 'reauth_required');
const _revoked = PostgrestException(code: 'PT401', message: 'Tu sesión ya no es válida', hint: 'session_revoked');

void main() {
  late ApiClient api;
  late List<AppFailure> ended;

  setUp(() {
    api = ApiClient(_MockSupabase(), functionsUrl: _functionsUrl);
    ended = [];
    api.onSessionEnded = ended.add;
  });

  test('maps errors to AppFailure', () async {
    await expectLater(
      api.run<void>(() async => throw const PostgrestException(code: 'PT404', message: 'No', hint: 'wallet_not_found')),
      throwsA(isA<AppFailure>().having((f) => f.kind, 'kind', FailureKind.notFound)),
    );
    expect(ended, isEmpty);
  });

  test('reauth_required: prompts, then retries once after confirmation (COU-59)', () async {
    var calls = 0;
    var prompts = 0;
    final result = await api.run(() async {
      calls++;
      if (calls == 1) throw _reauth;
      return 'deleted';
    }, onReauth: () async => ++prompts > 0);
    expect(result, 'deleted');
    expect(calls, 2);
    expect(prompts, 1);
  });

  test('reauth cancelled: the failure reaches the caller and nothing is retried', () async {
    var calls = 0;
    await expectLater(
      api.run<void>(() async {
        calls++;
        throw _reauth;
      }, onReauth: () async => false),
      throwsA(isA<AppFailure>().having((f) => f.kind, 'kind', FailureKind.reauthRequired)),
    );
    expect(calls, 1);
  });

  test('without onReauth the failure is returned as is', () async {
    await expectLater(
      api.run<void>(() async => throw _reauth),
      throwsA(isA<AppFailure>().having((f) => f.key, 'key', 'reauth_required')),
    );
  });

  test('a 401 notifies the session layer (COU-57)', () async {
    await expectLater(api.run<void>(() async => throw _revoked), throwsA(isA<AppFailure>()));
    expect(ended.single.key, 'session_revoked');
  });

  test('a wrong password while reauthenticating does not sign the user out (audit A1)', () async {
    await expectLater(
      api.run<void>(() async => throw const FunctionException(status: 401, details: {'code': 'invalid_password'})),
      throwsA(isA<AppFailure>().having((f) => f.kind, 'kind', FailureKind.invalidCredentials)),
    );
    expect(ended, isEmpty);
  });

  test('a 401 on the retry after reauth is also reported', () async {
    var calls = 0;
    await expectLater(
      api.run<void>(() async {
        calls++;
        throw calls == 1 ? _reauth : _revoked;
      }, onReauth: () async => true),
      throwsA(isA<AppFailure>().having((f) => f.endsSession, 'endsSession', isTrue)),
    );
    expect(ended, hasLength(1));
  });

  group('403 feature_not_in_plan (COU-183)', () {
    const notInPlan = PostgrestException(
      code: 'PT403',
      message: 'Tu plan no incluye familias',
      hint: 'feature_not_in_plan',
    );
    late List<AppFailure> notices;

    setUp(() {
      notices = [];
      api.onFeatureNotInPlan = notices.add;
    });

    test('is reported to the app, once, with the backend message', () async {
      await expectLater(api.run<void>(() async => throw notInPlan), throwsA(isA<AppFailure>()));
      expect(notices.single.message, 'Tu plan no incluye familias');
      expect(ended, isEmpty);
    });

    test('planUpsell false keeps it local (a 403 about someone else\'s plan)', () async {
      await expectLater(api.run<void>(() async => throw notInPlan, planUpsell: false), throwsA(isA<AppFailure>()));
      expect(notices, isEmpty);
    });

    test('other 403s are not plan notices', () async {
      await expectLater(
        api.run<void>(
          () async => throw const PostgrestException(code: 'PT403', message: 'Acceso denegado', hint: 'forbidden'),
        ),
        throwsA(isA<AppFailure>().having((f) => f.kind, 'kind', FailureKind.forbidden)),
      );
      expect(notices, isEmpty);
    });
  });

  group('invoke (Edge Functions with our HTTP client, COU-63)', () {
    late _MockSupabase supabase;
    late http.Request sent;

    ApiClient withServer(http.Response Function(http.Request request) answer, {String? accessToken = 'user-jwt'}) {
      supabase = _MockSupabase();
      final functions = _MockFunctions();
      final auth = _MockAuth();
      when(() => supabase.functions).thenReturn(functions);
      when(() => supabase.auth).thenReturn(auth);
      when(() => functions.headers).thenReturn({'apikey': 'anon', 'Authorization': 'Bearer anon'});
      Session? session;
      if (accessToken != null) {
        session = _MockSession();
        when(() => session!.accessToken).thenReturn(accessToken);
      }
      when(() => auth.currentSession).thenReturn(session);
      return ApiClient(
        supabase,
        functionsUrl: _functionsUrl,
        deviceId: 'device-1',
        httpClient: MockClient((request) async {
          sent = request;
          return answer(request);
        }),
      );
    }

    test('posts JSON with the SDK headers and the device id', () async {
      final client = withServer((_) => http.Response(jsonEncode({'success': true}), 200));
      final body = await client.invoke('login', body: {'email': 'a@b.ec'});
      expect(body['success'], isTrue);
      expect(sent.url.toString(), 'https://api.test/functions/v1/login');
      expect(sent.headers['apikey'], 'anon');
      expect(sent.headers['Authorization'], 'Bearer user-jwt', reason: 'the current session token, not a stale header');
      expect(sent.headers['x-device-id'], 'device-1');
      expect(jsonDecode(sent.body), {'email': 'a@b.ec'});
    });

    test('without a session the anon key authorizes the call (login, register)', () async {
      final client = withServer((_) => http.Response('{}', 200), accessToken: null);
      await client.invoke('login');
      expect(sent.headers['Authorization'], 'Bearer anon');
    });

    test('429 exposes Retry-After as AppFailure.retryAfter', () async {
      final client = withServer(
        (_) => http.Response(
          jsonEncode({'success': false, 'error': 'Demasiados intentos', 'code': 'rate_limited'}),
          429,
          headers: {'retry-after': '900', 'content-type': 'application/json'},
        ),
      );
      await expectLater(
        client.invoke('login'),
        throwsA(
          isA<AppFailure>()
              .having((f) => f.kind, 'kind', FailureKind.rateLimited)
              .having((f) => f.retryAfter, 'retryAfter', const Duration(seconds: 900)),
        ),
      );
    });

    test('a non-JSON gateway error still maps by status', () async {
      final client = withServer((_) => http.Response('<html>Bad gateway</html>', 502));
      await expectLater(
        client.invoke('register'),
        throwsA(isA<AppFailure>().having((f) => f.kind, 'kind', FailureKind.server)),
      );
    });

    test('a timeout is a network failure', () async {
      supabase = _MockSupabase();
      final functions = _MockFunctions();
      final auth = _MockAuth();
      when(() => supabase.functions).thenReturn(functions);
      when(() => supabase.auth).thenReturn(auth);
      when(() => auth.currentSession).thenReturn(null);
      when(() => functions.headers).thenReturn(<String, String>{});
      final slow = ApiClient(
        supabase,
        functionsUrl: _functionsUrl,
        timeout: const Duration(milliseconds: 10),
        httpClient: MockClient((_) => Future.delayed(const Duration(seconds: 1), () => http.Response('{}', 200))),
      );
      await expectLater(
        slow.invoke('login'),
        throwsA(isA<AppFailure>().having((f) => f.kind, 'kind', FailureKind.network)),
      );
    });
  });
}
