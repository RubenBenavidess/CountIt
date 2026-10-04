import 'dart:async';

import 'package:equatable/equatable.dart';

import '../router/app_router.dart';
import '../router/notification_routes.dart';
import 'push_messaging.dart';

/// A push received in the foreground, for the in-app banner (COU-179).
class PushNotice extends Equatable {
  const PushNotice({required this.title, required this.body, required this.location});

  final String title;
  final String body;

  /// Where «Ver» leads: the validated destination or the inbox.
  final String location;

  @override
  List<Object?> get props => [title, body, location];
}

/// What the app does with pushes (COU-179, COU-199), independent of the
/// provider: a tapped push (background or cold start) opens its screen
/// through [NotificationRoutes] and is marked as read; a push in the
/// foreground refreshes the inbox and becomes a [PushNotice].
///
/// Nothing happens without a signed-in user: a push meant for a previous
/// account never opens anything. Unknown kinds or invalid ids open the inbox,
/// never an arbitrary route.
class PushOpenHandler {
  PushOpenHandler({
    required this._messaging,
    required this._isSignedIn,
    required this._navigate,
    required this._markRead,
    required this._refreshInbox,
  });

  final PushMessaging _messaging;
  final bool Function() _isSignedIn;
  final void Function(String location) _navigate;
  final Future<void> Function(int notificationId) _markRead;
  final void Function() _refreshInbox;

  final _notices = StreamController<PushNotice>.broadcast();
  final _subscriptions = <StreamSubscription<PushMessage>>[];

  /// Foreground pushes to show inside the app.
  Stream<PushNotice> get notices => _notices.stream;

  /// Call once the session is restored (like the auth links), so the cold
  /// start push is not swallowed by the splash redirect.
  Future<void> start() async {
    if (!_messaging.isAvailable) return;
    _subscriptions
      ..add(_messaging.openedMessages.listen(open))
      ..add(_messaging.foregroundMessages.listen(_foreground));
    try {
      final initial = await _messaging.initialMessage();
      if (initial != null) open(initial);
    } catch (_) {
      // No launch message: nothing to open.
    }
  }

  /// The user tapped [message].
  void open(PushMessage message) {
    if (!_isSignedIn()) return;
    final id = NotificationRoutes.notificationIdOfPush(message.data);
    if (id != null) unawaited(_markRead(id).catchError((Object _) {}));
    _navigate(destinationOf(message));
  }

  void _foreground(PushMessage message) {
    if (!_isSignedIn()) return;
    _refreshInbox();
    final title = message.title?.trim() ?? '';
    if (title.isEmpty) return;
    _notices.add(PushNotice(title: title, body: message.body?.trim() ?? '', location: destinationOf(message)));
  }

  /// The validated screen of [message], or the inbox.
  static String destinationOf(PushMessage message) =>
      NotificationRoutes.locationForPush(message.data) ?? AppRoutes.notifications;

  Future<void> dispose() async {
    for (final subscription in _subscriptions) {
      await subscription.cancel();
    }
    await _notices.close();
  }
}
