import 'package:countit_app/app/router/app_router.dart';
import 'package:countit_app/app/session/session_cubit.dart';
import 'package:countit_app/data/dtos/profile.dart';
import 'package:countit_app/presentation/wallets/view/widgets/wallet_card.dart';
import 'package:countit_app/shared/utils/dates.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../../helpers/mocks.dart';
import '../../helpers/pump_app.dart';
import '../../helpers/wallet_fixtures.dart';

const _profile = Profile(
  userId: 'u1',
  username: 'mariaq',
  email: 'maria@correo.ec',
  firstName: 'María',
  role: UserRole.user,
  timezone: 'America/Guayaquil',
);

void main() {
  late MockAuthRepository auth;
  late MockProfileRepository profiles;
  late MockWalletRepository wallets;

  setUpAll(Dates.init);

  setUp(() {
    auth = MockAuthRepository();
    profiles = MockProfileRepository();
    wallets = MockWalletRepository();
    when(() => auth.sessionChanges).thenAnswer((_) => const Stream.empty());
    when(() => auth.hasSession).thenReturn(true);
    when(() => profiles.fetchMyProfile()).thenAnswer((_) async => _profile);
    when(() => wallets.list())
        .thenAnswer((_) async => [for (var i = 0; i < 30; i++) walletFixture(id: i, name: 'Billetera $i')]);
  });

  Future<void> pumpShell(WidgetTester tester) async {
    final session = SessionCubit(auth: auth, profiles: profiles);
    addTearDown(session.close);
    await session.restore();
    final router = buildRouter(session: session, config: testConfig);
    addTearDown(router.dispose);
    await tester.pumpApp(
      const SizedBox(),
      auth: auth,
      profiles: profiles,
      wallets: wallets,
      session: session,
      router: router,
    );
    await tester.pumpAndSettle();
  }

  double homeOffset(WidgetTester tester) =>
      tester.state<ScrollableState>(find.byType(Scrollable).first).position.pixels;

  testWidgets('signed in lands on «Inicio» with the bottom navigation (COU-168)', (tester) async {
    await pumpShell(tester);
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.text('Hola, María'), findsOneWidget);
    expect(find.byType(WalletCard), findsWidgets);
  });

  testWidgets('switching tabs keeps the home scroll position and does not reload', (tester) async {
    await pumpShell(tester);
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -600));
    await tester.pumpAndSettle();
    final offset = homeOffset(tester);
    expect(offset, greaterThan(0));

    await tester.tap(find.text('Perfil'));
    await tester.pumpAndSettle();
    expect(find.text('Cerrar sesión'), findsOneWidget);

    await tester.tap(find.text('Inicio'));
    await tester.pumpAndSettle();
    expect(homeOffset(tester), offset);
    verify(() => wallets.list()).called(1);
  });

  testWidgets('system back on «Perfil» returns to «Inicio» instead of leaving', (tester) async {
    await pumpShell(tester);
    await tester.tap(find.text('Perfil'));
    await tester.pumpAndSettle();

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('Hola, María'), findsOneWidget);
    final bar = tester.widget<NavigationBar>(find.byType(NavigationBar));
    expect(bar.selectedIndex, 0);
  });

  testWidgets('profile sub-screens cover the bottom bar and back returns to the tab', (tester) async {
    await pumpShell(tester);
    await tester.tap(find.text('Perfil'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Datos personales'));
    await tester.pumpAndSettle();
    expect(find.byType(NavigationBar), findsNothing);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.text('Cerrar sesión'), findsOneWidget);
  });

  test('the root path leads home', () {
    expect(AppRoutes.wallet(3), '/wallets/3');
    expect(AppRoutes.editWallet(3), '/wallets/3/edit');
  });
}
