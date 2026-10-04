import 'package:flutter/foundation.dart' show visibleForTesting;

import '../../../app/errors/app_failure.dart';
import '../../../app/session/session_cubit.dart';
import '../../../data/repositories/auth_repository.dart';
import '../../../shared/state/submit_cubit.dart';

/// HU-06: confirms the password and opens the 5-minute safe mode (COU-147).
///
/// A 429 blocks the confirmation until `Retry-After` (3 attempts per 2
/// minutes per account, 10 per 15 minutes per IP). The block outlives the
/// sheet: closing it and starting the deletion again opens a new cubit that
/// shows the same message and countdown instead of offering a retry the
/// server would reject.
class ReauthCubit extends SubmitCubit {
  ReauthCubit(this._auth, {super.now}) {
    final block = _block;
    if (block != null && block.until.isAfter(now())) {
      emit(SubmitState(status: SubmitStatus.failure, failure: block.failure, blockedUntil: block.until));
    }
  }

  final AuthRepository _auth;

  /// Wait when a 429 comes without `Retry-After`: the account window.
  static const defaultBlock = Duration(minutes: 2);

  /// Last rate limit of this device (the IP layer applies to any account too).
  static ({AppFailure failure, DateTime until})? _block;

  @visibleForTesting
  static void resetBlock() => _block = null;

  bool get blocked => state.blockedUntil?.isAfter(now()) ?? false;

  Future<bool> confirm(String password) async {
    if (blocked) return false;
    final confirmed = await submit(() => _auth.reauthenticate(password));
    final failure = state.failure;
    if (!isClosed && failure?.kind == FailureKind.rateLimited) {
      final until = state.blockedUntil ?? now().add(defaultBlock);
      _block = (failure: failure!, until: until);
      if (state.blockedUntil == null) {
        emit(SubmitState(status: SubmitStatus.failure, failure: failure, blockedUntil: until));
      }
    }
    if (confirmed) _block = null;
    return confirmed;
  }

  /// Hides «Contraseña incorrecta» once the user types again (the field's
  /// forced error would otherwise keep the form invalid); a rate limit stays.
  void passwordEdited() {
    if (state.failure?.kind == FailureKind.invalidCredentials) clearFailure();
  }
}

/// HU-04: change the password (COU-142). The other devices are signed out by
/// Auth; this one keeps going with the fresh session.
class ChangePasswordCubit extends SubmitCubit {
  ChangePasswordCubit({required this._auth, required this._session, super.now});

  final AuthRepository _auth;
  final SessionCubit _session;

  static const signInAgain = 'Tu contraseña cambió. Inicia sesión con la nueva.';

  Future<bool> change({required String currentPassword, required String newPassword}) => submit(() async {
    final kept = await _auth.changePassword(currentPassword: currentPassword, newPassword: newPassword);
    if (!kept) await _session.signOut(message: signInAgain);
  });
}

/// HU-30: delete the account (COU-150). On success nothing of the user stays
/// on the device: the session state is cleared and the SDK forgets the tokens.
class DeleteAccountCubit extends SubmitCubit {
  DeleteAccountCubit({required this._auth, required this._session, super.now});

  final AuthRepository _auth;
  final SessionCubit _session;

  static const farewell = 'Eliminamos tu cuenta y tus datos personales. Gracias por usar Count It!';

  Future<bool> delete(String password) => submit(() async {
    await _auth.deleteAccount(password);
    await _session.signOut(message: farewell);
  });
}
