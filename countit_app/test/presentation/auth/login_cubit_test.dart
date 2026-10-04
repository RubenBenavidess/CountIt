import 'package:bloc_test/bloc_test.dart';
import 'package:countit_app/app/errors/app_failure.dart';
import 'package:countit_app/presentation/auth/cubit/login_cubit.dart';
import 'package:countit_app/shared/state/submit_cubit.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../../helpers/mocks.dart';

void main() {
  late MockAuthRepository auth;
  final now = DateTime(2026, 10, 3, 12);

  setUp(() => auth = MockAuthRepository());

  void stubLogin(Future<void> Function() answer) => when(
    () => auth.login(
      email: any(named: 'email'),
      password: any(named: 'password'),
      captchaToken: any(named: 'captchaToken'),
    ),
  ).thenAnswer((_) => answer());

  blocTest<LoginCubit, SubmitState>(
    'empty fields fail locally without calling the backend',
    build: () => LoginCubit(auth),
    act: (c) => c.login(email: '  ', password: ''),
    expect: () => [isA<SubmitState>().having((s) => s.failure?.kind, 'kind', FailureKind.validation)],
    verify: (_) => verifyNever(
      () => auth.login(
        email: any(named: 'email'),
        password: any(named: 'password'),
        captchaToken: any(named: 'captchaToken'),
      ),
    ),
  );

  blocTest<LoginCubit, SubmitState>(
    'success: trims the e-mail and passes the captcha token',
    setUp: () => stubLogin(() async {}),
    build: () => LoginCubit(auth),
    act: (c) => c.login(email: ' ana@test.com ', password: 'Clave2026x', captchaToken: 'tok'),
    expect: () => [const SubmitState(status: SubmitStatus.submitting), const SubmitState(status: SubmitStatus.success)],
    verify: (_) =>
        verify(() => auth.login(email: 'ana@test.com', password: 'Clave2026x', captchaToken: 'tok')).called(1),
  );

  const wrong = AppFailure(
    kind: FailureKind.invalidCredentials,
    message: 'Correo o contraseña incorrectos',
    key: 'invalid_credentials',
    status: 401,
  );

  blocTest<LoginCubit, SubmitState>(
    'wrong credentials show the backend message',
    setUp: () => stubLogin(() async => throw wrong),
    build: () => LoginCubit(auth),
    act: (c) => c.login(email: 'ana@test.com', password: 'x'),
    expect: () => [
      const SubmitState(status: SubmitStatus.submitting),
      const SubmitState(status: SubmitStatus.failure, failure: wrong),
    ],
  );

  blocTest<LoginCubit, SubmitState>(
    '429 blocks the form until Retry-After elapses (COU-63)',
    setUp: () => stubLogin(
      () async => throw const AppFailure(
        kind: FailureKind.rateLimited,
        message: 'Demasiados intentos',
        status: 429,
        retryAfter: Duration(seconds: 90),
      ),
    ),
    build: () => LoginCubit(auth, now: () => now),
    act: (c) => c.login(email: 'ana@test.com', password: 'x'),
    skip: 1,
    expect: () => [
      isA<SubmitState>().having((s) => s.blockedUntil, 'blockedUntil', now.add(const Duration(seconds: 90))),
    ],
  );

  blocTest<LoginCubit, SubmitState>(
    'a second tap while sending is ignored',
    setUp: () => stubLogin(() => Future<void>.delayed(const Duration(milliseconds: 10))),
    build: () => LoginCubit(auth),
    act: (c) async {
      final first = c.login(email: 'ana@test.com', password: 'x');
      await c.login(email: 'ana@test.com', password: 'x');
      await first;
    },
    verify: (_) => verify(
      () => auth.login(
        email: any(named: 'email'),
        password: any(named: 'password'),
        captchaToken: any(named: 'captchaToken'),
      ),
    ).called(1),
  );
}
