import 'package:countit_app/app/push/push_messaging.dart';
import 'package:countit_app/app/push/push_open_handler.dart';
import 'package:countit_app/app/router/app_router.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/fake_push_messaging.dart';

const _exceeded = PushMessage(
  title: 'Presupuesto excedido',
  body: '«Comida» en «Casa»',
  data: {'kind': 'budget_exceeded', 'notification_id': '70', 'budget_id': '9', 'wallet_id': '2'},
);

void main() {
  late FakePushMessaging messaging;
  late List<String> navigated;
  late List<int> marked;
  late int refreshed;
  late bool signedIn;
  late PushOpenHandler handler;

  PushOpenHandler build() => PushOpenHandler(
    messaging: messaging,
    isSignedIn: () => signedIn,
    navigate: navigated.add,
    markRead: (id) async => marked.add(id),
    refreshInbox: () => refreshed++,
  );

  setUp(() {
    messaging = FakePushMessaging();
    navigated = [];
    marked = [];
    refreshed = 0;
    signedIn = true;
    handler = build();
  });

  tearDown(() => handler.dispose());

  group('tapped push (COU-199)', () {
    test('background: opens its screen and marks it as read', () async {
      await handler.start();
      messaging.opened.add(_exceeded);
      await pumpEventQueue();
      expect(navigated, ['/wallets/2']);
      expect(marked, [70]);
    });

    test('cold start: the launch message is opened once started', () async {
      messaging.initial = _exceeded;
      await handler.start();
      expect(navigated, ['/wallets/2']);
    });

    test('unknown kind or invalid ids: the inbox, never an arbitrary route', () {
      handler
        ..open(const PushMessage(data: {'kind': 'open_url', 'url': 'https://evil.example'}))
        ..open(const PushMessage(data: {'kind': 'budget_warning', 'wallet_id': '/admin'}));
      expect(navigated, [AppRoutes.notifications, AppRoutes.notifications]);
      expect(marked, isEmpty);
    });

    test('signed out: a push of a previous account opens nothing', () {
      signedIn = false;
      handler.open(_exceeded);
      expect(navigated, isEmpty);
      expect(marked, isEmpty);
    });
  });

  group('foreground push (COU-179)', () {
    test('refreshes the inbox and becomes a notice with its destination', () async {
      await handler.start();
      final notice = handler.notices.first;
      messaging.foreground.add(_exceeded);
      expect(
        await notice,
        const PushNotice(title: 'Presupuesto excedido', body: '«Comida» en «Casa»', location: '/wallets/2'),
      );
      expect(refreshed, 1);
      expect(navigated, isEmpty);
    });

    test('without a title only the inbox refreshes', () async {
      await handler.start();
      var notices = 0;
      handler.notices.listen((_) => notices++);
      messaging.foreground.add(const PushMessage(data: {'kind': 'plan_expired'}));
      await pumpEventQueue();
      expect(refreshed, 1);
      expect(notices, 0);
    });
  });

  test('push not configured: start does nothing', () async {
    final noop = PushOpenHandler(
      messaging: const NoopPushMessaging(),
      isSignedIn: () => true,
      navigate: navigated.add,
      markRead: (_) async {},
      refreshInbox: () => refreshed++,
    );
    await noop.start();
    expect(navigated, isEmpty);
    await noop.dispose();
  });
}
