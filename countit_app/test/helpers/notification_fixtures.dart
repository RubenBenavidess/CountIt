import 'package:countit_app/data/dtos/notification.dart';

/// A notification of the inbox; unread unless [readAt] is given.
AppNotification notificationFixture({
  int id = 1,
  NotificationKind? kind = NotificationKind.budgetWarning,
  String title = 'Presupuesto al 80 %',
  String body = '«Comida» en «Casa»: llevas \$80,00 de \$100,00',
  Map<String, Object?> data = const {'budget_id': 3, 'wallet_id': 7},
  DateTime? createdAt,
  DateTime? readAt,
}) => AppNotification(
  id: id,
  kind: kind,
  title: title,
  body: body,
  data: data,
  createdAt: createdAt ?? DateTime.utc(2026, 10, 3, 15),
  readAt: readAt,
);
