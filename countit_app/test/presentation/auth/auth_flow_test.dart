import 'dart:async';

import 'package:countit_app/app/errors/app_failure.dart';
import 'package:countit_app/app/router/app_router.dart';
import 'package:countit_app/app/session/session_cubit.dart';
import 'package:countit_app/app/session/session_state.dart';
import 'package:countit_app/data/dtos/profile.dart';
import 'package:countit_app/data/dtos/wallet.dart';
import 'package:countit_app/data/repositories/auth_repository.dart';
import 'package:countit_app/data/repositories/profile_repository.dart';
import 'package:countit_app/data/repositories/wallet_repository.dart';
import 'package:countit_app/shared/utils/dates.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/pump_app.dart';

/// COU-164: register → confirm → login → logout through the real router and
/// screens, over an in-memory Auth that behaves like the Edge Functions
/// (unconfirmed e-mail, wrong password, taken username) and the SDK session.

const _email = 'maria@correo.ec';
const _password = 'Quito2026x';

class _Account {
  _Account(this.profile, this.password);

  final Profile profile;
  final String password;
  var confirmed = false;
}

/// In-memory backend: accounts by e-mail and the device's SDK session.
class _Backend implements AuthRepository, ProfileRepository {
  final accounts = <String, _Account>{};
  final _changes = StreamController<SessionChange>.broadcast();
  _Account? _session;
  var signOutCalls = 0;

  void confirm(String email) => accounts[email]!.confirmed = true;

  Future<void> dispose() => _changes.close();

  @override
  bool get hasSession => _session != null;

  @override
  Stream<SessionChange> get sessionChanges => _changes.stream;

  @override
  Future<void> register({
    required String email,
    required String password,
    required String username,
    required String firstName,
    required String lastName,
    String? captchaToken,
  }) async {
    if (accounts.values.any((a) => a.profile.username == username)) {
      throw const AppFailure(
        kind: FailureKind.conflict,
        message: 'Ese nombre de usuario ya está en uso',
        key: 'username_taken',
        status: 409,
      );
    }
    // Like the backend: a taken e-mail answers the same as a new one.
    accounts.putIfAbsent(
      email,
      () => _Account(
        Profile(
          userId: 'u-${accounts.length + 1}',
          username: username,
          email: email,
          firstName: firstName,
          lastName: lastName,
          role: UserRole.user,
          timezone: 'America/Guayaquil',
        ),
        password,
      ),
    );
  }

  @override
  Future<void> login({required String email, required String password, String? captchaToken}) async {
    final account = accounts[email];
    if (account == null || account.password != password) {
      throw const AppFailure(
        kind: FailureKind.invalidCredentials,
        message: 'Correo o contraseña incorrectos',
        key: 'invalid_credentials',
        status: 401,
      );
    }
    if (!account.confirmed) {
      throw const AppFailure(
        kind: FailureKind.forbidden,
        message: 'Confirma tu correo para iniciar sesión',
        key: 'email_not_confirmed',
        status: 403,
      );
    }
    _session = account;
    _changes.add(SessionChange.signedIn);
  }

  @override
  Future<void> signOut() async {
    signOutCalls++;
    _session = null;
    _changes.add(SessionChange.signedOut);
  }

