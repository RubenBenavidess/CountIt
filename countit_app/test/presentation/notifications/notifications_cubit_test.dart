import 'dart:async';

import 'package:countit_app/app/errors/app_failure.dart';
import 'package:countit_app/data/dtos/notification.dart';
import 'package:countit_app/data/dtos/paged.dart';
import 'package:countit_app/presentation/notifications/cubit/notifications_cubit.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../../helpers/mocks.dart';
import '../../helpers/notification_fixtures.dart';

const _network = AppFailure(kind: FailureKind.network, message: 'Sin conexión');

List<AppNotification> _range(int from, int to, {bool read = false}) => [
  for (var id = from; id >= to; id--) notificationFixture(id: id, readAt: read ? DateTime.utc(2026) : null),
];

void main() {
  late MockNotificationRepository repository;
  late NotificationsCubit cubit;

  setUp(() {
    repository = MockNotificationRepository();
    cubit = NotificationsCubit(repository);
    when(() => repository.markRead(any())).thenAnswer((_) async {});
    when(repository.markAllRead).thenAnswer((_) async {});
    when(() => repository.changes(any())).thenAnswer((_) => const Stream.empty());
  });

  tearDown(() => cubit.close());

  void inboxReturns(List<AppNotification> items, {bool hasMore = false, int? unread}) {
    when(() => repository.inbox()).thenAnswer((_) async => Paged(items, hasMore: hasMore));
    when(repository.unreadCount).thenAnswer((_) async => unread ?? items.where((n) => !n.isRead).length);
  }

  group('setUser / load (COU-108, COU-111)', () {
    test('loads the first page and the unread count', () async {
      inboxReturns([notificationFixture(id: 2), notificationFixture(id: 1, readAt: DateTime.utc(2026))]);
      await cubit.setUser('u1');
      expect(cubit.state.status, InboxStatus.success);
      expect(cubit.state.items.map((n) => n.id), [2, 1]);
      expect(cubit.state.unread, 1);
      expect(cubit.state.badgeLabel, '1');
    });

    test('nothing without a user', () async {
      await cubit.load();
      verifyNever(() => repository.inbox());
    });

    test('a failed first load keeps nothing and explains itself', () async {
      when(() => repository.inbox()).thenThrow(_network);
      when(repository.unreadCount).thenAnswer((_) async => 0);
      await cubit.setUser('u1');
      expect(cubit.state.status, InboxStatus.failure);
      expect(cubit.state.failure, _network);
      expect(cubit.state.isFirstLoad, isTrue);
    });

    test('a failed reload keeps the list on screen', () async {
      inboxReturns([notificationFixture(id: 2)]);
      await cubit.setUser('u1');
      when(() => repository.inbox()).thenThrow(_network);
      await cubit.load();
      expect(cubit.state.status, InboxStatus.failure);
      expect(cubit.state.items, hasLength(1));
      expect(cubit.state.isFirstLoad, isFalse);
    });

    test('signing out forgets everything; a late answer of the old user is dropped', () async {
      final pending = Completer<Paged<AppNotification>>();
      when(() => repository.inbox()).thenAnswer((_) => pending.future);
      when(repository.unreadCount).thenAnswer((_) async => 5);
      unawaited(cubit.setUser('u1'));
      await cubit.setUser(null);
      pending.complete(Paged([notificationFixture()], hasMore: false));
      await Future<void>.delayed(Duration.zero);
      expect(cubit.state, const NotificationsState());
    });

    test('loads during a load are coalesced into one more', () async {
      final first = Completer<Paged<AppNotification>>();
      var calls = 0;
      when(() => repository.inbox()).thenAnswer((_) {
        calls++;
        return calls == 1 ? first.future : Future.value(const Paged(<AppNotification>[], hasMore: false));
      });
      when(repository.unreadCount).thenAnswer((_) async => 0);
      final initial = cubit.setUser('u1');
      unawaited(cubit.load());
      unawaited(cubit.load());
      first.complete(const Paged(<AppNotification>[], hasMore: false));
      await initial;
      expect(calls, 2);
    });

    test('badge: «99+» past 99', () {
      expect(const NotificationsState(unread: 100).badgeLabel, '99+');
      expect(const NotificationsState().badgeLabel, isNull);
    });
  });

  group('paging', () {
    test('loadMore continues before the last id and appends without duplicates', () async {
      inboxReturns(_range(40, 11), hasMore: true);
      await cubit.setUser('u1');
      when(() => repository.inbox(before: 11)).thenAnswer((_) async => Paged(_range(11, 5), hasMore: false));
      await cubit.loadMore();
      expect(cubit.state.items.first.id, 40);
      expect(cubit.state.items.last.id, 5);
      expect(cubit.state.items.where((n) => n.id == 11), hasLength(1));
      expect(cubit.state.hasMore, isFalse);
    });

    test('a failed page needs an explicit retry', () async {
      inboxReturns(_range(40, 11), hasMore: true);
      await cubit.setUser('u1');
      when(() => repository.inbox(before: 11)).thenThrow(_network);
      await cubit.loadMore();
      expect(cubit.state.moreFailure, _network);
      await cubit.loadMore();
      verify(() => repository.inbox(before: 11)).called(1);
      when(() => repository.inbox(before: 11)).thenAnswer((_) async => Paged(_range(10, 1), hasMore: false));
      await cubit.loadMore(retry: true);
      expect(cubit.state.items, hasLength(40));
    });

    test('a reload keeps the older pages below the new head', () async {
      inboxReturns(_range(40, 11), hasMore: true);
      await cubit.setUser('u1');
      when(() => repository.inbox(before: 11)).thenAnswer((_) async => Paged(_range(10, 1), hasMore: false));
      await cubit.loadMore();
      // A new notification arrives: the head moves by one.
      inboxReturns(_range(41, 12), hasMore: true);
      await cubit.load();
      expect(cubit.state.items.first.id, 41);
      expect(cubit.state.items.last.id, 1);
      expect(cubit.state.items, hasLength(41));
      expect(cubit.state.hasMore, isFalse);
    });
  });

  group('mark as read (COU-181)', () {
    test('one: at once in the list and the badge', () async {
      inboxReturns([notificationFixture(id: 2), notificationFixture(id: 1)]);
      await cubit.setUser('u1');
      final future = cubit.markRead(cubit.state.items.first);
      expect(cubit.state.items.first.isRead, isTrue);
      expect(cubit.state.unread, 1);
      await future;
      verify(() => repository.markRead([2])).called(1);
    });

    test('an already read one or a double tap sends nothing more', () async {
      final pending = Completer<void>();
      when(() => repository.markRead(any())).thenAnswer((_) => pending.future);
      inboxReturns([notificationFixture(id: 2), notificationFixture(id: 1, readAt: DateTime.utc(2026))]);
      await cubit.setUser('u1');
      final unread = cubit.state.items.first;
      unawaited(cubit.markRead(unread));
      unawaited(cubit.markRead(unread));
      await cubit.markRead(cubit.state.items.last);
      pending.complete();
      await Future<void>.delayed(Duration.zero);
      verify(() => repository.markRead(any())).called(1);
    });

    test('a failure puts it back and reports', () async {
      when(() => repository.markRead(any())).thenThrow(_network);
      inboxReturns([notificationFixture(id: 2)]);
      await cubit.setUser('u1');
      await cubit.markRead(cubit.state.items.single);
      expect(cubit.state.items.single.isRead, isFalse);
      expect(cubit.state.unread, 1);
      expect(cubit.state.actionFailure, const InboxActionFailure(1, _network));
    });

    test('all: every loaded one and the badge to zero', () async {
      inboxReturns(_range(3, 1), unread: 12);
      await cubit.setUser('u1');
      await cubit.markAllRead();
      expect(cubit.state.items.every((n) => n.isRead), isTrue);
      expect(cubit.state.unread, 0);
      expect(cubit.state.markingAll, isFalse);
      verify(repository.markAllRead).called(1);
    });

    test('all: nothing unread sends nothing', () async {
      inboxReturns(_range(3, 1, read: true));
      await cubit.setUser('u1');
      await cubit.markAllRead();
      verifyNever(repository.markAllRead);
    });

    test('all: a failure restores the previous state and reports', () async {
      when(repository.markAllRead).thenThrow(_network);
      inboxReturns(_range(3, 1));
      await cubit.setUser('u1');
      await cubit.markAllRead();
      expect(cubit.state.items.every((n) => !n.isRead), isTrue);
      expect(cubit.state.unread, 3);
      expect(cubit.state.actionFailure?.failure, _network);
    });
  });

  group('live with Realtime (COU-182)', () {
    late StreamController<void> live;
    late bool cancelled;

    setUp(() {
      cancelled = false;
      live = StreamController<void>(onCancel: () => cancelled = true);
      when(() => repository.changes('u1')).thenAnswer((_) => live.stream);
    });

    test('a change reloads the head and the badge', () async {
      inboxReturns([notificationFixture(id: 1)]);
      await cubit.setUser('u1');
      inboxReturns([notificationFixture(id: 2, kind: NotificationKind.budgetExceeded), notificationFixture(id: 1)]);
      live.add(null);
      await pumpEventQueue();
      expect(cubit.state.items.map((n) => n.id), [2, 1]);
      expect(cubit.state.unread, 2);
    });

    test('signing out closes the channel and later signals do nothing', () async {
      inboxReturns([notificationFixture(id: 1)]);
      await cubit.setUser('u1');
      await cubit.setUser(null);
      expect(cancelled, isTrue);
      expect(cubit.state, const NotificationsState());
    });

    test('another account gets its own channel', () async {
      inboxReturns(const []);
      await cubit.setUser('u1');
      when(() => repository.changes('u2')).thenAnswer((_) => const Stream.empty());
      await cubit.setUser('u2');
      expect(cancelled, isTrue);
      verify(() => repository.changes('u2')).called(1);
    });

    test('closing the cubit closes the channel', () async {
      inboxReturns(const []);
      await cubit.setUser('u1');
      await cubit.close();
      expect(cancelled, isTrue);
    });
  });

  group('markReadById (tapped push · COU-199)', () {
    test('a loaded one goes through the list', () async {
      inboxReturns([notificationFixture(id: 4)]);
      await cubit.setUser('u1');
      await cubit.markReadById(4);
      expect(cubit.state.items.single.isRead, isTrue);
      verify(() => repository.markRead([4])).called(1);
    });

    test('one not loaded: straight to the API, then the badge reloads', () async {
      inboxReturns([notificationFixture(id: 4)]);
      await cubit.setUser('u1');
      clearInteractions(repository);
      await cubit.markReadById(99);
      verify(() => repository.markRead([99])).called(1);
      verify(() => repository.unreadCount()).called(1);
    });

    test('signed out: nothing', () async {
      await cubit.markReadById(99);
      verifyNever(() => repository.markRead(any()));
    });
  });
}
