import 'package:bloc_test/bloc_test.dart';
import 'package:countit_app/app/errors/app_failure.dart';
import 'package:countit_app/app/session/session_cubit.dart';
import 'package:countit_app/app/session/session_state.dart';
import 'package:countit_app/data/dtos/profile.dart';
import 'package:countit_app/presentation/plans/view/plan_details.dart';
import 'package:countit_app/presentation/profile/cubit/profile_cubits.dart';
import 'package:countit_app/presentation/profile/view/about_page.dart';
import 'package:countit_app/presentation/profile/view/profile_page.dart';
import 'package:countit_app/presentation/profile/view/timezone_picker.dart';
import 'package:countit_app/presentation/wallets/view/widgets/bank_disclaimer.dart';
import 'package:countit_app/shared/platform/file_sharer.dart';
import 'package:countit_app/shared/state/submit_cubit.dart';
import 'package:countit_app/shared/utils/dates.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../../helpers/mocks.dart';
import '../../helpers/pump_app.dart';

class _FakeSharer implements FileSharer {
  String? fileName;
  String? contents;

  @override
  Future<void> shareJson({required String fileName, required String contents, String? subject}) async {
    this.fileName = fileName;
    this.contents = contents;
  }
}

const _contador = UserPlan(
  planId: 2,
  name: 'Contador',
  limits: {
    'max_wallets': 10,
    'max_budgets_per_wallet': 14,
    'max_daily_transactions': 40,
    'max_scheduled_transactions': 10,
    'max_families': 2,
    'max_family_users': 3,
    'family_feature': 1,
    'advanced_statistics': 1,
    'wallet_projection': 0,
  },
);

Profile _profile({UserRole role = UserRole.user}) => Profile(
  userId: 'u1',
  username: 'mariaq',
  email: 'maria@correo.ec',
  firstName: 'María',
  lastName: 'Quishpe',
  role: role,
  timezone: 'America/Guayaquil',
  plan: _contador,
);