  @override
  Future<Profile> fetchMyProfile() async {
    final account = _session;
    if (account == null) {
      throw const AppFailure(
        kind: FailureKind.unauthenticated,
        message: 'Tu sesión terminó. Inicia sesión de nuevo.',
        key: 'not_authenticated',
        status: 401,
      );
    }
    return account.profile;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError('${invocation.memberName}');
}

class _NoWallets implements WalletRepository {
  @override
  Future<List<Wallet>> list() async => const [];

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError('${invocation.memberName}');
}

/// The editable text inside the field labelled [label] (labels sit above the input).
Finder _field(String label) => find.descendant(
  of: find.ancestor(of: find.text(label), matching: find.byType(Column)).first,
  matching: find.byType(EditableText),
);

String _textOf(WidgetTester tester, Finder field) => tester.widget<EditableText>(field).controller.text;

void main() {
  setUpAll(Dates.init);

  late _Backend backend;
  late SessionCubit session;

  Future<void> start(WidgetTester tester) async {
    tester.view.physicalSize = const Size(800, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    backend = _Backend();
    addTearDown(backend.dispose);
    session = SessionCubit(auth: backend, profiles: backend);
    addTearDown(session.close);
    await session.restore();
    final router = buildRouter(session: session, config: testConfig);
    addTearDown(router.dispose);

    await tester.pumpApp(
      const SizedBox(),
      auth: backend,
      profiles: backend,
      wallets: _NoWallets(),
      session: session,
      router: router,
    );
    await tester.pumpAndSettle();
  }

  Future<void> fillRegister(WidgetTester tester, {String username = 'mariaq'}) async {
    await tester.enterText(_field('Nombre'), 'María');
    await tester.enterText(_field('Apellido'), 'Quishpe');
    await tester.enterText(_field('Nombre de usuario'), username);
    await tester.enterText(_field('Correo electrónico'), '  Maria@Correo.ec ');
    await tester.enterText(_field('Contraseña'), _password);
    await tester.enterText(_field('Repite la contraseña'), _password);
    await tester.tap(find.widgetWithText(FilledButton, 'Crear cuenta'));
    await tester.pumpAndSettle();
  }

  Future<void> login(WidgetTester tester, String password) async {
    await tester.enterText(_field('Correo electrónico'), _email);
    await tester.enterText(_field('Contraseña'), password);
    await tester.tap(find.widgetWithText(FilledButton, 'Iniciar sesión'));
    await tester.pumpAndSettle();
  }

  testWidgets('register, confirm the e-mail, sign in and sign out', (tester) async {
    await start(tester);

    // No session: the welcome screen.
    expect(session.state.status, SessionStatus.unauthenticated);
    expect(find.text('Crear mi cuenta'), findsOneWidget);

    // Register: the e-mail is normalized and the result never confirms it was new.
    await tester.tap(find.text('Crear mi cuenta'));
    await tester.pumpAndSettle();
    await fillRegister(tester);
    expect(backend.accounts.keys, [_email]);
    expect(backend.hasSession, isFalse, reason: 'registering does not sign in');
    expect(find.text('Revisa tu correo'), findsOneWidget);
    expect(find.textContaining('m•••@correo.ec', findRichText: true), findsOneWidget);

    // Signing in before confirming explains it and offers to check the mail.
    await tester.tap(find.text('Ir a iniciar sesión'));
    await tester.pumpAndSettle();
    await login(tester, _password);
    expect(find.text('Confirma tu correo para iniciar sesión'), findsOneWidget);
    expect(find.text('Ir a revisar mi correo'), findsOneWidget);
    expect(session.state.status, SessionStatus.unauthenticated);

    // A wrong password clears only the password.
    backend.confirm(_email);
    await login(tester, 'Otra2026x');
    expect(find.text('Correo o contraseña incorrectos'), findsOneWidget);
    expect(_textOf(tester, _field('Correo electrónico')), _email);
    expect(_textOf(tester, _field('Contraseña')), isEmpty);

    // Confirmed: the session loads the profile and the router opens the home.
    await login(tester, _password);
    expect(session.state.status, SessionStatus.authenticated);
    expect(session.state.profile?.username, 'mariaq');
    expect(find.text('Inicio'), findsOneWidget);
    expect(find.text('Iniciar sesión'), findsNothing);

    // Profile → sign out (confirmed) → welcome, with no session left on the device.
    await tester.tap(find.text('Perfil'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Cerrar sesión'), 200);
    await tester.tap(find.text('Cerrar sesión'));
    await tester.pumpAndSettle();
    expect(find.text('¿Cerrar sesión?'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Cerrar sesión'));
    await tester.pumpAndSettle();

    expect(backend.signOutCalls, 1);
    expect(backend.hasSession, isFalse);
    expect(session.state.status, SessionStatus.unauthenticated);
    expect(session.state.profile, isNull);
    expect(find.text('Crear mi cuenta'), findsOneWidget);
    expect(find.text('Perfil'), findsNothing);
  });

  testWidgets('a taken username keeps the form and shows the error on the field', (tester) async {
    await start(tester);
    backend.accounts['otro@correo.ec'] = _Account(
      const Profile(
        userId: 'u-0',
        username: 'mariaq',
        email: 'otro@correo.ec',
        firstName: 'Otra',
        role: UserRole.user,
        timezone: 'America/Guayaquil',
      ),
      _password,
    );

    await tester.tap(find.text('Crear mi cuenta'));
    await tester.pumpAndSettle();
    await fillRegister(tester);

    expect(find.text('Ese nombre de usuario ya está en uso'), findsOneWidget);
    expect(find.text('Revisa tu correo'), findsNothing);
    expect(backend.accounts, hasLength(1));

    // Another username goes through.
    await fillRegister(tester, username: 'maria_q');
    expect(find.text('Revisa tu correo'), findsOneWidget);
    expect(backend.accounts[_email]?.profile.username, 'maria_q');
  });

  testWidgets('a session restored at start-up opens the home; signing out returns to welcome', (tester) async {
    tester.view.physicalSize = const Size(800, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    backend = _Backend();
    addTearDown(backend.dispose);
    await backend.register(email: _email, password: _password, username: 'mariaq', firstName: 'María', lastName: 'Q');
    backend.confirm(_email);
    await backend.login(email: _email, password: _password);

    session = SessionCubit(auth: backend, profiles: backend);
    addTearDown(session.close);
    await session.restore();
    final router = buildRouter(session: session, config: testConfig);
    addTearDown(router.dispose);
    await tester.pumpApp(
      const SizedBox(),
      auth: backend,
      profiles: backend,
      wallets: _NoWallets(),
      session: session,
      router: router,
    );
    await tester.pumpAndSettle();

    expect(session.state.status, SessionStatus.authenticated);
    expect(find.text('Inicio'), findsOneWidget);

    await session.signOut();
    await tester.pumpAndSettle();
    expect(backend.hasSession, isFalse);
    expect(find.text('Crear mi cuenta'), findsOneWidget);
  });
}
