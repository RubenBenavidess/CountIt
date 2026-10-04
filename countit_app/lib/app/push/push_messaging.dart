import 'package:equatable/equatable.dart';

/// A push as the app receives it: what the system shows plus `data`
/// (`kind`, `notification_id` and ids, all strings). `data` is untrusted:
/// it goes through `NotificationRoutes` before anything uses it.
class PushMessage extends Equatable {
  const PushMessage({this.title, this.body, this.data = const {}});

  final String? title;
  final String? body;
  final Map<String, Object?> data;

  @override
  List<Object?> get props => [title, body, data];
}

/// The push provider seam (FCM). The app only talks to this interface, so the
/// real implementation (`firebase_messaging`, see docs/PUSH.md) plugs in
/// without touching the session, the inbox or the router.
///
/// Implementations never log tokens or message contents.
abstract interface class PushMessaging {
  /// False while the provider is not configured: nothing is registered and
  /// the app does not ask for the notifications permission.
  bool get isAvailable;

  /// `android` | `ios` (what `register_push_device` expects); null when unsupported.
  String? get platform;

  /// This installation's token, or null when there is none (yet).
  Future<String?> getToken();

  /// New tokens after a rotation (COU-177).
  Stream<String> get onTokenRefresh;

  /// Invalidates this installation's token (sign-out): a push to the old
  /// token fails and the backend forgets it.
  Future<void> deleteToken();

  /// Pushes received while the app is in the foreground (COU-179): the
  /// system does not show them, the app does.
  Stream<PushMessage> get foregroundMessages;

  /// Pushes the user tapped while the app was in the background (COU-199).
  Stream<PushMessage> get openedMessages;

  /// The push that launched the app from a terminated state, once (COU-199).
  Future<PushMessage?> initialMessage();
}

/// Default until Firebase is configured (COU-28/COU-103): no token, no
/// messages. The inbox still works in real time through Realtime.
class NoopPushMessaging implements PushMessaging {
  const NoopPushMessaging();

  @override
  bool get isAvailable => false;

  @override
  String? get platform => null;

  @override
  Future<String?> getToken() async => null;

  @override
  Stream<String> get onTokenRefresh => const Stream.empty();

  @override
  Future<void> deleteToken() async {}

  @override
  Stream<PushMessage> get foregroundMessages => const Stream.empty();

  @override
  Stream<PushMessage> get openedMessages => const Stream.empty();

  @override
  Future<PushMessage?> initialMessage() async => null;
}
