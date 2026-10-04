import '../../../app/session/session_cubit.dart';
import '../../../data/repositories/auth_repository.dart';
import '../../../shared/state/submit_cubit.dart';

/// HU-06: confirms the password and opens the 5-minute safe mode (COU-147).
class ReauthCubit extends SubmitCubit {
  ReauthCubit(this._auth, {super.now});

  final AuthRepository _auth;

  Future<bool> confirm(String password) => submit(() => _auth.reauthenticate(password));
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
