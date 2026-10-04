import '../../../data/repositories/auth_repository.dart';
import '../../../shared/state/submit_cubit.dart';

/// Registration (HU-01). The form validates locally; the backend answers the
/// same 201 whether or not the e-mail existed, so success always leads to
/// «Revisa tu correo».
class RegisterCubit extends SubmitCubit {
  RegisterCubit(this._auth, {super.now});

  final AuthRepository _auth;

  Future<bool> register({
    required String firstName,
    required String lastName,
    required String username,
    required String email,
    required String password,
    String? captchaToken,
  }) => submit(
    () => _auth.register(
      firstName: firstName.trim(),
      lastName: lastName.trim(),
      username: username.trim(),
      email: email.trim().toLowerCase(),
      password: password,
      captchaToken: captchaToken,
    ),
  );
}
