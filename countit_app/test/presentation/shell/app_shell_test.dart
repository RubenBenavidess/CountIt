import 'package:countit_app/app/router/app_router.dart';
import 'package:countit_app/app/session/session_cubit.dart';
import 'package:countit_app/data/dtos/paged.dart';
import 'package:countit_app/data/dtos/profile.dart';
import 'package:countit_app/data/dtos/statistics.dart';
import 'package:countit_app/data/dtos/transaction.dart';
import 'package:countit_app/presentation/notifications/cubit/notifications_cubit.dart';
import 'package:countit_app/presentation/wallets/view/widgets/wallet_card.dart';
import 'package:countit_app/shared/utils/dates.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../../helpers/mocks.dart';
import '../../helpers/notification_fixtures.dart';
import '../../helpers/pump_app.dart';
import '../../helpers/statistics_fixtures.dart';
import '../../helpers/transaction_fixtures.dart';
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

  Future<void> pumpShell(
    WidgetTester tester, {
    NotificationsCubit? notifications,
    MockTransactionRepository? transactions,
    MockAnalysisRepository? analysis,
    MockBudgetRepository? budgets,
  }) async {
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
      notificationsCubit: notifications,
      transactions: transactions,
      analysis: analysis,
      budgets: budgets,
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

  testWidgets('«Avisos» shows the unread badge and opens the inbox (COU-111)', (tester) async {
    final semantics = tester.ensureSemantics();
    final repository = noNotifications();
    when(() => repository.inbox())
        .thenAnswer((_) async => Paged([notificationFixture(id: 2), notificationFixture(id: 1)], hasMore: false));
    when(repository.unreadCount).thenAnswer((_) async => 2);
    final notifications = NotificationsCubit(repository);
    addTearDown(notifications.close);
    await notifications.setUser('u1');
    await pumpShell(tester, notifications: notifications);

    expect(find.descendant(of: find.byType(NavigationBar), matching: find.text('2')), findsOneWidget);
    expect(find.byTooltip('Avisos: 2 sin leer'), findsOneWidget);

    await tester.tap(find.text('Avisos'));
    await tester.pumpAndSettle();
    expect(find.text('Notificaciones'), findsOneWidget);

    await tester.tap(find.byTooltip('Marcar todas como leídas'));
    await tester.pumpAndSettle();
    expect(find.descendant(of: find.byType(NavigationBar), matching: find.text('2')), findsNothing);
    expect(find.byTooltip('Avisos'), findsOneWidget);
    semantics.dispose();
  });

  Finder tab(String label) => find.descendant(of: find.byType(NavigationBar), matching: find.text(label));

  testWidgets('five tabs, in the order of the design', (tester) async {
    await pumpShell(tester);
    final bar = tester.widget<NavigationBar>(find.byType(NavigationBar));
    expect(
      [for (final d in bar.destinations) (d as NavigationDestination).label],
      ['Inicio', 'Movimientos', 'Estadísticas', 'Avisos', 'Perfil'],
    );
  });

  group('«Movimientos» tab', () {
    late MockTransactionRepository transactions;

    setUp(() {
      transactions = MockTransactionRepository();
      when(() => wallets.list()).thenAnswer(
        (_) async => [
          walletFixture(id: 4, name: 'Pichincha'),
          walletFixture(id: 5, name: 'Viaje', isOwner: false, ownerName: 'Lucía'),
        ],
      );
      when(() => transactions.list(any(), filter: any(named: 'filter'))).thenAnswer(
        (invocation) async => TransactionPage([
          if (invocation.positionalArguments.first != 5)
            transactionFixture(id: 2, walletId: 4, walletName: 'Pichincha', name: 'Almuerzo'),
          transactionFixture(id: 1, walletId: 5, walletName: 'Viaje', name: 'Hotel', authorName: 'Lucía'),
        ]),
      );
    });

    setUpAll(() => registerFallbackValue(const TransactionFilter()));

    testWidgets('lists every wallet, naming each movement\'s wallet; picking one filters', (tester) async {
      await pumpShell(tester, transactions: transactions);
      await tester.tap(tab('Movimientos'));
      await tester.pumpAndSettle();

      verify(() => transactions.list(null, filter: const TransactionFilter())).called(1);
      expect(find.text('Historial'), findsOneWidget);
      expect(find.text('Pichincha · Sin presupuesto'), findsOneWidget);
      // Shared wallet: its movements also say who registered them.
      expect(find.text('Viaje · Sin presupuesto · Lucía'), findsOneWidget);

      await tester.tap(find.text('Todas las billeteras'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Viaje').last);
      await tester.pumpAndSettle();
      verify(() => transactions.list(5, filter: const TransactionFilter())).called(1);
      expect(find.text('Almuerzo'), findsNothing);
      expect(find.text('Sin presupuesto · Lucía'), findsOneWidget);
    });

    testWidgets('coming back to the tab reloads what changed elsewhere', (tester) async {
      await pumpShell(tester, transactions: transactions);
      await tester.tap(tab('Movimientos'));
      await tester.pumpAndSettle();
      await tester.tap(tab('Inicio'));
      await tester.pumpAndSettle();
      await tester.tap(tab('Movimientos'));
      await tester.pumpAndSettle();
      verify(() => transactions.list(null, filter: const TransactionFilter())).called(2);
    });

    testWidgets('«Movimiento» asks for the wallet and opens its form', (tester) async {
      final budgets = MockBudgetRepository();
      when(() => budgets.listByWallet(any())).thenAnswer((_) async => []);
      await pumpShell(tester, transactions: transactions, budgets: budgets);
      await tester.tap(tab('Movimientos'));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Registrar un movimiento'));
      await tester.pumpAndSettle();
      expect(find.text('¿En qué billetera?'), findsOneWidget);
      expect(find.text('Compartida por Lucía'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('pick-wallet-5')));
      await tester.pumpAndSettle();
      expect(find.text('Nuevo movimiento'), findsOneWidget);
      expect(find.byType(NavigationBar), findsNothing);
    });
  });

  testWidgets('«Estadísticas» tab starts on the first own wallet and offers the projection', (tester) async {
    final analysis = MockAnalysisRepository();
    when(() => wallets.list()).thenAnswer(
      (_) async => [walletFixture(id: 9, name: 'De Lucía', isOwner: false), walletFixture(id: 4, name: 'Pichincha')],
    );
    when(() => analysis.walletStatistics(4, StatisticsRange.days30)).thenAnswer((_) async => statisticsFixture());
    await pumpShell(tester, analysis: analysis);
    await tester.tap(tab('Estadísticas'));
    await tester.pumpAndSettle();

    verify(() => analysis.walletStatistics(4, StatisticsRange.days30)).called(1);
    expect(find.text('Pichincha'), findsOneWidget);
    expect(find.byKey(const ValueKey('statistics-projection')), findsOneWidget);
    expect(find.byTooltip('Volver'), findsNothing);
  });

  test('the root path leads home', () {
    expect(AppRoutes.wallet(3), '/wallets/3');
    expect(AppRoutes.editWallet(3), '/wallets/3/edit');
  });
}
