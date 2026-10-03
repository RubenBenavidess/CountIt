import '../../../data/repositories/auth_repository.dart';
import '../../../shared/state/submit_cubit.dart';

/// Login form logic. On success the SDK session changes and [SessionCubit]
/// loads the profile and the router leaves the login screen: this Cubit never
/// navigates nor touches the session itself.
class LoginCubit extends SubmitCubit {
  LoginCubit(this._auth, {super.now});

  final AuthRepository _auth;

  Future<void> login({required String email, required String password, String? captchaToken}) async {
    if (email.trim().isEmpty || password.isEmpty) {
      fail('Ingresa tu correo y tu contraseña');
      return;
    }
    await submit(() => _auth.login(email: email.trim(), password: password, captchaToken: captchaToken));
  }
}
