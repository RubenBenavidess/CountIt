import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

/// Opens the inbox of the device's e-mail app (COU-110). Android uses an
/// `APP_EMAIL` intent (MainActivity); iOS opens Mail with `message://`.
class MailLauncher {
  const MailLauncher();

  static const channel = MethodChannel('ec.countit.app/mail');

  /// False when no e-mail app could be opened.
  Future<bool> openInbox() async {
    try {
      return switch (defaultTargetPlatform) {
        TargetPlatform.android => await channel.invokeMethod<bool>('openInbox') ?? false,
        TargetPlatform.iOS => await launchUrl(Uri.parse('message://')),
        _ => false,
      };
    } on PlatformException {
      return false;
    }
  }
}
