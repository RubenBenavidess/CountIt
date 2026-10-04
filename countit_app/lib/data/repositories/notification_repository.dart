import '../dtos/notification.dart';
import '../dtos/paged.dart';
import '../remote/api_client.dart';
import '../remote/realtime_watcher.dart';

/// My notifications (HU-31 · COU-30): the inbox comes from
/// `api.v_notifications` (only my rows, by RLS) and reading them is
/// `mark_notifications_read`. The database produces them; the app never
/// creates or deletes one. New ones and read marks from other devices arrive
/// through Realtime on `public.notifications` (whose policy also requires a
/// live session), encapsulated here (COU-182).
abstract interface class NotificationRepository {
  static const pageSize = 30;

  /// The badge counts at most this many; more shows «99+».
  static const unreadCap = 100;

  /// Newest first. [before] continues after the last id of the previous page
  /// (keyset paging: new notifications never shift the next page).
  Future<Paged<AppNotification>> inbox({int? before, int limit = pageSize});

  /// Unread notifications, up to [unreadCap].
  Future<int> unreadCount();

  /// `mark_notifications_read(p_ids)`: the ones that were already read (or
  /// are not mine) are ignored by the API.
  Future<void> markRead(List<int> ids);

  /// `mark_notifications_read()` without ids: every unread one, loaded or not.
  Future<void> markAllRead();

  /// Signals a change of [userId]'s notifications (a new one, read on
  /// another device…) and every Realtime (re)join, so changes missed while
  /// disconnected are recovered by reloading. Cancel to close the channel.
  Stream<void> changes(String userId);
}

class SupabaseNotificationRepository implements NotificationRepository {
  SupabaseNotificationRepository(this._api, this._realtime);

  final ApiClient _api;
  final RealtimeWatcher _realtime;

  static const view = 'v_notifications';
  static const table = 'notifications';
  static const columns = 'notification_id,kind,title,body,data,created_at,read_at';

  @override
  Future<Paged<AppNotification>> inbox({int? before, int limit = NotificationRepository.pageSize}) async {
    final rows = await _api.select(
      view,
      columns: columns,
      query: (q) {
        final filtered = before == null ? q : q.lt('notification_id', before);
        // One extra row tells whether another page exists.
        return filtered.order('notification_id', ascending: false).limit(limit + 1);
      },
    );
    final items = [
      for (final row in rows)
        if (row['notification_id'] is num) AppNotification.fromJson(row),
    ];
    final hasMore = items.length > limit;
    return Paged(List.unmodifiable(hasMore ? items.take(limit) : items), hasMore: hasMore);
  }

  @override
  Future<int> unreadCount() async {
    final rows = await _api.select(
      view,
      columns: 'notification_id',
      query: (q) => q.isFilter('read_at', null).limit(NotificationRepository.unreadCap),
    );
    return rows.length;
  }

  @override
  Future<void> markRead(List<int> ids) async {
    if (ids.isEmpty) return;
    await _api.rpc<dynamic>('mark_notifications_read', params: {'p_ids': ids});
  }

  @override
  Future<void> markAllRead() => _api.rpc<dynamic>('mark_notifications_read');

  @override
  Stream<void> changes(String userId) => _realtime.watch(RealtimeTopic(table: table, column: 'user_id', value: userId));
}
