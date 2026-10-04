import 'package:equatable/equatable.dart';

import 'json_parsing.dart';

/// `public.notification_kind`: the events the database notifies (HU-31).
enum NotificationKind {
  familyInvitation('family_invitation'),

  /// A budget of one of my wallets reached 80 % of its period.
  budgetWarning('budget_warning'),

  /// A budget went over its limit (only this one when it jumps past 100 %).
  budgetExceeded('budget_exceeded'),

  /// A scheduled payment or income of mine was registered.
  scheduledExecuted('scheduled_executed'),

  /// My paid plan expires in 3 days.
  planExpiring('plan_expiring'),

  /// My paid plan expired: back to Regular.
  planExpired('plan_expired'),

  /// Security alert: the password of the account changed.
  passwordChanged('password_changed');

  const NotificationKind(this.apiValue);

  final String apiValue;

  /// Null for a missing or unknown kind (a newer API): shown, never routed.
  static NotificationKind? parse(Object? value) {
    for (final kind in values) {
      if (kind.apiValue == value) return kind;
    }
    return null;
  }
}

/// A row of `api.v_notifications`: my in-app inbox (HU-31 · COU-30).
///
/// [title] and [body] are written by the database in Spanish; [data] holds
/// the ids of what the notification is about (`wallet_id`, `budget_id`,
/// `scheduled_transaction_id`). It is untrusted input: whoever reads it must
/// validate types and ids (see `NotificationRoutes`).
class AppNotification extends Equatable {
  const AppNotification({
    required this.id,
    required this.kind,
    required this.title,
    required this.body,
    required this.createdAt,
    this.data = const {},
    this.readAt,
  });

  factory AppNotification.fromJson(Map<String, dynamic> json) {
    final data = json['data'];
    return AppNotification(
      id: (json['notification_id'] as num).toInt(),
      kind: NotificationKind.parse(json['kind']),
      title: (json['title'] as String?) ?? '',
      body: (json['body'] as String?) ?? '',
      data: data is Map ? Map<String, Object?>.unmodifiable(Map<String, Object?>.from(data)) : const {},
      createdAt: parseTimestamp(json['created_at']) ?? DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      readAt: parseTimestamp(json['read_at']),
    );
  }

  /// `notification_id`: grows with every notification (newest = highest).
  final int id;

  /// Null when the API sent a kind this version does not know.
  final NotificationKind? kind;
  final String title;
  final String body;
  final Map<String, Object?> data;
  final DateTime createdAt;
  final DateTime? readAt;

  bool get isRead => readAt != null;

  /// This notification read at [at] (or unread again with null).
  AppNotification withReadAt(DateTime? at) =>
      AppNotification(id: id, kind: kind, title: title, body: body, data: data, createdAt: createdAt, readAt: at);

  @override
  List<Object?> get props => [id, kind, title, body, data, createdAt, readAt];
}
