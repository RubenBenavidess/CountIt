import 'package:bloc_test/bloc_test.dart';
import 'package:countit_app/app/errors/app_failure.dart';
import 'package:countit_app/app/session/session_cubit.dart';
import 'package:countit_app/app/session/session_state.dart';
import 'package:countit_app/data/dtos/profile.dart';
import 'package:countit_app/presentation/account/cubit/account_cubits.dart';
import 'package:countit_app/presentation/account/view/delete_account_page.dart';
import 'package:countit_app/presentation/account/view/reauth_sheet.dart';
import 'package:countit_app/shared/state/submit_cubit.dart';
import 'package:countit_app/shared/utils/dates.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../../helpers/mocks.dart';
import '../../helpers/pump_app.dart';

const _profile = Profile(
  userId: 'u1',
  username: 'mariaq',
  email: 'maria@correo.ec',
  role: UserRole.user,
  timezone: 'America/Guayaquil',
);

const _wrong = AppFailure(
  kind: FailureKind.invalidCredentials,
  message: 'Contraseña incorrecta',
  key: 'invalid_password',
  status: 401,
);

void main() {
  late MockAuthRepository auth;
  late MockProfileRepository profiles;
  late SessionCubit session;

  setUpAll(Dates.init);

  setUp(() {
    ReauthCubit.resetBlock();
    auth = MockAuthRepository();
    profiles = MockProfileRepository();
    when(() => auth.sessionChanges).thenAnswer((_) => const Stream.empty());
    when(() => auth.signOut()).thenAnswer((_) async {});
    session = SessionCubit(auth: auth, profiles: profiles)..emit(const SessionState.authenticated(_profile));
  });

  tearDown(() => session.close());

  group('ChangePasswordCubit (COU-142)', () {
    blocTest<ChangePasswordCubit, SubmitState>(
      'with a fresh session the user stays signed in',
      setUp: () =>
          when(() => auth.changePassword(currentPassword: 'Quito2026', newPassword: 'Cuenca2027'))
              .thenAnswer((_) async => true),
      build: () => ChangePasswordCubit(auth: auth, session: session),
      act: (c) => c.change(currentPassword: 'Quito2026', newPassword: 'Cuenca2027'),
      expect: () => [
        const SubmitState(status: SubmitStatus.submitting),
        const SubmitState(status: SubmitStatus.success),
      ],
      verify: (_) {
        expect(session.state.status, SessionStatus.authenticated);
        verifyNever(() => auth.signOut());
      },
    );

    blocTest<ChangePasswordCubit, SubmitState>(
      'without a session in the answer it asks to sign in again',
      setUp: () => when(
        () => auth.changePassword(
          currentPassword: any(named: 'currentPassword'),
          newPassword: any(named: 'newPassword'),
        ),
      ).thenAnswer((_) async => false),
      build: () => ChangePasswordCubit(auth: auth, session: session),
      act: (c) => c.change(currentPassword: 'Quito2026', newPassword: 'Cuenca2027'),
      verify: (_) =>
          expect(session.state, const SessionState.unauthenticated(message: ChangePasswordCubit.signInAgain)),
    );

    blocTest<ChangePasswordCubit, SubmitState>(
      'a wrong current password keeps the session',
      setUp: () => when(
        () => auth.changePassword(
          currentPassword: any(named: 'currentPassword'),
          newPassword: any(named: 'newPassword'),
        ),
      ).thenThrow(_wrong),
      build: () => ChangePasswordCubit(auth: auth, session: session),
      act: (c) => c.change(currentPassword: 'x', newPassword: 'Cuenca2027'),
      skip: 1,
      expect: () => [const SubmitState(status: SubmitStatus.failure, failure: _wrong)],
      verify: (_) => expect(session.state.status, SessionStatus.authenticated),
    );
  });

  group('DeleteAccountCubit (COU-150)', () {
    blocTest<DeleteAccountCubit, SubmitState>(
      'success clears the session with a farewell and forgets the tokens',
      setUp: () => when(() => auth.deleteAccount('Quito2026')).thenAnswer((_) async {}),
      build: () => DeleteAccountCubit(auth: auth, session: session),
      act: (c) => c.delete('Quito2026'),
      verify: (_) {
        expect(session.state, const SessionState.unauthenticated(message: DeleteAccountCubit.farewell));
        verify(() => auth.signOut()).called(1);
      },
    );

    blocTest<DeleteAccountCubit, SubmitState>(
      'a wrong password deletes nothing',
      setUp: () => when(() => auth.deleteAccount(any())).thenThrow(_wrong),
      build: () => DeleteAccountCubit(auth: auth, session: session),
      act: (c) => c.delete('x'),
      verify: (_) => expect(session.state.status, SessionStatus.authenticated),
    );
  });

  group('Delete account screen (COU-149)', () {
    testWidgets('the button only works with the exact word', (tester) async {
      when(() => auth.deleteAccount(any())).thenAnswer((_) async {});
      await tester.pumpApp(const DeleteAccountPage(), auth: auth, profiles: profiles, session: session);

      Finder field(String label) => find.descendant(
        of: find.ancestor(of: find.text(label), matching: find.byType(Column)).first,
        matching: find.byType(EditableText),
      );
      final button = find.widgetWithText(FilledButton, 'Eliminar mi cuenta');

      await tester.enterText(field('Contraseña'), 'Quito2026');
      await tester.enterText(field('Escribe ELIMINAR para confirmar'), 'eliminar');
      await tester.pump();
      await tester.scrollUntilVisible(button, 300, scrollable: find.byType(Scrollable).first);
      expect(tester.widget<FilledButton>(button).onPressed, isNull);

      await tester.enterText(field('Escribe ELIMINAR para confirmar'), 'ELIMINAR');
      await tester.pump();
      expect(tester.widget<FilledButton>(button).onPressed, isNotNull);
      await tester.tap(button);
      await tester.pump();
      verify(() => auth.deleteAccount('Quito2026')).called(1);
    });
  });

  group('Reauthentication sheet (COU-86, COU-147, COU-162)', () {
    Future<bool?> open(WidgetTester tester) async {
      bool? result;
      await tester.pumpApp(
        Builder(
          builder: (context) => TextButton(
            onPressed: () async => result = await confirmIdentity(
              context,
              action: 'eliminar «Hogar»',
              confirmLabel: 'Eliminar billetera',
              consequences: 'Se cerrarán sus presupuestos.',
            ),
            child: const Text('abrir'),
          ),
        ),
        auth: auth,
      );
      await tester.tap(find.text('abrir'));
      await tester.pumpAndSettle();
      return result;
    }

    testWidgets('explains the action and returns true after a correct password', (tester) async {
      when(() => auth.reauthenticate('Quito2026')).thenAnswer((_) async => DateTime(2026, 10, 3, 12, 5));
      bool? result;
      await tester.pumpApp(
        Builder(
          builder: (context) => TextButton(
            onPressed: () async =>
                result = await confirmIdentity(context, action: 'eliminar «Hogar»', confirmLabel: 'Eliminar billetera'),
            child: const Text('abrir'),
          ),
        ),
        auth: auth,
      );
      await tester.tap(find.text('abrir'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Para eliminar «Hogar» escribe tu contraseña'), findsOneWidget);

      await tester.enterText(find.byType(EditableText), 'Quito2026');
      await tester.tap(find.text('Eliminar billetera'));
      await tester.pumpAndSettle();
      expect(result, isTrue);
    });

    testWidgets('a wrong password stays in the sheet with the message', (tester) async {
      when(() => auth.reauthenticate(any())).thenThrow(_wrong);
      await open(tester);
      expect(find.text('Se cerrarán sus presupuestos.'), findsOneWidget);
      await tester.enterText(find.byType(EditableText), 'x');
      await tester.tap(find.text('Eliminar billetera'));
      await tester.pumpAndSettle();
      expect(find.text('Contraseña incorrecta'), findsOneWidget);
      expect(find.text('Confirma que eres tú'), findsOneWidget);
    });

    testWidgets('after a wrong password, typing again allows another attempt', (tester) async {
      when(() => auth.reauthenticate(any())).thenThrow(_wrong);
      await open(tester);
      await tester.enterText(find.byType(EditableText), 'x');
      await tester.tap(find.text('Eliminar billetera'));
      await tester.pumpAndSettle();
      expect(find.text('Contraseña incorrecta'), findsOneWidget);

      when(() => auth.reauthenticate('Quito2026')).thenAnswer((_) async => DateTime(2026, 10, 3, 12, 5));
      await tester.enterText(find.byType(EditableText), 'Quito2026');
      await tester.pumpAndSettle();
      expect(find.text('Contraseña incorrecta'), findsNothing, reason: 'the forced error would keep the form invalid');
      await tester.tap(find.text('Eliminar billetera'));
      await tester.pumpAndSettle();
      verify(() => auth.reauthenticate('Quito2026')).called(1);
      expect(find.text('Confirma que eres tú'), findsNothing);
    });

    testWidgets('a 429 blocks the confirmation until Retry-After, even after reopening the sheet', (tester) async {
      const limited = AppFailure(
        kind: FailureKind.rateLimited,
        message: 'Demasiados intentos fallidos. Intente nuevamente en 2 minutos.',
        key: 'rate_limited',
        status: 429,
        retryAfter: Duration(seconds: 90),
      );
      when(() => auth.reauthenticate(any())).thenThrow(limited);
      await open(tester);
      await tester.enterText(find.byType(EditableText), 'x');
      await tester.tap(find.text('Eliminar billetera'));
      await tester.pumpAndSettle();
      expect(find.text(limited.message), findsOneWidget);
      expect(find.text('Espera 1:30'), findsOneWidget);
      FilledButton confirm() => tester.widget<FilledButton>(
        find.ancestor(of: find.textContaining('Espera'), matching: find.byType(FilledButton)),
      );
      expect(confirm().onPressed, isNull);

      // The keyboard's «done» does not bypass the block.
      await tester.enterText(find.byType(EditableText), 'Quito2026');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      verify(() => auth.reauthenticate(any())).called(1);

      // Closing and starting the deletion again keeps the block and its message.
      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('abrir'));
      await tester.pumpAndSettle();
      expect(find.text(limited.message), findsOneWidget);
      expect(confirm().onPressed, isNull);

      // Once the wait is over the sheet can confirm again.
      when(() => auth.reauthenticate('Quito2026')).thenAnswer((_) async => DateTime(2026, 10, 3, 12, 5));
      await tester.pump(const Duration(seconds: 91));
      expect(find.text('Eliminar billetera'), findsOneWidget);
      await tester.enterText(find.byType(EditableText), 'Quito2026');
      await tester.tap(find.text('Eliminar billetera'));
      await tester.pumpAndSettle();
      verify(() => auth.reauthenticate('Quito2026')).called(1);
      expect(find.text('Confirma que eres tú'), findsNothing);
    });

    testWidgets('a 429 without Retry-After blocks for the 2-minute window', (tester) async {
      when(() => auth.reauthenticate(any())).thenThrow(
        const AppFailure(
          kind: FailureKind.rateLimited,
          message: 'Demasiados intentos',
          key: 'rate_limited',
          status: 429,
        ),
      );
      await open(tester);
      await tester.enterText(find.byType(EditableText), 'x');
      await tester.tap(find.text('Eliminar billetera'));
      await tester.pumpAndSettle();
      expect(find.text('Espera 2:00'), findsOneWidget);
    });

    testWidgets('a locked account disables the confirmation', (tester) async {
      when(() => auth.reauthenticate(any())).thenThrow(
        const AppFailure(
          kind: FailureKind.locked,
          message: 'Tu cuenta está bloqueada temporalmente',
          key: 'account_locked',
          status: 423,
        ),
      );
      await open(tester);
      await tester.enterText(find.byType(EditableText), 'x');
      await tester.tap(find.text('Eliminar billetera'));
      await tester.pumpAndSettle();
      expect(find.text('Tu cuenta está bloqueada temporalmente'), findsOneWidget);
      expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Eliminar billetera')).onPressed, isNull);
    });

    testWidgets('cancel returns false', (tester) async {
      bool? result;
      await tester.pumpApp(
        Builder(
          builder: (context) => TextButton(
            onPressed: () async => result = await confirmIdentity(context, action: 'x', confirmLabel: 'Eliminar'),
            child: const Text('abrir'),
          ),
        ),
        auth: auth,
      );
      await tester.tap(find.text('abrir'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();
      expect(result, isFalse);
    });
  });
}
