import 'dart:async';

import 'package:countit_app/app/push/push_open_handler.dart';
import 'package:countit_app/presentation/notifications/view/push_notice_host.dart';
import 'package:countit_app/presentation/notifications/view/widgets/push_permission_card.dart';
import 'package:countit_app/shared/platform/notification_permission.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../../helpers/fake_push_messaging.dart';
import '../../helpers/mocks.dart';
import '../../helpers/pump_app.dart';

void main() {
  group('PushPermissionCard (COU-175)', () {
    late MockNotificationPermission permission;

    setUp(() {
      permission = MockNotificationPermission();
      when(permission.openSettings).thenAnswer((_) async => true);
    });

    Future<void> pump(WidgetTester tester, {bool available = true}) async {
      await tester.pumpApp(
        const PushPermissionCard(),
        pushMessaging: FakePushMessaging(isAvailable: available),
        notificationPermission: permission,
      );
      await tester.pumpAndSettle();
    }

    testWidgets('push not configured: never asks', (tester) async {
      await pump(tester, available: false);
      expect(find.byKey(const ValueKey('push-permission-card')), findsNothing);
      verifyNever(permission.status);
    });

    testWidgets('not asked yet: «Activar» shows the system dialog; granted hides the card', (tester) async {
      when(permission.status).thenAnswer((_) async => NotificationPermissionStatus.notDetermined);
      when(permission.request).thenAnswer((_) async => NotificationPermissionStatus.granted);
      await pump(tester);
      expect(find.textContaining('Activa las notificaciones'), findsOneWidget);

      await tester.tap(find.text('Activar'));
      await tester.pumpAndSettle();
      verify(permission.request).called(1);
      expect(find.byKey(const ValueKey('push-permission-card')), findsNothing);
    });

    testWidgets('denied: only the settings can change it', (tester) async {
      when(permission.status).thenAnswer((_) async => NotificationPermissionStatus.denied);
      await pump(tester);
      await tester.tap(find.text('Abrir ajustes'));
      await tester.pumpAndSettle();
      verify(permission.openSettings).called(1);
      verifyNever(permission.request);
    });

    testWidgets('«Ahora no» hides it; granted or unsupported never shows it', (tester) async {
      when(permission.status).thenAnswer((_) async => NotificationPermissionStatus.notDetermined);
      await pump(tester);
      await tester.tap(find.text('Ahora no'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('push-permission-card')), findsNothing);

      for (final status in [NotificationPermissionStatus.granted, NotificationPermissionStatus.unsupported]) {
        when(permission.status).thenAnswer((_) async => status);
        await pump(tester);
        expect(find.byKey(const ValueKey('push-permission-card')), findsNothing);
      }
    });
  });

  testWidgets('PushNoticeHost: a foreground push shows a snackbar with «Ver» (COU-179)', (tester) async {
    final notices = StreamController<PushNotice>.broadcast();
    addTearDown(notices.close);
    final opened = <String>[];
    await tester.pumpApp(PushNoticeHost(notices: notices.stream, onOpen: opened.add, child: const SizedBox.expand()));

    notices.add(const PushNotice(title: 'Presupuesto excedido', body: '«Comida» en «Casa»', location: '/wallets/2'));
    await tester.pumpAndSettle();
    expect(find.text('Presupuesto excedido'), findsOneWidget);
    expect(find.text('«Comida» en «Casa»'), findsOneWidget);

    await tester.tap(find.text('Ver'));
    await tester.pumpAndSettle();
    expect(opened, ['/wallets/2']);
  });
}