void main() {
  late MockAuthRepository auth;
  late MockProfileRepository profiles;

  setUpAll(Dates.init);

  setUp(() {
    auth = MockAuthRepository();
    profiles = MockProfileRepository();
    when(() => auth.sessionChanges).thenAnswer((_) => const Stream.empty());
    when(() => auth.signOut()).thenAnswer((_) async {});
  });

  test('plan quotas and features are structured for the plan card', () {
    expect(planQuotas(_contador).map((q) => '${q.label}: ${q.value}'), [
      'Billeteras: 10',
      'Presupuestos por billetera: 14',
      'Movimientos por día: 40',
      'Programadas activas: 10',
      'Billeteras compartidas: 2',
      'Miembros por billetera: 3',
    ]);
    expect(planFeatures(_contador).map((f) => '${f.label}: ${f.included}'), [
      'Billeteras compartidas: true',
      'Estadísticas avanzadas: true',
      'Proyección de saldo: false',
    ]);
    const pro = UserPlan(planId: 3, name: 'Contador Profesional', limits: {'max_wallets': 999, 'wallet_projection': 1});
    expect(planQuotas(pro).map((q) => '${q.label}: ${q.value}'), ['Billeteras: Ilimitadas']);
    expect(planFeatures(pro).where((f) => f.included).map((f) => f.label), ['Proyección de saldo']);
  });

  test('the time-zone list starts with Guayaquil and only has IANA names', () {
    final names = timezoneNames();
    expect(names.first, 'America/Guayaquil');
    expect(names, contains('Europe/Madrid'));
    expect(names.where((n) => !n.contains('/')), isEmpty);
  });

  group('EditProfileCubit (COU-146)', () {
    late SessionCubit session;

    setUp(() {
      session = SessionCubit(auth: auth, profiles: profiles)..emit(SessionState.authenticated(_profile()));
      when(
        () => profiles.updateMyProfile(
          firstName: any(named: 'firstName'),
          lastName: any(named: 'lastName'),
          username: any(named: 'username'),
          timezone: any(named: 'timezone'),
        ),
      ).thenAnswer((_) async {});
      when(profiles.fetchMyProfile).thenAnswer((_) async => _profile());
    });

    tearDown(() => session.close());

    blocTest<EditProfileCubit, SubmitState>(
      'sends only what changed and refreshes the session profile',
      build: () => EditProfileCubit(profiles: profiles, session: session),
      act: (c) => c.save(
        original: _profile(),
        firstName: ' María José ',
        lastName: 'Quishpe',
        username: 'mariaq',
        timezone: 'America/Guayaquil',
      ),
      verify: (_) {
        verify(
          () => profiles.updateMyProfile(firstName: 'María José', lastName: 'Quishpe', username: null, timezone: null),
        ).called(1);
        verify(profiles.fetchMyProfile).called(1);
      },
    );

    blocTest<EditProfileCubit, SubmitState>(
      'a new username and zone are sent',
      build: () => EditProfileCubit(profiles: profiles, session: session),
      act: (c) => c.save(
        original: _profile(),
        firstName: 'María',
        lastName: 'Quishpe',
        username: 'mquishpe',
        timezone: 'Europe/Madrid',
      ),
      verify: (_) => verify(
        () => profiles.updateMyProfile(
          firstName: 'María',
          lastName: 'Quishpe',
          username: 'mquishpe',
          timezone: 'Europe/Madrid',
        ),
      ).called(1),
    );
  });

  group('ExportDataCubit (COU-148)', () {
    blocTest<ExportDataCubit, SubmitState>(
      'writes pretty JSON named by date and shares it',
      setUp: () => when(profiles.exportMyData).thenAnswer(
        (_) async => {
          'profile': {'username': 'mariaq'},
        },
      ),
      build: () => ExportDataCubit(profiles: profiles, sharer: _FakeSharer()),
      act: (c) => c.export(),
      verify: (c) {
        expect(ExportDataCubit.fileName(DateTime(2026, 10, 3)), 'countit-datos-2026-10-03.json');
      },
    );

    test('the shared file holds the export', () async {
      when(profiles.exportMyData).thenAnswer(
        (_) async => {
          'profile': {'username': 'mariaq'},
        },
      );
      final sharer = _FakeSharer();
      final cubit = ExportDataCubit(profiles: profiles, sharer: sharer);
      expect(await cubit.export(), isTrue);
      expect(sharer.fileName, startsWith('countit-datos-'));
      expect(sharer.contents, contains('"username": "mariaq"'));
      await cubit.close();
    });
  });

  group('Profile screen (COU-143, COU-128)', () {
    Future<SessionCubit> pump(WidgetTester tester, Profile profile, {FileSharer? sharer}) async {
      final session = SessionCubit(auth: auth, profiles: profiles)..emit(SessionState.authenticated(profile));
      addTearDown(session.close);
      await tester.pumpApp(
        ProfilePage(sharer: sharer ?? _FakeSharer()),
        auth: auth,
        profiles: profiles,
        session: session,
      );
      return session;
    }

    testWidgets('shows identity, plan and account actions', (tester) async {
      await pump(tester, _profile());
      expect(find.text('María Quishpe'), findsOneWidget);
      expect(find.text('@mariaq · America/Guayaquil'), findsOneWidget);
      // The plan is summarised; limits and features live in «Mi plan» (COU-113).
      expect(find.text('Contador'), findsOneWidget);
      expect(find.byKey(const ValueKey('profile-plan-card')), findsOneWidget);
      expect(find.text('Movimientos por día'), findsNothing);
      for (final label in [
        'Datos personales',
        'Cambiar contraseña',
        'Exportar mis datos',
        'Eliminar mi cuenta',
        'Acerca de Count It!',
      ]) {
        await tester.scrollUntilVisible(find.text(label), 200);
        expect(find.text(label), findsOneWidget, reason: label);
      }
      expect(find.text('Administración'), findsNothing);
    });

    testWidgets('administration only for admins', (tester) async {
      await pump(tester, _profile(role: UserRole.admin));
      await tester.scrollUntilVisible(find.text('Administración'), 200);
      expect(find.text('Administración'), findsOneWidget);
    });

    testWidgets('sign-out asks first, then clears the session', (tester) async {
      final session = await pump(tester, _profile());
      await tester.scrollUntilVisible(find.text('Cerrar sesión'), 200);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cerrar sesión'));
      await tester.pumpAndSettle();
      expect(find.text('¿Cerrar sesión?'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Cerrar sesión'));
      // Without a router the page stays (showing a spinner); the app redirects away.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(session.state, const SessionState.unauthenticated());
      verify(() => auth.signOut()).called(1);
    });

    testWidgets('an export failure is reported', (tester) async {
      when(profiles.exportMyData).thenThrow(const AppFailure(kind: FailureKind.network, message: 'No hay conexión'));
      await pump(tester, _profile());
      await tester.scrollUntilVisible(find.text('Exportar mis datos'), 200);
      await tester.ensureVisible(find.text('Exportar mis datos'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Exportar mis datos'));
      await tester.pumpAndSettle();
      expect(find.text('No hay conexión'), findsOneWidget);
    });
  });

  group('About page (bank non-affiliation)', () {
    testWidgets('shows the bank disclaimer and the legal links', (tester) async {
      await tester.pumpApp(AboutPage(openLink: (_) async => true));
      expect(find.text('Acerca de Count It!'), findsOneWidget);
      expect(find.byType(BankDisclaimer), findsOneWidget);
      expect(
        find.text(
          'Los nombres de bancos se muestran solo para que identifiques tus cuentas y pertenecen a sus '
          'titulares. Count It! no está afiliada ni respaldada por ninguna entidad financiera.',
        ),
        findsOneWidget,
      );
      expect(find.text('https://countit-bft.pages.dev/privacidad/'), findsOneWidget);
      expect(find.text('https://countit-bft.pages.dev/terminos/'), findsOneWidget);
    });

    testWidgets('the links open outside the app; a failure shows the address', (tester) async {
      final opened = <Uri>[];
      await tester.pumpApp(
        AboutPage(
          openLink: (url) async {
            opened.add(url);
            return url == AboutPage.privacyUrl;
          },
        ),
      );
      await tester.tap(find.byKey(const ValueKey('about-privacy')));
      await tester.pumpAndSettle();
      expect(opened, [AboutPage.privacyUrl]);
      expect(find.textContaining('No pudimos abrir el enlace'), findsNothing);
      await tester.tap(find.byKey(const ValueKey('about-terms')));
      await tester.pumpAndSettle();
      expect(opened.last, AboutPage.termsUrl);
      expect(find.text('No pudimos abrir el enlace: https://countit-bft.pages.dev/terminos/'), findsOneWidget);
    });
  });
}
