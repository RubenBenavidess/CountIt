import 'package:countit_app/app/errors/app_failure.dart';
import 'package:countit_app/data/remote/api_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class _MockSupabase extends Mock implements SupabaseClient {}

const _reauth = PostgrestException(code: 'PT403', message: 'Confirma tu contraseña', hint: 'reauth_required');
const _revoked = PostgrestException(code: 'PT401', message: 'Tu sesión ya no es válida', hint: 'session_revoked');

void main() {
  late ApiClient api;
  late List<AppFailure> ended;

  setUp(() {
    api = ApiClient(_MockSupabase());
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
}
