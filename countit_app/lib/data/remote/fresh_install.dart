import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../app/logging/app_logger.dart';

/// Forgets the secrets of a previous installation (MASVS-STORAGE).
///
/// iOS keeps Keychain items after the app is deleted, so a reinstall would
/// silently restore the last session and install id. Preferences, unlike the
/// Keychain, go away with the app: without the marker this is the first run
/// of this installation and the secure storage is wiped before Supabase reads
/// it. On Android the Keystore data goes with the app anyway (no backups).
abstract final class FreshInstall {
  static const marker = 'countit.installed';

  static Future<void> forgetPreviousInstall({
    SharedPreferencesAsync? preferences,
    FlutterSecureStorage storage = const FlutterSecureStorage(),
  }) async {
    try {
      final prefs = preferences ?? SharedPreferencesAsync();
      if (await prefs.getBool(marker) ?? false) return;
      await storage.deleteAll();
      await prefs.setBool(marker, true);
    } on Exception catch (e) {
      // Never block start-up: the worst case is the previous session staying.
      AppLogger.warning('fresh install check failed: ${e.runtimeType}');
    }
  }
}
