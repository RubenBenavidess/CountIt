import 'package:countit_app/app/errors/app_failure.dart';
import 'package:countit_app/data/dtos/scheduled_transaction.dart';
import 'package:countit_app/data/dtos/transaction.dart';
import 'package:countit_app/data/remote/api_client.dart';
import 'package:countit_app/data/repositories/scheduled_transaction_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../helpers/mocks.dart';

typedef _Query = PostgrestTransformBuilder<List<Map<String, dynamic>>> Function(
  PostgrestFilterBuilder<List<Map<String, dynamic>>> builder,
);

/// Runs the repository's query callback on a real PostgREST builder and
/// returns the request it sends.
Future<Uri> _requestOf(_Query query, String columns) async {
  late Uri url;
  final client = PostgrestClient(
    'http://localhost/rest/v1',
    httpClient: MockClient((request) async {
      url = request.url;
      return http.Response('[]', 200, headers: {'content-type': 'application/json'}, request: request);
    }),
  );
  await query(client.from(SupabaseScheduledTransactionRepository.view).select(columns));
  return url;
}

Map<String, dynamic> _row(int id, {bool paused = false}) => {
  'scheduled_transaction_id': id,
  'wallet_id': 4,
  'user_id': 'u1',
  'name': 'Regla $id',
  'type': 'expense',
  'amount': 10,
  'periodicity': 'months',
  'period_interval': 1,
  'start_date': '2026-11-01',
  'next_run_date': '2026-11-01',
  'is_active': true,
  'is_paused': paused,
};

void main() {
  late MockApiClient api;
  late SupabaseScheduledTransactionRepository scheduled;
  late List<Uri> requests;

  setUp(() {
    api = MockApiClient();
    scheduled = SupabaseScheduledTransactionRepository(api);
    requests = [];
  });

  void selectReturns(List<Map<String, dynamic>> rows) =>
      when(
        () => api.select(
          any(),
          columns: any(named: 'columns'),
          query: any(named: 'query'),
        ),
      ).thenAnswer((invocation) async {
        final columns = (invocation.namedArguments[#columns] as String?) ?? '*';
        requests.add(await _requestOf(invocation.namedArguments[#query] as _Query, columns));
        return rows;
      });

  void rpcReturns(Object? json) =>
      when(() => api.rpc<dynamic>(any(), params: any(named: 'params'))).thenAnswer((_) async => json);

  group('reads (COU-20)', () {
    test('listByWallet: the wallet, soonest next run first, stable tiebreak', () async {
      selectReturns([_row(1), _row(2)]);
      final rules = await scheduled.listByWallet(4);
      final query = requests.single.queryParameters;
      expect(requests.single.path, '/rest/v1/v_scheduled_transactions');
      expect(query['wallet_id'], 'eq.4');
      expect(query['order'], 'next_run_date.asc.nullslast,scheduled_transaction_id.asc.nullslast');
      expect(rules.map((r) => r.scheduledTransactionId), [1, 2]);
    });

    test('usageOf counts the caller\'s rules in every wallet, two columns only', () async {
      selectReturns([_row(1), _row(2, paused: true), _row(3)]);
      final usage = await scheduled.usageOf('u1');
      final query = requests.single.queryParameters;
      expect(query['user_id'], 'eq.u1');
      expect(query.containsKey('wallet_id'), isFalse);
      expect(query['select'], 'scheduled_transaction_id,is_paused');
      expect(usage, const ScheduledUsage(total: 3, running: 2));
      expect(usage.paused, 1);
    });

    test('getById: an empty answer is the API\'s 404', () async {
      selectReturns([]);
      await expectLater(
        scheduled.getById(99),
        throwsA(isA<AppFailure>().having((f) => f.key, 'key', 'scheduled_transaction_not_found')),
      );
      expect(requests.single.queryParameters['scheduled_transaction_id'], 'eq.99');
    });
  });

  group('writes (COU-20)', () {
    final input = ScheduledTransactionInput(
      name: 'Sueldo',
      type: TransactionType.income,
      amountCents: 90000,
      startDate: DateTime(2026, 10, 30),
      periodicity: Periodicity.months,
    );

    test('create sends the wallet and every field, returns the rule', () async {
      rpcReturns(_row(31));
      final rule = await scheduled.create(4, input);
      expect(rule.scheduledTransactionId, 31);
      verify(
        () => api.rpc<dynamic>(
          'create_scheduled_transaction',
          params: {
            'p_wallet_id': 4,
            'p_name': 'Sueldo',
            'p_type': 'income',
            'p_amount': 900.0,
            'p_periodicity': 'months',
            'p_period_interval': 1,
            'p_end_date': null,
            'p_budget_id': null,
            'p_start_date': '2026-10-30',
          },
        ),
      ).called(1);
    });

    test('update sends p_id and the editable fields, never the start', () async {
      rpcReturns(_row(31));
      await scheduled.update(31, input);
      final params =
          verify(() => api.rpc<dynamic>('update_scheduled_transaction', params: captureAny(named: 'params')))
                  .captured
                  .single
              as Map<String, dynamic>;
      expect(params['p_id'], 31);
      expect(params.containsKey('p_start_date'), isFalse);
      expect(params['p_period_interval'], 1);
    });

    test('setPaused sends set_scheduled_transaction_paused', () async {
      rpcReturns(_row(31, paused: true));
      final rule = await scheduled.setPaused(31, paused: true);
      expect(rule.isPaused, isTrue);
      verify(() => api.rpc<dynamic>('set_scheduled_transaction_paused', params: {'p_id': 31, 'p_paused': true}))
          .called(1);
    });

    test('an unexpected payload is a server failure, never a crash', () async {
      rpcReturns(null);
      await expectLater(
        scheduled.setPaused(31, paused: false),
        throwsA(isA<AppFailure>().having((f) => f.kind, 'kind', FailureKind.server)),
      );
    });

    test('delete passes the reauth prompt', () async {
      when(
        () => api.rpc<dynamic>(
          any(),
          params: any(named: 'params'),
          onReauth: any(named: 'onReauth'),
        ),
      ).thenAnswer((_) async => {});
      Future<bool> prompt() async => true;
      final ReauthPrompt onReauth = prompt;
      await scheduled.delete(31, onReauth: onReauth);
      verify(() => api.rpc<dynamic>('delete_scheduled_transaction', params: {'p_id': 31}, onReauth: onReauth))
          .called(1);
    });
  });
}
