import 'package:countit_app/app/errors/app_failure.dart';
import 'package:countit_app/app/router/app_router.dart';
import 'package:countit_app/app/session/session_cubit.dart';
import 'package:countit_app/app/session/session_state.dart';
import 'package:countit_app/data/repositories/auth_repository.dart';
import 'package:countit_app/presentation/auth/view/check_email_page.dart';
import 'package:countit_app/presentation/auth/view/email_confirmed_page.dart';
import 'package:countit_app/presentation/auth/view/forgot_password_page.dart';
import 'package:countit_app/presentation/auth/view/login_page.dart';
import 'package:countit_app/presentation/auth/view/register_page.dart';
import 'package:countit_app/presentation/auth/view/reset_password_page.dart';
import 'package:countit_app/presentation/auth/view/welcome_page.dart';
import 'package:countit_app/shared/platform/mail_launcher.dart';
import 'package:countit_app/shared/utils/dates.dart';
import 'package:countit_app/shared/utils/validators.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';

import '../../helpers/mocks.dart';
import '../../helpers/pump_app.dart';

class _MockMail extends Mock implements MailLauncher {}

/// Router with the auth screens and a marker for every destination, so a test
/// can assert where a screen navigates.
GoRouter _router(String initial, {Widget? page}) => GoRouter(
  initialLocation: initial,
  routes: [
    GoRoute(path: AppRoutes.welcome, builder: (_, _) => const WelcomePage()),
    GoRoute(path: AppRoutes.login, builder: (_, _) => page ?? const LoginPage()),
    GoRoute(path: AppRoutes.register, builder: (_, _) => const RegisterPage()),
    GoRoute(
      path: AppRoutes.checkEmail,
      builder: (_, state) => Scaffold(body: Text('check-email:${state.extra}')),
    ),
    GoRoute(
      path: AppRoutes.forgotPassword,
      builder: (_, _) => const Scaffold(body: Text('forgot')),
    ),
  ],
);

Finder _field(String label) => find.ancestor(of: find.text(label), matching: find.byType(Column)).first;

Future<void> _enter(WidgetTester tester, String label, String text) async {
  await tester.enterText(find.descendant(of: _field(label), matching: find.byType(EditableText)), text);
}

