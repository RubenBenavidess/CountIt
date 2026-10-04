import 'package:countit_app/app/errors/app_failure.dart';
import 'package:countit_app/data/dtos/notification.dart';
import 'package:countit_app/data/dtos/paged.dart';
import 'package:countit_app/presentation/notifications/cubit/notifications_cubit.dart';
import 'package:countit_app/presentation/notifications/view/notifications_page.dart';
import 'package:countit_app/shared/utils/dates.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../../helpers/mocks.dart';
import '../../helpers/notification_fixtures.dart';
import '../../helpers/pump_app.dart';

const _network = AppFailure(kind: FailureKind.network, message: 'Sin conexión. Revisa tu internet.');

void main() {
  late MockNotificationRepository repository;
  late NotificationsCubit cubit;

  setUpAll(Dates.init);

  setUp(() {
    repository = noNotifications();
    cubit = NotificationsCubit(repository);
  });

  tearDown(() => cubit.close());

  void inboxReturns(List<AppNotification> items, {bool hasMore = false}) {
    when(() => repository.inbox()).thenAnswer((_) async => Paged(items, hasMore: hasMore));
    when(repository.unreadCount).thenAnswer((_) async => items.where((n) => !n.isRead).length);
  }

  Future<void> pumpInbox(WidgetTester tester) async {
    await cubit.setUser('u1');
    await tester.pumpApp(const NotificationsPage(), notifications: repository, notificationsCubit: cubit);
    await tester.pumpAndSettle();
  }

  testWidgets('empty inbox explains what will show up', (tester) async {
    await pumpInbox(tester);
    expect(find.text('No tienes notificaciones'), findsOneWidget);
    expect(find.byKey(const ValueKey('notifications-mark-all')), findsNothing);
  });

  testWidgets('a failed first load offers a retry', (tester) async {
    when(() => repository.inbox()).thenThrow(_network);
    await pumpInbox(tester);
    expect(find.text(_network.message), findsOneWidget);

    inboxReturns([notificationFixture()]);
    await tester.tap(find.text('Reintentar'));
    await tester.pumpAndSettle();
    expect(find.text('Presupuesto al 80 %'), findsOneWidget);
  });

  testWidgets('unread and read rows say so to screen readers (COU-108)', (tester) async {
    final semantics = tester.ensureSemantics();
    inboxReturns([
      notificationFixture(
        id: 2,
        title: 'Nueva invitación',
        body: 'Te invitaron',
        kind: NotificationKind.familyInvitation,
      ),
      notificationFixture(id: 1, readAt: DateTime.utc(2026, 10, 3, 16)),
    ]);
    await pumpInbox(tester);

    expect(find.bySemanticsLabel(RegExp(r'^No leída\. Nueva invitación\. Te invitaron\. ')), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp(r'^Leída\. Presupuesto al 80 %')), findsOneWidget);
    expect(find.byKey(const ValueKey('notification-unread-dot')), findsOneWidget);
    // Touch targets of at least 44 px.
    expect(tester.getSize(find.byKey(const ValueKey('notification-2'))).height, greaterThanOrEqualTo(44));
    semantics.dispose();
  });

  testWidgets('tapping an unread one marks it as read (COU-181)', (tester) async {
    inboxReturns([notificationFixture(id: 5)]);
    await pumpInbox(tester);

    await tester.tap(find.byKey(const ValueKey('notification-5')));
    await tester.pumpAndSettle();
    verify(() => repository.markRead([5])).called(1);
    expect(find.byKey(const ValueKey('notification-unread-dot')), findsNothing);
    expect(cubit.state.unread, 0);
  });

  testWidgets('«Marcar todas como leídas» reads everything and hides itself', (tester) async {
    inboxReturns([notificationFixture(id: 2), notificationFixture(id: 1)]);
    await pumpInbox(tester);

    await tester.tap(find.byTooltip('Marcar todas como leídas'));
    await tester.pumpAndSettle();
    verify(repository.markAllRead).called(1);
    expect(find.byKey(const ValueKey('notification-unread-dot')), findsNothing);
    expect(find.byKey(const ValueKey('notifications-mark-all')), findsNothing);
  });

  testWidgets('a failed «mark as read» restores the row and shows the error', (tester) async {
    when(() => repository.markRead(any())).thenThrow(_network);
    inboxReturns([notificationFixture(id: 5)]);
    await pumpInbox(tester);

    await tester.tap(find.byKey(const ValueKey('notification-5')));
    await tester.pumpAndSettle();
    expect(find.text(_network.message), findsOneWidget);
    expect(find.byKey(const ValueKey('notification-unread-dot')), findsOneWidget);
  });

  testWidgets('scrolling to the end loads the next page lazily', (tester) async {
    inboxReturns([for (var id = 40; id > 10; id--) notificationFixture(id: id)], hasMore: true);
    when(() => repository.inbox(before: 11))
        .thenAnswer((_) async => Paged([notificationFixture(id: 10, title: 'La más antigua')], hasMore: false));
    await pumpInbox(tester);
    // Only the visible rows are built.
    expect(find.byKey(const ValueKey('notification-11')), findsNothing);

    await tester.scrollUntilVisible(find.text('La más antigua'), 500);
    await tester.pumpAndSettle();
    verify(() => repository.inbox(before: 11)).called(1);
    expect(find.byKey(const ValueKey('notifications-footer')), findsNothing);
  });
}
