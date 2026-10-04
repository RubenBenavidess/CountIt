import 'package:countit_app/app/errors/app_failure.dart';
import 'package:countit_app/data/dtos/transaction.dart';
import 'package:countit_app/data/remote/api_client.dart';
import 'package:countit_app/data/repositories/transaction_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../helpers/mocks.dart';

typedef _Query = PostgrestTransformBuilder<List<Map<String, dynamic>>> Function(
  PostgrestFilterBuilder<List<Map<String, dynamic>>> builder,
);

/// Runs a repository's query callback on a real PostgREST builder and
/// returns the request it sends, so tests check the exact filters.
Future<Uri> _requestOf(_Query query) async {
  late Uri url;
  final client = PostgrestClient(
    'http://localhost/rest/v1',
    httpClient: MockClient((request) async {
      url = request.url;
      return http.Response('[]', 200, headers: {'content-type': 'application/json'}, request: request);
    }),
  );
  await query(client.from(SupabaseTransactionRepository.view).select());
  return url;
}

Map<String, dynamic> _row(int id, String date) => {
  'transaction_id': id,
  'wallet_id': 4,
  'name': 'Movimiento $id',
  'type': 'expense',
  'amount': 10,
  'date': date,
};

void main() {
  late MockApiClient api;
  late SupabaseTransactionRepository transactions;
  late List<Uri> requests;

  setUp(() {
    api = MockApiClient();
    transactions = SupabaseTransactionRepository(api);
    requests = [];
  });

  /// Stubs `select` with [rows] and records the request each call builds.
  void selectReturns(List<Map<String, dynamic>> rows) =>
      when(
        () => api.select(
          any(),
          columns: any(named: 'columns'),
          query: any(named: 'query'),
        ),
      ).thenAnswer((invocation) async {
        requests.add(await _requestOf(invocation.namedArguments[#query] as _Query));
        return rows;
      });

  group('list (COU-230, COU-232)', () {
    test('first page: wallet, newest first with a stable tiebreak, one extra row', () async {
      selectReturns([_row(2, '2026-10-03'), _row(1, '2026-10-02')]);
      final page = await transactions.list(4, limit: 2);
      final query = requests.single.queryParameters;
      expect(requests.single.path, '/rest/v1/v_transactions');
      expect(query['wallet_id'], 'eq.4');
      expect(query['order'], 'date.desc.nullslast,transaction_id.desc.nullslast');
      expect(query['limit'], '3');
      expect(query.containsKey('or'), isFalse);
      expect(page.items.map((t) => t.transactionId), [2, 1]);
      expect(page.hasMore, isFalse, reason: 'no extra row came back');
    });

    test('the extra row means another page, which starts after the last shown row', () async {
      selectReturns([_row(5, '2026-10-03'), _row(4, '2026-10-02'), _row(3, '2026-10-02')]);
      final page = await transactions.list(4, limit: 2);
      expect(page.items.map((t) => t.transactionId), [5, 4], reason: 'the extra row is not shown');
      expect(page.next, TransactionCursor(date: DateTime(2026, 10, 2), transactionId: 4));
    });

    test('next pages use a keyset filter (stable when rows are added meanwhile)', () async {
      selectReturns([]);
      await transactions.list(4, after: TransactionCursor(date: DateTime(2026, 10, 2), transactionId: 4));
      expect(requests.single.queryParameters['or'], '(date.lt.2026-10-02,and(date.eq.2026-10-02,transaction_id.lt.4))');
      expect(requests.single.queryParameters['limit'], '${TransactionRepository.pageSize + 1}');
    });
  });

  group('getById', () {
    test('no row is transaction_not_found (404)', () async {
      selectReturns([]);
      await expectLater(
        transactions.getById(99),
        throwsA(
          isA<AppFailure>()
              .having((f) => f.kind, 'kind', FailureKind.notFound)
              .having((f) => f.key, 'key', 'transaction_not_found'),
        ),
      );
      expect(requests.single.queryParameters['transaction_id'], 'eq.99');
    });

    test('returns the row', () async {
      selectReturns([_row(7, '2026-10-01')]);
      expect((await transactions.getById(7)).transactionId, 7);
    });
  });

  group('writes', () {
    final input = TransactionInput(
      name: 'Taxi',
      type: TransactionType.expense,
      amountCents: 350,
      date: DateTime(2026, 10, 2),
      budgetId: 3,
    );

    test('create sends create_transaction with the wallet and returns the id', () async {
      when(() => api.rpc<dynamic>(any(), params: any(named: 'params'))).thenAnswer((_) async => {'transaction_id': 21});
      expect(await transactions.create(4, input), 21);
      verify(
        () => api.rpc<dynamic>(
          'create_transaction',
          params: {
            'p_wallet_id': 4,
            'p_name': 'Taxi',
            'p_type': 'expense',
            'p_amount': 3.5,
            'p_date': '2026-10-02',
            'p_budget_id': 3,
          },
        ),
      ).called(1);
    });

    test('update sends update_transaction with the full state', () async {
      when(() => api.rpc<dynamic>(any(), params: any(named: 'params'))).thenAnswer((_) async => {});
      await transactions.update(21, input);
      verify(
        () => api.rpc<dynamic>(
          'update_transaction',
          params: {
            'p_transaction_id': 21,
            'p_name': 'Taxi',
            'p_type': 'expense',
            'p_amount': 3.5,
            'p_date': '2026-10-02',
            'p_budget_id': 3,
          },
        ),
      ).called(1);
    });

    test('delete passes the reauth prompt to delete_transaction', () async {
      when(
        () => api.rpc<dynamic>(
          any(),
          params: any(named: 'params'),
          onReauth: any(named: 'onReauth'),
        ),
      ).thenAnswer((_) async => {});
      Future<bool> prompt() async => true;
      final ReauthPrompt onReauth = prompt;
      await transactions.delete(21, onReauth: onReauth);
      verify(() => api.rpc<dynamic>('delete_transaction', params: {'p_transaction_id': 21}, onReauth: onReauth))
          .called(1);
    });
  });
}
