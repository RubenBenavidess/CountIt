import 'package:countit_app/data/dtos/notification.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('NotificationKind.parse', () {
    test('every backend kind (public.notification_kind)', () {
      expect(NotificationKind.values.map((k) => k.apiValue), [
        'family_invitation',
        'budget_warning',
        'budget_exceeded',
        'scheduled_executed',
        'plan_expiring',
        'plan_expired',
        'password_changed',
      ]);
      for (final kind in NotificationKind.values) {
        expect(NotificationKind.parse(kind.apiValue), kind);
      }
    });

    test('unknown, missing or non-string kinds are null', () {
      expect(NotificationKind.parse('wallet_deleted'), isNull);
      expect(NotificationKind.parse(null), isNull);
      expect(NotificationKind.parse(3), isNull);
    });
  });

  group('AppNotification.fromJson (v_notifications)', () {
    test('a full row', () {
      final n = AppNotification.fromJson({
        'notification_id': 41,
        'kind': 'budget_exceeded',
        'title': 'Presupuesto excedido',
        'body': '«Comida» en «Casa»',
        'data': {'budget_id': 3, 'wallet_id': 7},
        'created_at': '2026-10-03T15:00:00+00:00',
        'read_at': null,
      });
      expect(n.id, 41);
      expect(n.kind, NotificationKind.budgetExceeded);
      expect(n.data, {'budget_id': 3, 'wallet_id': 7});
      expect(n.createdAt, DateTime.utc(2026, 10, 3, 15));
      expect(n.isRead, isFalse);
    });

    test('tolerates an unknown kind, missing texts and a non-object data', () {
      final n = AppNotification.fromJson({
        'notification_id': 2,
        'kind': 'something_new',
        'data': 'oops',
        'created_at': 'not a date',
        'read_at': '2026-10-03T16:00:00Z',
      });
      expect(n.kind, isNull);
      expect(n.title, '');
      expect(n.data, isEmpty);
      expect(n.isRead, isTrue);
    });

    test('data cannot be modified by the UI', () {
      final n = AppNotification.fromJson({
        'notification_id': 2,
        'kind': 'plan_expired',
        'data': <String, dynamic>{'wallet_id': 1},
        'created_at': '2026-10-03T16:00:00Z',
      });
      expect(() => n.data['wallet_id'] = 9, throwsUnsupportedError);
    });

    test('withReadAt marks and unmarks', () {
      final n = AppNotification.fromJson({'notification_id': 2, 'kind': 'plan_expired', 'created_at': null});
      final read = n.withReadAt(DateTime.utc(2026));
      expect(read.isRead, isTrue);
      expect(read.withReadAt(null), n);
    });
  });
}
