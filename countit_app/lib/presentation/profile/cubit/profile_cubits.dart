import 'dart:convert';

import 'package:clock/clock.dart';

import '../../../app/session/session_cubit.dart';
import '../../../data/dtos/profile.dart';
import '../../../data/repositories/profile_repository.dart';
import '../../../shared/platform/file_sharer.dart';
import '../../../shared/state/submit_cubit.dart';
import '../../../shared/utils/dates.dart';

/// HU-05: edit names, username and time zone (COU-144, COU-146).
class EditProfileCubit extends SubmitCubit {
  EditProfileCubit({required this._profiles, required this._session});

  final ProfileRepository _profiles;
  final SessionCubit _session;

  Future<bool> save({
    required Profile original,
    required String firstName,
    required String lastName,
    required String username,
    required String timezone,
  }) => submit(() async {
    final newUsername = username.trim();
    await _profiles.updateMyProfile(
      firstName: firstName.trim(),
      lastName: lastName.trim(),
      // Only real changes: a username change is audited and may be taken.
      username: newUsername == original.username ? null : newUsername,
      timezone: timezone == original.timezone ? null : timezone,
    );
    // The whole app (dates, «hoy») follows the refreshed profile.
    await _session.refreshProfile();
  });
}

/// HU-29: download everything as JSON and share it (COU-148).
class ExportDataCubit extends SubmitCubit {
  ExportDataCubit({required this._profiles, required this._sharer});

  final ProfileRepository _profiles;
  final FileSharer _sharer;

  static String fileName(DateTime day) => 'countit-datos-${Dates.toApi(day)}.json';

  Future<bool> export() => submit(() async {
    final data = await _profiles.exportMyData();
    await _sharer.shareJson(
      fileName: fileName(clock.now()),
      contents: const JsonEncoder.withIndent('  ').convert(data),
      subject: 'Mis datos de Count It!',
    );
  });
}
