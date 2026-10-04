import '../../data/dtos/notification.dart';
import 'app_router.dart';

/// Where a notification leads (HU-31 · COU-180), for the inbox and for a
/// tapped push alike.
///
/// Pure and defensive: `data` comes from the database through the inbox or
/// through FCM (where every value is a string) and is treated as untrusted.
/// Only known kinds map to a fixed set of app screens; ids must be positive
/// 32-bit integers (`wallet_id`, `budget_id`… are `integer` in the database).
/// Anything else (unknown kind, missing or malformed id, extra keys, paths
/// or URLs inside `data`) leads nowhere: the caller stays where it is.
abstract final class NotificationRoutes {
  static const _maxInt = 2147483647;

  /// Largest integer exact on every platform (web doubles).
  static const _maxSafe = 9007199254740991;
  static final _decimal = RegExp(r'^[1-9][0-9]{0,15}$');

  /// The location to open for a notification of [kind] with [data]; null
  /// when it has no screen or its data is not trustworthy.
  static String? locationFor(NotificationKind? kind, Map<String, Object?> data) {
    switch (kind) {
      case NotificationKind.familyInvitation:
        // The wallet is not readable before accepting: the invitations list.
        return AppRoutes.invitations;
      case NotificationKind.budgetWarning || NotificationKind.budgetExceeded:
        // Budgets live in the wallet screen. A malformed budget id means the
        // payload is not what the backend sends: ignore it entirely.
        final wallet = parseId(data['wallet_id']);
        final budget = data['budget_id'];
        if (wallet == null || (budget != null && parseId(budget) == null)) return null;
        return AppRoutes.wallet(wallet);
      case NotificationKind.scheduledExecuted:
        final wallet = parseId(data['wallet_id']);
        final rule = data['scheduled_transaction_id'];
        if (wallet == null || (rule != null && parseId(rule) == null)) return null;
        return AppRoutes.scheduled(wallet);
      case NotificationKind.planExpiring || NotificationKind.planExpired:
        return AppRoutes.myPlan;
      case NotificationKind.passwordChanged:
        // Account security: change it again (or sign out from «Perfil»).
        return AppRoutes.changePassword;
      case null:
        return null;
    }
  }

  /// A push payload (`data.kind`, `data.notification_id` and the ids, all
  /// strings in FCM): its location, or null.
  static String? locationForPush(Map<String, Object?> data) => locationFor(NotificationKind.parse(data['kind']), data);

  /// `data.notification_id` of a push (a `bigint`), to mark it as read when opened.
  static int? notificationIdOfPush(Map<String, Object?> data) => parseId(data['notification_id'], bigint: true);

  /// A positive integer id from an `int` or a plain decimal string; null for
  /// anything else (doubles, signs, spaces, leading zeros, overflow,
  /// booleans…). Ids are 32-bit (`integer`) unless [bigint].
  static int? parseId(Object? value, {bool bigint = false}) {
    final id = switch (value) {
      int() => value,
      String() when _decimal.hasMatch(value) => int.tryParse(value),
      _ => null,
    };
    return id != null && id > 0 && id <= (bigint ? _maxSafe : _maxInt) ? id : null;
  }
}