void main() {
  late MockAuthRepository auth;

  setUpAll(() async {
    await Dates.init();
    registerFallbackValue(Uri());
  });

  setUp(() {
    auth = MockAuthRepository();
    when(() => auth.sessionChanges).thenAnswer((_) => const Stream.empty());
  });

  void stubLogin(Object? error) => when(
    () => auth.login(
      email: any(named: 'email'),
      password: any(named: 'password'),
      captchaToken: any(named: 'captchaToken'),
    ),
  ).thenAnswer((_) async => error == null ? null : throw error);

  group('Welcome (COU-80)', () {
    testWidgets('both actions open their screen', (tester) async {
      await tester.pumpApp(const SizedBox(), auth: auth, router: _router(AppRoutes.welcome));
      await tester.pumpAndSettle();
      expect(find.text('Cuéntalo\ntodo.'), findsOneWidget);

      await tester.tap(find.text('Ya tengo cuenta'));
      await tester.pumpAndSettle();
      expect(find.text('Hola de nuevo'), findsOneWidget);

      await tester.tap(find.byTooltip('Volver'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Crear mi cuenta'));
      await tester.pumpAndSettle();
      expect(find.text('Crear cuenta'), findsWidgets);
    });
  });

  group('Login (COU-160)', () {
    testWidgets('validates locally before calling the backend', (tester) async {
      await tester.pumpApp(const LoginPage(), auth: auth);
      await tester.tap(find.text('Iniciar sesión'));
      await tester.pump();
      expect(find.text(Validators.requiredMessage), findsNWidgets(2));
      verifyNever(
        () => auth.login(
          email: any(named: 'email'),
          password: any(named: 'password'),
          captchaToken: any(named: 'captchaToken'),
        ),
      );
    });

    testWidgets('wrong credentials: generic message and the password is cleared', (tester) async {
      stubLogin(
        const AppFailure(
          kind: FailureKind.invalidCredentials,
          message: 'Correo o contraseña incorrectos',
          key: 'invalid_credentials',
          status: 401,
        ),
      );
      await tester.pumpApp(const LoginPage(), auth: auth);
      await _enter(tester, 'Correo electrónico', 'maria@correo.ec');
      await _enter(tester, 'Contraseña', 'Quito2026');
      await tester.tap(find.text('Iniciar sesión'));
      await tester.pumpAndSettle();

      expect(find.text('Correo o contraseña incorrectos'), findsOneWidget);
      expect(find.text('maria@correo.ec'), findsOneWidget);
      expect(find.text('Quito2026'), findsNothing);
    });

    testWidgets('e-mail not confirmed offers the «revisa tu correo» shortcut', (tester) async {
      stubLogin(
        const AppFailure(
          kind: FailureKind.forbidden,
          message: 'Confirma tu correo para iniciar sesión',
          key: 'email_not_confirmed',
          status: 403,
        ),
      );
      await tester.pumpApp(const SizedBox(), auth: auth, router: _router(AppRoutes.login));
      await tester.pumpAndSettle();
      await _enter(tester, 'Correo electrónico', 'maria@correo.ec');
      await _enter(tester, 'Contraseña', 'Quito2026');
      await tester.tap(find.text('Iniciar sesión'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Ir a revisar mi correo'));
      await tester.pumpAndSettle();
      expect(find.text('check-email:maria@correo.ec'), findsOneWidget);
    });

    testWidgets('429 disables the button with a countdown (COU-63)', (tester) async {
      stubLogin(
        const AppFailure(
          kind: FailureKind.rateLimited,
          message: 'Demasiados intentos',
          status: 429,
          retryAfter: Duration(seconds: 65),
        ),
      );
      await tester.pumpApp(const LoginPage(), auth: auth);
      await _enter(tester, 'Correo electrónico', 'maria@correo.ec');
      await _enter(tester, 'Contraseña', 'Quito2026');
      await tester.tap(find.text('Iniciar sesión'));
      await tester.pump();
      await tester.pump();

      expect(find.textContaining('Espera 1:0'), findsOneWidget);
      await tester.pump(const Duration(seconds: 66));
      expect(find.text('Iniciar sesión'), findsOneWidget);
    });

    testWidgets('success keeps the spinner while the session takes over', (tester) async {
      stubLogin(null);
      await tester.pumpApp(const LoginPage(), auth: auth);
      await _enter(tester, 'Correo electrónico', 'maria@correo.ec');
      await _enter(tester, 'Contraseña', 'Quito2026');
      await tester.tap(find.text('Iniciar sesión'));
      await tester.pump();
      await tester.pump();
      expect(find.bySemanticsLabel('Iniciar sesión, cargando'), findsOneWidget);
    });

    testWidgets('an involuntary sign-out explains itself', (tester) async {
      final session = SessionCubit(auth: auth, profiles: MockProfileRepository())
        ..emit(const SessionState.unauthenticated(message: 'Tu sesión ya no es válida. Inicia sesión nuevamente'));
      addTearDown(session.close);
      await tester.pumpApp(const LoginPage(), auth: auth, session: session);
      expect(find.text('Tu sesión ya no es válida. Inicia sesión nuevamente'), findsOneWidget);
    });
  });

  group('Register (COU-158)', () {
    void stubRegister(Object? error) => when(
      () => auth.register(
        email: any(named: 'email'),
        password: any(named: 'password'),
        username: any(named: 'username'),
        firstName: any(named: 'firstName'),
        lastName: any(named: 'lastName'),
        captchaToken: any(named: 'captchaToken'),
      ),
    ).thenAnswer((_) async => error == null ? null : throw error);

    Future<void> fill(WidgetTester tester, {String username = 'mariaq'}) async {
      await _enter(tester, 'Nombre', 'María');
      await _enter(tester, 'Apellido', 'Quishpe');
      await _enter(tester, 'Nombre de usuario', username);
      await _enter(tester, 'Correo electrónico', 'Maria@Correo.ec');
      await _enter(tester, 'Contraseña', 'Quito2026');
      await _enter(tester, 'Repite la contraseña', 'Quito2026');
    }

    Future<void> tapCreate(WidgetTester tester) async {
      final button = find.widgetWithText(FilledButton, 'Crear cuenta');
      await tester.scrollUntilVisible(button, 300, scrollable: find.byType(Scrollable).first);
      await tester.tap(button);
    }

    Future<void> submit(WidgetTester tester) async {
      await tapCreate(tester);
      await tester.pumpAndSettle();
    }

    testWidgets('inline validation and the live password checklist', (tester) async {
      await tester.pumpApp(const RegisterPage(), auth: auth);
      await fill(tester, username: 'del_ana');
      await _enter(tester, 'Repite la contraseña', 'Quito2027');
      await tester.pump();
      expect(find.text('Ese nombre de usuario no está disponible'), findsOneWidget);
      expect(find.text('Las contraseñas no coinciden'), findsOneWidget);
      expect(find.bySemanticsLabel('Al menos un número: cumplido'), findsOneWidget);
    });

    testWidgets('success goes to «Revisa tu correo» with the normalised e-mail', (tester) async {
      stubRegister(null);
      final router = GoRouter(
        initialLocation: AppRoutes.register,
        routes: [
          GoRoute(path: AppRoutes.register, builder: (_, _) => const RegisterPage()),
          GoRoute(
            path: AppRoutes.checkEmail,
            builder: (_, s) => Scaffold(body: Text('check-email:${s.extra}')),
          ),
        ],
      );
      await tester.pumpApp(const SizedBox(), auth: auth, router: router);
      await tester.pumpAndSettle();
      await fill(tester);
      await submit(tester);
      expect(find.text('check-email:maria@correo.ec'), findsOneWidget);
      verify(
        () => auth.register(
          email: 'maria@correo.ec',
          password: 'Quito2026',
          username: 'mariaq',
          firstName: 'María',
          lastName: 'Quishpe',
          captchaToken: any(named: 'captchaToken'),
        ),
      ).called(1);
    });

    testWidgets('server validationErrors appear under their field', (tester) async {
      stubRegister(
        const AppFailure(
          kind: FailureKind.validation,
          message: 'Errores de validación',
          key: 'validation_error',
          status: 400,
          fieldErrors: {'username': 'El nombre de usuario solo puede contener letras'},
        ),
      );
      await tester.pumpApp(const RegisterPage(), auth: auth);
      await fill(tester);
      await submit(tester);
      expect(find.text('El nombre de usuario solo puede contener letras'), findsOneWidget);
      expect(find.text('Errores de validación'), findsNothing, reason: 'the field error replaces the banner');
    });

    testWidgets('username taken is shown on the username field', (tester) async {
      stubRegister(
        const AppFailure(
          kind: FailureKind.conflict,
          message: 'Ese nombre de usuario ya está en uso',
          key: 'username_taken',
          status: 409,
        ),
      );
      await tester.pumpApp(const RegisterPage(), auth: auth);
      await fill(tester);
      await submit(tester);
      expect(find.text('Ese nombre de usuario ya está en uso'), findsOneWidget);
    });

    testWidgets('429 shows the countdown', (tester) async {
      stubRegister(
        const AppFailure(
          kind: FailureKind.rateLimited,
          message: 'Demasiados intentos',
          status: 429,
          retryAfter: Duration(seconds: 30),
        ),
      );
      await tester.pumpApp(const RegisterPage(), auth: auth);
      await fill(tester);
      await tapCreate(tester);
      await tester.pump();
      await tester.pump();
      expect(find.text('Espera 0:30'), findsOneWidget);
      expect(find.text('Demasiados intentos'), findsOneWidget);
    });
  });

  group('Password recovery (COU-85, COU-133, COU-136, COU-141)', () {
    testWidgets('the request answers generically', (tester) async {
      when(
        () => auth.requestPasswordReset(
          email: any(named: 'email'),
          captchaToken: any(named: 'captchaToken'),
        ),
      ).thenAnswer((_) async {});
      await tester.pumpApp(const ForgotPasswordPage(), auth: auth);
      await _enter(tester, 'Correo electrónico', 'Maria@Correo.ec');
      await tester.tap(find.text('Enviar enlace'));
      await tester.pumpAndSettle();
      expect(find.text(ForgotPasswordPage.sentMessage), findsOneWidget);
      expect(find.text('Reenviar enlace'), findsOneWidget);
      verify(() => auth.requestPasswordReset(email: 'maria@correo.ec', captchaToken: null)).called(1);
    });

    testWidgets('an expired link explains why the user is here', (tester) async {
      await tester.pumpApp(const ForgotPasswordPage(linkExpired: true), auth: auth);
      expect(find.text('El enlace venció o ya fue usado. Solicita uno nuevo'), findsOneWidget);
    });

    testWidgets('new password: saves, then the session enters the app', (tester) async {
      final profiles = MockProfileRepository();
      when(() => auth.setNewPassword('Quito2026')).thenAnswer((_) async {});
      when(profiles.fetchMyProfile).thenThrow(const AppFailure(kind: FailureKind.network, message: 'x'));
      final session = SessionCubit(auth: auth, profiles: profiles)..emit(const SessionState.passwordRecovery());
      addTearDown(session.close);
      await tester.pumpApp(const ResetPasswordPage(), auth: auth, session: session);

      await _enter(tester, 'Nueva contraseña', 'Quito2026');
      await _enter(tester, 'Repite la contraseña', 'Quito2026');
      await tester.tap(find.text('Guardar y entrar'));
      await tester.pump();
      await tester.pump();
      verify(() => auth.setNewPassword('Quito2026')).called(1);
      verify(profiles.fetchMyProfile).called(1);
    });

    testWidgets('new password: the same as before is rejected with its message', (tester) async {
      when(() => auth.setNewPassword(any())).thenThrow(
        const AppFailure(
          kind: FailureKind.validation,
          message: 'La nueva contraseña debe ser diferente a la actual',
          key: 'same_password',
          status: 422,
        ),
      );
      await tester.pumpApp(const ResetPasswordPage(), auth: auth);
      await _enter(tester, 'Nueva contraseña', 'Quito2026');
      await _enter(tester, 'Repite la contraseña', 'Quito2026');
      await tester.tap(find.text('Guardar y entrar'));
      await tester.pumpAndSettle();
      expect(find.text('La nueva contraseña debe ser diferente a la actual'), findsOneWidget);
    });
  });

  group('E-mail screens (COU-110, COU-114)', () {
    testWidgets('«Revisa tu correo» masks the address and opens the mail app', (tester) async {
      final mail = _MockMail();
      when(mail.openInbox).thenAnswer((_) async => false);
      await tester.pumpApp(
        CheckEmailPage(email: 'maria@correo.ec', mail: mail),
        auth: auth,
      );
      expect(find.textContaining('m•••@correo.ec'), findsOneWidget);
      expect(find.textContaining('maria@correo.ec'), findsNothing);

      await tester.tap(find.text('Abrir app de correo'));
      await tester.pump();
      verify(mail.openInbox).called(1);
      expect(find.text('No encontramos una app de correo en este teléfono'), findsOneWidget);
    });

    testWidgets('confirmed and expired links', (tester) async {
      await tester.pumpApp(const EmailConfirmedPage(), auth: auth);
      expect(find.text('¡Correo confirmado!'), findsOneWidget);
      await tester.pumpApp(const EmailConfirmedPage(expired: true), auth: auth);
      expect(find.text('El enlace venció o ya fue usado'), findsOneWidget);
    });
  });

  test('AuthRepository exposes the recovery change', () {
    expect(SessionChange.values, contains(SessionChange.passwordRecovery));
  });
}
