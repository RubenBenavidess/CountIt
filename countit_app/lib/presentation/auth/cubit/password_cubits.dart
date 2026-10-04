import '../../../data/repositories/auth_repository.dart';
import '../../../shared/state/submit_cubit.dart';

/// «Recupera tu contraseña» (HU-03, step 1). The answer is generic: success
/// never confirms that the e-mail exists.
class ForgotPasswordCubit extends SubmitCubit {
  ForgotPasswordCubit(this._auth, {super.now});

  final AuthRepository _auth;

  Future<bool> requestLink({required String email, String? captchaToken}) =>
      submit(() => _auth.requestPasswordReset(email: email.trim().toLowerCase(), captchaToken: captchaToken));
}

/// New password with the recovery session (HU-03, step 2).
class ResetPasswordCubit extends SubmitCubit {
  ResetPasswordCubit(this._auth, {super.now});

  final AuthRepository _auth;

  Future<bool> save(String password) => submit(() => _auth.setNewPassword(password));
}
