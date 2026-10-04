import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../app/errors/app_failure.dart';
import '../../../data/repositories/auth_repository.dart';

class LoginState extends Equatable {
  const LoginState({this.submitting = false, this.failure});

  final bool submitting;
  final AppFailure? failure;

  @override
  List<Object?> get props => [submitting, failure];
}

/// Login form logic. On success the SDK session changes and [SessionCubit]
/// loads the profile and the router leaves the login screen: this Cubit never
/// navigates nor touches the session itself.
class LoginCubit extends Cubit<LoginState> {
  LoginCubit(this._auth) : super(const LoginState());

  final AuthRepository _auth;

  Future<void> submit({required String email, required String password}) async {
    if (state.submitting) return;
    if (email.trim().isEmpty || password.isEmpty) {
      emit(
        const LoginState(
          failure: AppFailure(kind: FailureKind.validation, message: 'Ingresa tu correo y tu contraseña'),
        ),
      );
      return;
    }
    emit(const LoginState(submitting: true));
    try {
      await _auth.login(email: email.trim(), password: password);
      emit(const LoginState());
    } on AppFailure catch (failure) {
      emit(LoginState(failure: failure));
    }
  }
}
