import 'package:countit_app/data/dtos/notification.dart';
import 'package:countit_app/data/repositories/notification_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../helpers/mocks.dart';

typedef _Query = PostgrestTransformBuilder<List<Map<String, dynamic>>> Function(
  PostgrestFilterBuilder<List<Map<String, dynamic>>> builder,
);

/// Runs the repository's query on a real PostgREST builder; returns the URL it sends.
Future<Uri> _requestOf(_Query query, String columns) async {
  late Uri url;
  final client = PostgrestClient(
    'http://localhost/rest/v1',
    httpClient: MockClient((request) async {
      url = request.url;
      return http.Response('[]', 200, headers: {'content-type': 'application/json'}, request: request);
    }),
  );
  await query(client.from(SupabaseNotificationRepository.view).select(columns));
  return url;
}

Map<String, dynamic> _row(int id, {String? readAt}) => {
  'notification_id': id,
  'kind': 'budget_warning',
  'title': 'Presupuesto al 80 %',
  'body': 'texto',
  'data': {'budget_id': 3, 'wallet_id': 7},
  'created_at': '2026-10-03T15:00:00Z',
  'read_at': readAt,
};

void main() {
  late MockApiClient api;
  late SupabaseNotificationRepository repository;
  late Uri request;

  setUp(() {
    api = MockApiClient();
    repository = SupabaseNotificationRepository(api);
  });

  void selectReturns(List<Map<String, dynamic>> rows) =>
      when(
        () => api.select(
          any(),
          columns: any(named: 'columns'),
          query: any(named: 'query'),
        ),
      ).thenAnswer((invocation) async {
        request = await _requestOf(
          invocation.namedArguments[#query] as _Query,
          invocation.namedArguments[#columns] as String,
        );
        return rows;
      });

  group('inbox (v_notifications · COU-30)', () {
    test('first page: newest first, one extra row to know about the next page', () async {
      selectReturns([for (var id = 40; id > 9; id--) _row(id)]);
      final page = await repository.inbox();

      expect(request.path, '/rest/v1/v_notifications');
      expect(request.queryParameters['order'], startsWith('notification_id.desc'));
      expect(request.queryParameters['limit'], '31');
      expect(request.queryParameters.containsKey('notification_id'), isFalse);
      expect(page.items, hasLength(30));
      expect(page.items.first.id, 40);
      expect(page.hasMore, isTrue);
    });

    test('next page continues before the last id (keyset)', () async {
      selectReturns([_row(5), _row(4)]);
      final page = await repository.inbox(before: 6);
      expect(request.queryParameters['notification_id'], 'lt.6');
      expect(page.items.map((n) => n.id), [5, 4]);
      expect(page.hasMore, isFalse);
    });

    test('rows without a numeric id are skipped', () async {
      selectReturns([
        _row(5),
        {..._row(4), 'notification_id': 'x'},
      ]);
      final page = await repository.inbox();
      expect(page.items.single.kind, NotificationKind.budgetWarning);
    });
  });

  test('unreadCount: only unread ids, capped', () async {
    selectReturns([
      {'notification_id': 3},
      {'notification_id': 2},
    ]);
    expect(await repository.unreadCount(), 2);
    expect(request.queryParameters['read_at'], 'is.null');
    expect(request.queryParameters['select'], 'notification_id');
    expect(request.queryParameters['limit'], '${NotificationRepository.unreadCap}');
  });

  group('mark_notifications_read (COU-181)', () {
    setUp(() {
      when(() => api.rpc<dynamic>(any(), params: any(named: 'params'))).thenAnswer((_) async => 1);
    });

    test('some ids', () async {
      await repository.markRead([4, 5]);
      verify(
        () => api.rpc<dynamic>(
          'mark_notifications_read',
          params: {
            'p_ids': [4, 5],
          },
        ),
      ).called(1);
    });

    test('no ids: nothing is sent (it would mark all)', () async {
      await repository.markRead(const []);
      verifyNever(() => api.rpc<dynamic>(any(), params: any(named: 'params')));
    });

    test('all: without p_ids', () async {
      await repository.markAllRead();
      verify(() => api.rpc<dynamic>('mark_notifications_read')).called(1);
    });
  });
}
