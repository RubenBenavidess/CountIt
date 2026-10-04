import 'dart:async';

import 'package:countit_app/app/push/push_messaging.dart';

/// Drives [PushMessaging] from a test: tokens, rotations and messages.
class FakePushMessaging implements PushMessaging {
  FakePushMessaging({this.token = 'token-1', this.isAvailable = true, this.platform = 'android', this.initial});

  String? token;
  PushMessage? initial;
  final calls = <String>[];
  final refresh = StreamController<String>.broadcast();
  final foreground = StreamController<PushMessage>.broadcast();
  final opened = StreamController<PushMessage>.broadcast();

  @override
  final bool isAvailable;

  @override
  final String? platform;

  @override
  Future<String?> getToken() async {
    calls.add('getToken');
    return token;
  }

  @override
  Stream<String> get onTokenRefresh => refresh.stream;

  @override
  Future<void> deleteToken() async {
    calls.add('deleteToken');
    token = null;
  }

  @override
  Stream<PushMessage> get foregroundMessages => foreground.stream;

  @override
  Stream<PushMessage> get openedMessages => opened.stream;

  @override
  Future<PushMessage?> initialMessage() async => initial;
}
