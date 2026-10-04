import 'dart:math';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Random per-install identifier sent as `x-device-id` so the backend rate
/// limits per device. Not tied to the hardware or the user.
abstract final class InstallId {
  static const key = 'countit.install_id';

  static Future<String> load({FlutterSecureStorage storage = const FlutterSecureStorage()}) async {
    final existing = await storage.read(key: key);
    if (existing != null && existing.isNotEmpty) return existing;
    final random = Random.secure();
    final id = List.generate(16, (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
    await storage.write(key: key, value: id);
    return id;
  }
}
