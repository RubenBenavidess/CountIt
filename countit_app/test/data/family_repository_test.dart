import 'dart:async';

import 'package:countit_app/app/errors/app_failure.dart';
import 'package:countit_app/data/dtos/family.dart';
import 'package:countit_app/data/remote/api_client.dart';
import 'package:countit_app/data/remote/realtime_watcher.dart';
import 'package:countit_app/data/repositories/family_repository.dart';
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
  await query(client.from(SupabaseFamilyRepository.view).select(columns));
  return url;
}

/// Realtime double: one controller per watched topic, driven by the test.
class _FakeRealtime implements RealtimeWatcher {
  final topics = <RealtimeTopic>[];
  final controllers = <StreamController<void>>[];

  @override
  Stream<void> watch(RealtimeTopic topic) {
    topics.add(topic);
    final controller = StreamController<void>();
    controllers.add(controller);
    return controller.stream;
  }
}

void main() {
  late MockApiClient api;
  late _FakeRealtime realtime;
  late SupabaseFamilyRepository families;

  setUp(() {
    api = MockApiClient();
    realtime = _FakeRealtime();
    families = SupabaseFamilyRepository(api, realtime);
  });

  void rpcReturns(Object? json) => when(
    () => api.rpc<dynamic>(
      any(),
      params: any(named: 'params'),
      onReauth: any(named: 'onReauth'),
      planUpsell: any(named: 'planUpsell'),
    ),
  ).thenAnswer((_) async => json);

  group('membersOf (v_family_members · COU-21)', () {
    test('filters the wallet, narrow columns, sorted owner → accepted → pending; unknown status skipped', () async {
      late Uri request;
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
        return [
          {'wallet_id': 4, 'user_id': 'p', 'username': 'pedro_p', 'status': 'pending', 'is_owner': false},
          {'wallet_id': 4, 'user_id': 'x', 'username': 'nuevo_x', 'status': 'banned', 'is_owner': false},
          {'wallet_id': 4, 'user_id': 'a', 'username': 'ana_q', 'status': 'accepted', 'is_owner': false},
          {'wallet_id': 4, 'user_id': 'o', 'username': 'owner_o', 'status': 'owner', 'is_owner': true},
        ];
      });

      final members = await families.membersOf(4);

      expect(request.path, '/rest/v1/v_family_members');
      expect(request.queryParameters['wallet_id'], 'eq.4');
      expect(request.queryParameters['select'], isNot(contains('email')));
      expect(members.map((m) => m.userId), ['o', 'a', 'p']);
      expect(members.first.status, FamilyStatus.owner);
    });
  });

  group('RPCs', () {
    test('myInvitations: get_my_invitations rows', () async {
      rpcReturns([
        {'wallet_id': 5, 'wallet_name': 'Viaje', 'owner_username': 'lucia_m', 'owner_name': 'Lucía'},
      ]);
      final invitations = await families.myInvitations();
      expect(invitations.single.walletId, 5);
      expect(invitations.single.owner, 'Lucía');
      verify(() => api.rpc<dynamic>('get_my_invitations')).called(1);
    });

    test('invite: trimmed username; returns the pending membership', () async {
      rpcReturns({'wallet_id': 4, 'user_id': 'u3', 'username': 'carlos_q', 'status': 'pending'});
      final member = await families.invite(4, '  carlos_q ');
      expect(member.isPending, isTrue);
      verify(() => api.rpc<dynamic>('invite_family_member', params: {'p_wallet_id': 4, 'p_username': 'carlos_q'}))
          .called(1);
    });

    test('invite: an unexpected body is a server failure', () async {
      rpcReturns(null);
      await expectLater(
        families.invite(4, 'carlos_q'),
        throwsA(isA<AppFailure>().having((f) => f.kind, 'kind', FailureKind.server)),
      );
    });

    test('respond, leave: their parameters', () async {
      rpcReturns(<String, dynamic>{});
      await families.respond(5, accept: true);
      await families.respond(6, accept: false);
      await families.leave(4);
      // A 403 on accepting is about the owner's plan: kept away from the plans sheet.
      verify(
        () => api.rpc<dynamic>(
          'respond_family_invitation',
          params: {'p_wallet_id': 5, 'p_accept': true},
          planUpsell: false,
        ),
      ).called(1);
      verify(
        () => api.rpc<dynamic>(
          'respond_family_invitation',
          params: {'p_wallet_id': 6, 'p_accept': false},
          planUpsell: false,
        ),
      ).called(1);
      verify(() => api.rpc<dynamic>('leave_family', params: {'p_wallet_id': 4})).called(1);
    });

    test('remove 🔒: passes the reauth prompt to the API client', () async {
      rpcReturns(<String, dynamic>{});
      Future<bool> prompt() async => true;
      final ReauthPrompt onReauth = prompt;
      await families.remove(4, 'u2', onReauth: onReauth);
      verify(
        () =>
            api.rpc<dynamic>('remove_family_member', params: {'p_wallet_id': 4, 'p_user_id': 'u2'}, onReauth: onReauth),
      ).called(1);
    });
  });

  group('Realtime on public.families (simulated)', () {
    test('my memberships: user_id filter; each signal reaches the listener', () async {
      final signals = <void>[];
      final subscription = families.myMembershipChanges('u1').listen(signals.add);
      final topic = realtime.topics.single;
      expect((topic.table, topic.column, topic.value), ('families', 'user_id', 'u1'));

      realtime.controllers.single
        ..add(null)
        ..add(null);
      await Future<void>.delayed(Duration.zero);
      expect(signals, hasLength(2));

      await subscription.cancel();
      expect(realtime.controllers.single.hasListener, isFalse, reason: 'cancel releases the channel');
    });

    test('wallet memberships: wallet_id filter', () async {
      final subscription = families.walletMembershipChanges(4).listen((_) {});
      final topic = realtime.topics.single;
      expect((topic.table, topic.column, topic.value), ('families', 'wallet_id', 4));
      await subscription.cancel();
    });
  });
}
