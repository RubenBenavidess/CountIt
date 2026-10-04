import 'package:bloc_test/bloc_test.dart';
import 'package:countit_app/app/errors/app_failure.dart';
import 'package:countit_app/presentation/auth/cubit/login_cubit.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../../helpers/mocks.dart';

void main() {
  late MockAuthRepository auth;

  setUp(() => auth = MockAuthRepository());

  blocTest<LoginCubit, LoginState>(
    'empty fields fail locally without calling the backend',
    build: () => LoginCubit(auth),
    act: (c) => c.submit(email: '  ', password: ''),
    expect: () => [isA<LoginState>().having((s) => s.failure?.kind, 'kind', FailureKind.validation)],
    verify: (_) => verifyNever(
      () => auth.login(
        email: any(named: 'email'),
        password: any(named: 'password'),
      ),
    ),
  );

  blocTest<LoginCubit, LoginState>(
    'success: submitting, then idle (the session listener loads the profile)',
    setUp: () => when(() => auth.login(email: 'ana@test.com', password: 'Clave2026x')).thenAnswer((_) async {}),
    build: () => LoginCubit(auth),
    act: (c) => c.submit(email: ' ana@test.com ', password: 'Clave2026x'),
    expect: () => [const LoginState(submitting: true), const LoginState()],
  );

  const wrong = AppFailure(
    kind: FailureKind.invalidCredentials,
    message: 'Correo o contraseña incorrectos',
    key: 'invalid_credentials',
    status: 401,
  );

  blocTest<LoginCubit, LoginState>(
    'wrong credentials show the backend message',
    setUp: () => when(
      () => auth.login(
        email: any(named: 'email'),
        password: any(named: 'password'),
      ),
    ).thenThrow(wrong),
    build: () => LoginCubit(auth),
    act: (c) => c.submit(email: 'ana@test.com', password: 'x'),
    expect: () => [const LoginState(submitting: true), const LoginState(failure: wrong)],
  );
}
