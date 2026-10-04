import 'package:countit_app/app/router/app_router.dart';
import 'package:countit_app/app/router/notification_routes.dart';
import 'package:countit_app/data/dtos/notification.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('locationFor: every backend kind (COU-180)', () {
    test('family_invitation → invitations (the wallet is not readable yet)', () {
      expect(
        NotificationRoutes.locationFor(NotificationKind.familyInvitation, {'wallet_id': 5}),
        AppRoutes.invitations,
      );
      expect(NotificationRoutes.locationFor(NotificationKind.familyInvitation, const {}), AppRoutes.invitations);
    });

    test('budget_warning / budget_exceeded → the wallet with the budget', () {
      for (final kind in [NotificationKind.budgetWarning, NotificationKind.budgetExceeded]) {
        expect(NotificationRoutes.locationFor(kind, {'budget_id': 9, 'wallet_id': 2}), '/wallets/2');
      }
    });

    test('scheduled_executed → the wallet\'s scheduled list', () {
      expect(
        NotificationRoutes.locationFor(NotificationKind.scheduledExecuted, {
          'scheduled_transaction_id': 4,
          'wallet_id': 2,
        }),
        '/wallets/2/scheduled',
      );
    });

    test('plan_expiring / plan_expired → «Mi plan»; password_changed → account security', () {
      expect(NotificationRoutes.locationFor(NotificationKind.planExpiring, const {}), AppRoutes.myPlan);
      expect(NotificationRoutes.locationFor(NotificationKind.planExpired, const {}), AppRoutes.myPlan);
      expect(NotificationRoutes.locationFor(NotificationKind.passwordChanged, const {}), AppRoutes.changePassword);
    });
  });

  group('untrusted data leads nowhere', () {
    test('unknown kinds', () {
      expect(NotificationRoutes.locationFor(null, {'wallet_id': 2}), isNull);
      expect(NotificationRoutes.locationForPush({'kind': 'admin_panel', 'wallet_id': '2'}), isNull);
      expect(NotificationRoutes.locationForPush({'wallet_id': '2'}), isNull);
    });

    test('missing or malformed wallet ids', () {
      const kind = NotificationKind.budgetWarning;
      for (final bad in <Object?>[
        null,
        0,
        -3,
        2.5,
        true,
        '',
        ' 2',
        '+2',
        '02',
        '2/../../admin',
        '/admin',
        'https://evil.example',
        '2147483648',
        2147483648,
        '99999999999999999999',
        <String, Object?>{},
      ]) {
        expect(NotificationRoutes.locationFor(kind, {'wallet_id': bad, 'budget_id': 1}), isNull, reason: '$bad');
      }
    });

    test('a malformed related id voids the whole payload', () {
      expect(
        NotificationRoutes.locationFor(NotificationKind.budgetExceeded, {'wallet_id': 2, 'budget_id': 'x'}),
        isNull,
      );
      expect(
        NotificationRoutes.locationFor(NotificationKind.scheduledExecuted, {
          'wallet_id': 2,
          'scheduled_transaction_id': -1,
        }),
        isNull,
      );
    });

    test('extra keys never become routes', () {
      expect(
        NotificationRoutes.locationFor(NotificationKind.planExpired, {'route': '/admin', 'location': '/admin/audit'}),
        AppRoutes.myPlan,
      );
    });
  });

  group('push payloads (strings, as FCM sends them)', () {
    test('kind and ids as strings', () {
      final data = {'kind': 'budget_exceeded', 'notification_id': '69', 'budget_id': '9', 'wallet_id': '2'};
      expect(NotificationRoutes.locationForPush(data), '/wallets/2');
      expect(NotificationRoutes.notificationIdOfPush(data), 69);
    });

    test('notification ids are bigint but still validated', () {
      expect(NotificationRoutes.notificationIdOfPush({'notification_id': '3000000000'}), 3000000000);
      expect(NotificationRoutes.notificationIdOfPush({'notification_id': '-1'}), isNull);
      expect(NotificationRoutes.notificationIdOfPush(const {}), isNull);
    });
  });
}
