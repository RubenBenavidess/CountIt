import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

/// Hands a generated file to the system share sheet (COU-148).
abstract interface class FileSharer {
  Future<void> shareJson({required String fileName, required String contents, String? subject});
}

/// Writes into a private cache folder and opens the share sheet. The receiving
/// app may read the file after the sheet closes, so the previous exports are
/// deleted when a new one starts (and the OS may clear the cache anytime).
class SystemFileSharer implements FileSharer {
  const SystemFileSharer();

  static Future<Directory> _folder() async => Directory('${(await getTemporaryDirectory()).path}/exports');

  /// Deletes every export (the personal data of `export_my_data`): called when
  /// the session ends, so the next user of the device never finds them.
  static Future<void> clearExports() async {
    try {
      final folder = await _folder();
      if (folder.existsSync()) await folder.delete(recursive: true);
    } on Exception {
      // Best effort: the OS may also clear the cache.
    }
  }

  @override
  Future<void> shareJson({required String fileName, required String contents, String? subject}) async {
    final folder = await _folder();
    if (folder.existsSync()) await folder.delete(recursive: true);
    await folder.create(recursive: true);
    final file = File('${folder.path}/$fileName');
    await file.writeAsString(contents, flush: true);
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path, mimeType: 'application/json')],
        subject: subject,
      ),
    );
  }
}
