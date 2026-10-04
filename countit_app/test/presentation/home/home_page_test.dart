import 'package:bloc_test/bloc_test.dart';
import 'package:countit_app/app/errors/app_failure.dart';
import 'package:countit_app/app/router/app_router.dart';
import 'package:countit_app/app/session/session_cubit.dart';
import 'package:countit_app/data/dtos/profile.dart';
import 'package:countit_app/data/dtos/wallet.dart';
import 'package:countit_app/presentation/home/cubit/wallets_cubit.dart';
import 'package:countit_app/presentation/home/view/home_page.dart';
import 'package:countit_app/presentation/wallets/view/widgets/wallet_card.dart';
import 'package:countit_app/shared/state/load_state.dart';
import 'package:countit_app/shared/utils/dates.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';

import '../../helpers/mocks.dart';
import '../../helpers/pump_app.dart';
import '../../helpers/wallet_fixtures.dart';

const _network = AppFailure(kind: FailureKind.network, message: 'No hay conexión.');

const _profile = Profile(
  userId: 'u1',
  username: 'mariaq',
  email: 'maria@correo.ec',
  firstName: 'María',
  lastName: 'Quishpe',
  role: UserRole.user,
  timezone: 'America/Guayaquil',
);

void main() {
  late MockWalletRepository wallets;
  late MockAuthRepository auth;
  late MockProfileRepository profiles;

  setUpAll(Dates.init);

  setUp(() {
    wallets = MockWalletRepository();
    auth = MockAuthRepository();
    profiles = MockProfileRepository();
    when(() => auth.sessionChanges).thenAnswer((_) => const Stream.empty());
    when(() => auth.hasSession).thenReturn(true);
    when(() => profiles.fetchMyProfile()).thenAnswer((_) async => _profile);
  });

  group('WalletsCubit (COU-188)', () {
    blocTest<WalletsCubit, LoadState<List<Wallet>>>(
      'loads the wallets',
      setUp: () => when(() => wallets.list()).thenAnswer((_) async => [walletFixture()]),
      build: () => WalletsCubit(wallets),
      act: (cubit) => cubit.load(),
      expect: () => [
        const LoadState<List<Wallet>>.loading(),
        LoadState.success([walletFixture()]),
      ],
    );

    blocTest<WalletsCubit, LoadState<List<Wallet>>>(
      'a failed reload keeps the previous list',
      setUp: () => when(() => wallets.list()).thenThrow(_network),
      build: () => WalletsCubit(wallets),
      seed: () => LoadState.success([walletFixture()]),
      act: (cubit) => cubit.load(),
      expect: () => [
        LoadState<List<Wallet>>.loading(previous: [walletFixture()]),
        LoadState<List<Wallet>>.failure(_network, previous: [walletFixture()]),
      ],
    );

    test('concurrent loads share one request', () async {
      when(() => wallets.list()).thenAnswer((_) async => []);
      final cubit = WalletsCubit(wallets);
      await Future.wait([cubit.load(), cubit.load()]);
      verify(() => wallets.list()).called(1);
      await cubit.close();
    });

    test('groups own and shared wallets and sums the own balances', () {
      final list = [
        walletFixture(id: 1, balance: 10.1),
        walletFixture(id: 2, isOwner: false, balance: 500),
        walletFixture(id: 3, balance: 0.2),
      ];
      expect(list.own.map((w) => w.walletId), [1, 3]);
      expect(list.sharedWithMe.map((w) => w.walletId), [2]);
      expect(list.ownBalanceCents, 1030);
    });
  });

  group('HomePage (COU-187, COU-189, COU-215)', () {
    Future<SessionCubit> signedIn() async {
      final session = SessionCubit(auth: auth, profiles: profiles);
      addTearDown(session.close);
      await session.restore();
      return session;
    }

    /// Home plus stand-ins for the screens it opens, to check navigation.
    GoRouter router() => GoRouter(
      initialLocation: AppRoutes.home,
      routes: [
        GoRoute(path: AppRoutes.home, builder: (context, state) => const HomePage()),
        GoRoute(
          path: AppRoutes.newWallet,
          builder: (context, state) => const Scaffold(body: Text('FORM')),
        ),
        GoRoute(
          path: '${AppRoutes.wallets}/:id',
          builder: (context, state) => Scaffold(body: Text('DETAIL ${state.pathParameters['id']}')),
        ),
      ],
    );

    Future<void> pumpHome(WidgetTester tester) async {
      await tester.pumpApp(const SizedBox(), auth: auth, wallets: wallets, session: await signedIn(), router: router());
    }

    testWidgets('first load shows a spinner, then the greeting', (tester) async {
      when(() => wallets.list()).thenAnswer((_) => Future.delayed(const Duration(seconds: 1), () => [walletFixture()]));
      await pumpHome(tester);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      await tester.pumpAndSettle(const Duration(seconds: 1));
      expect(find.text('Hola, María'), findsOneWidget);
      expect(find.byType(WalletCard), findsOneWidget);
    });

    testWidgets('error without data: ErrorView with «Reintentar» that reloads', (tester) async {
      when(() => wallets.list()).thenThrow(_network);
      await pumpHome(tester);
      await tester.pumpAndSettle();
      expect(find.text('No pudimos cargar esto'), findsOneWidget);
      expect(find.text('No hay conexión.'), findsOneWidget);

      when(() => wallets.list()).thenAnswer((_) async => [walletFixture()]);
      await tester.tap(find.text('Reintentar'));
      await tester.pumpAndSettle();
      expect(find.byType(WalletCard), findsOneWidget);
    });

    testWidgets('empty: «Crea tu primera billetera» opens the form', (tester) async {
      when(() => wallets.list()).thenAnswer((_) async => []);
      await pumpHome(tester);
      await tester.pumpAndSettle();
      expect(find.text('Crea tu primera billetera'), findsOneWidget);
      expect(find.text('SALDO TOTAL'), findsNothing);

      await tester.tap(find.widgetWithText(FilledButton, 'Nueva billetera'));
      await tester.pumpAndSettle();
      expect(find.text('FORM'), findsOneWidget);
    });

    testWidgets('own and shared wallets in their sections; the empty state is gone', (tester) async {
      when(() => wallets.list()).thenAnswer(
        (_) async => [
          walletFixture(id: 1, name: 'Ahorros', balance: 100),
          walletFixture(id: 2, name: 'Casa compartida', isOwner: false, balance: 999),
        ],
      );
      await pumpHome(tester);
      await tester.pumpAndSettle();
      expect(find.text('Crea tu primera billetera'), findsNothing);
      expect(find.text('Mis billeteras'), findsOneWidget);
      expect(find.text('Compartidas conmigo'), findsOneWidget);
      expect(find.text('Ahorros'), findsOneWidget);
      expect(find.text('Casa compartida'), findsOneWidget);
      // Only own wallets add up to the total.
      expect(find.text(r'$100,00'), findsWidgets);
      expect(find.text('En tu billetera'), findsOneWidget);
    });

    testWidgets('no shared wallets: the shared section explains it', (tester) async {
      when(() => wallets.list()).thenAnswer((_) async => [walletFixture()]);
      await pumpHome(tester);
      await tester.pumpAndSettle();
      expect(find.text('Nadie ha compartido una billetera contigo todavía.'), findsOneWidget);
    });

    testWidgets('only shared wallets: the own section invites to create one', (tester) async {
      when(() => wallets.list()).thenAnswer((_) async => [walletFixture(isOwner: false)]);
      await pumpHome(tester);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Crear billetera'));
      await tester.pumpAndSettle();
      expect(find.text('FORM'), findsOneWidget);
    });

    testWidgets('tapping a card opens its detail and the list reloads on the way back', (tester) async {
      when(() => wallets.list()).thenAnswer((_) async => [walletFixture(id: 4, balance: 10)]);
      await pumpHome(tester);
      await tester.pumpAndSettle();

      await tester.tap(find.byType(WalletCard));
      await tester.pumpAndSettle();
      expect(find.text('DETAIL 4'), findsOneWidget);

      // A new movement changed the balance meanwhile.
      when(() => wallets.list()).thenAnswer((_) async => [walletFixture(id: 4, balance: 25)]);
      tester.state<NavigatorState>(find.byType(Navigator).last).pop();
      await tester.pumpAndSettle();
      expect(find.text(r'$25,00'), findsWidgets);
      verify(() => wallets.list()).called(2);
    });

    testWidgets('a failed refresh keeps the list and shows the error in a snackbar', (tester) async {
      when(() => wallets.list()).thenAnswer((_) async => [walletFixture(name: 'Ahorros')]);
      await pumpHome(tester);
      await tester.pumpAndSettle();

      when(() => wallets.list()).thenThrow(_network);
      await tester.fling(find.byType(CustomScrollView), const Offset(0, 400), 1000);
      await tester.pumpAndSettle();
      expect(find.text('Ahorros'), findsOneWidget);
      expect(find.text('No hay conexión.'), findsOneWidget);
      expect(find.text('No pudimos cargar esto'), findsNothing);
    });

    testWidgets('60 wallets with long names scroll lazily without overflow', (tester) async {
      when(() => wallets.list()).thenAnswer(
        (_) async => [
          for (var i = 0; i < 60; i++)
            walletFixture(id: i, name: 'Billetera con un nombre larguísimo que no cabe número $i', balance: i * 1000.0),
        ],
      );
      await pumpHome(tester);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      // Lazy: far fewer cards than wallets are built.
      expect(find.byType(WalletCard).evaluate().length, lessThan(20));
      await tester.dragUntilVisible(
        find.textContaining('número 59'),
        find.byType(CustomScrollView),
        const Offset(0, -500),
      );
      expect(find.textContaining('número 59'), findsOneWidget);
    });
  });
}
