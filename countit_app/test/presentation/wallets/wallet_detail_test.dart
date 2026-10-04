import 'package:countit_app/app/errors/app_failure.dart';
import 'package:countit_app/app/router/app_router.dart';
import 'package:countit_app/data/dtos/wallet.dart';
import 'package:countit_app/data/remote/api_client.dart';
import 'package:countit_app/presentation/wallets/view/wallet_detail_page.dart';
import 'package:countit_app/shared/utils/dates.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';

import '../../helpers/mocks.dart';
import '../../helpers/pump_app.dart';
import '../../helpers/wallet_fixtures.dart';

const _notFound = AppFailure(
  kind: FailureKind.notFound,
  message: 'Billetera no encontrada',
  key: 'wallet_not_found',
  status: 404,
);
const _reauthRequired = AppFailure(
  kind: FailureKind.reauthRequired,
  message: 'Confirma tu contraseña para continuar',
  key: 'reauth_required',
  status: 403,
);
const _network = AppFailure(kind: FailureKind.network, message: 'No hay conexión.');

void main() {
  late MockWalletRepository wallets;
  late MockAuthRepository auth;

  setUpAll(Dates.init);

  setUp(() {
    wallets = MockWalletRepository();
    auth = MockAuthRepository();
    when(() => auth.sessionChanges).thenAnswer((_) => const Stream.empty());
  });

  /// Home → detail of [wallet]; the edit route is a stand-in.
  Future<void> pumpDetail(WidgetTester tester, Wallet wallet) async {
    tester.view.physicalSize = const Size(420, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final router = GoRouter(
      initialLocation: AppRoutes.home,
      routes: [
        GoRoute(
          path: AppRoutes.home,
          builder: (context, state) => Scaffold(
            body: TextButton(
              onPressed: () => context.push(AppRoutes.wallet(wallet.walletId), extra: wallet),
              child: const Text('HOME'),
            ),
          ),
        ),
        GoRoute(
          path: '${AppRoutes.wallets}/:id',
          builder: (context, state) =>
              WalletDetailPage(walletId: int.parse(state.pathParameters['id']!), initial: state.extra as Wallet?),
          routes: [
            GoRoute(
              path: 'edit',
              builder: (context, state) => const Scaffold(body: Text('EDIT FORM')),
            ),
          ],
        ),
      ],
    );
    await tester.pumpApp(const SizedBox(), auth: auth, wallets: wallets, router: router);
    await tester.tap(find.text('HOME'));
    await tester.pumpAndSettle();
  }

  Future<void> tapButton(WidgetTester tester, String label) async {
    final button = find.widgetWithText(FilledButton, label);
    await tester.ensureVisible(button);
    await tester.pumpAndSettle();
    await tester.tap(button);
    await tester.pumpAndSettle();
  }

  /// Confirms the «¿Eliminar…?» dialog. Pumps frames instead of settling:
  /// the delete button spins while the password sheet is open.
  Future<void> confirmDelete(WidgetTester tester) async {
    await tapButton(tester, 'Eliminar billetera');
    expect(find.textContaining('¿Eliminar «'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Eliminar'));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  /// Taps a button inside the password sheet and lets the flow finish.
  Future<void> tapInSheet(WidgetTester tester, String label) async {
    await tester.tap(find.widgetWithText(FilledButton, label).last);
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  group('detail (COU-195, COU-211)', () {
    testWidgets('loads fresh data: totals, month and opening balance', (tester) async {
      final initial = walletFixture(id: 4, name: 'Ahorros', balance: 10);
      when(() => wallets.getById(4)).thenAnswer((_) async => walletFixture(id: 4, name: 'Ahorros', balance: 25));
      await pumpDetail(tester, initial);
      expect(find.text(r'$25,00'), findsOneWidget);
      expect(find.text('Saldo inicial'), findsOneWidget);
      expect(find.text('Ingresos totales'), findsOneWidget);
      expect(find.text('Gastos del mes'), findsWidgets);
      expect(find.text('Saldo proyectado a fin de mes'), findsNothing);
      expect(find.text('Presupuestos'), findsOneWidget);
      expect(find.text('Movimientos'), findsOneWidget);
    });

    testWidgets('projection row only with the plan feature', (tester) async {
      final wallet = walletFixture(id: 4, projectedBalance: 1300);
      when(() => wallets.getById(4)).thenAnswer((_) async => wallet);
      await pumpDetail(tester, wallet);
      expect(find.text('Saldo proyectado a fin de mes'), findsNWidgets(2), reason: 'card and figures');
    });

    testWidgets('owner sees edit and delete; edit opens the form and reloads on return', (tester) async {
      final wallet = walletFixture(id: 4);
      when(() => wallets.getById(4)).thenAnswer((_) async => wallet);
      await pumpDetail(tester, wallet);
      await tester.tap(find.byTooltip('Acciones'));
      await tester.pumpAndSettle();
      expect(find.text('Editar'), findsOneWidget);
      expect(find.text('Eliminar'), findsOneWidget);
      expect(find.text('Miembros'), findsOneWidget);

      await tester.tap(find.text('Editar'));
      await tester.pumpAndSettle();
      expect(find.text('EDIT FORM'), findsOneWidget);
      tester.state<NavigatorState>(find.byType(Navigator).last).pop();
      await tester.pumpAndSettle();
      verify(() => wallets.getById(4)).called(2);
    });

    testWidgets('shared wallet: owner actions are hidden', (tester) async {
      final wallet = walletFixture(id: 4, isOwner: false, ownerName: 'Luis Andrade', memberCount: 1);
      when(() => wallets.getById(4)).thenAnswer((_) async => wallet);
      await pumpDetail(tester, wallet);
      expect(find.text('Compartida contigo por Luis Andrade'), findsOneWidget);
      expect(find.text('Eliminar billetera'), findsNothing);
      expect(find.text('Editar billetera'), findsNothing);
      await tester.tap(find.byTooltip('Acciones'));
      await tester.pumpAndSettle();
      expect(find.text('Editar'), findsNothing);
      expect(find.text('Eliminar'), findsNothing);
      expect(find.text('Miembros'), findsOneWidget);
    });

    testWidgets('missing, someone else\'s or deleted: back home with «Billetera no encontrada»', (tester) async {
      when(() => wallets.getById(9)).thenAnswer((_) async => throw _notFound);
      await pumpDetail(tester, walletFixture(id: 9));
      expect(find.text('HOME'), findsOneWidget);
      expect(find.text('Billetera no encontrada'), findsOneWidget);
    });

    testWidgets('a network error keeps the card and explains in a snackbar', (tester) async {
      when(() => wallets.getById(4)).thenAnswer((_) async => throw _network);
      await pumpDetail(tester, walletFixture(id: 4, name: 'Ahorros'));
      expect(find.text('Saldo inicial'), findsOneWidget);
      expect(find.text('No hay conexión.'), findsOneWidget);
    });
  });

  group('delete with reauthentication (COU-212, COU-216)', () {
    final wallet = walletFixture(id: 4, name: 'Hogar');

    setUp(() => when(() => wallets.getById(4)).thenAnswer((_) async => wallet));

    /// Behaves like [ApiClient.run]: on reauth_required asks [onReauth] and retries once.
    void deleteNeedsReauth({required List<int> calls}) {
      when(() => wallets.delete(4, onReauth: any(named: 'onReauth'))).thenAnswer((invocation) async {
        calls.add(4);
        final prompt = invocation.namedArguments[#onReauth] as ReauthPrompt?;
        if (prompt == null || !await prompt()) throw _reauthRequired;
        calls.add(4);
      });
    }

    testWidgets('within the safe-mode window: deletes at once and returns home', (tester) async {
      when(() => wallets.delete(4, onReauth: any(named: 'onReauth'))).thenAnswer((_) async {});
      await pumpDetail(tester, wallet);
      await confirmDelete(tester);
      verify(() => wallets.delete(4, onReauth: any(named: 'onReauth'))).called(1);
      expect(find.text('Confirma que eres tú'), findsNothing);
      expect(find.text('HOME'), findsOneWidget);
      expect(find.text('Eliminamos «Hogar»'), findsOneWidget);
    });

    testWidgets('reauth_required: asks for the password, then retries and deletes', (tester) async {
      final calls = <int>[];
      deleteNeedsReauth(calls: calls);
      when(() => auth.reauthenticate('Quito2026')).thenAnswer((_) async => DateTime(2026, 10, 3, 12, 5));
      await pumpDetail(tester, wallet);
      await confirmDelete(tester);
      expect(find.text('Confirma que eres tú'), findsOneWidget);
      expect(find.textContaining('Para eliminar «Hogar» escribe tu contraseña'), findsOneWidget);

      await tester.enterText(find.byType(EditableText), 'Quito2026');
      await tapInSheet(tester, 'Eliminar billetera');
      verify(() => auth.reauthenticate('Quito2026')).called(1);
      expect(calls, [4, 4], reason: 'first attempt plus the retry');
      expect(find.text('HOME'), findsOneWidget);
      expect(find.text('Eliminamos «Hogar»'), findsOneWidget);
    });

    testWidgets('cancelling the password sheet deletes nothing and shows no error', (tester) async {
      final calls = <int>[];
      deleteNeedsReauth(calls: calls);
      await pumpDetail(tester, wallet);
      await confirmDelete(tester);
      await tapInSheet(tester, 'Cancelar');
      await tester.pumpAndSettle();
      expect(calls, [4], reason: 'no retry');
      expect(find.text('Saldo inicial'), findsOneWidget, reason: 'still on the detail');
      expect(find.byType(SnackBar), findsNothing);
      verifyNever(() => auth.reauthenticate(any()));
    });

    testWidgets('cancelling the confirmation dialog does not call the API', (tester) async {
      await pumpDetail(tester, wallet);
      await tapButton(tester, 'Eliminar billetera');
      await tester.tap(find.widgetWithText(FilledButton, 'Cancelar'));
      await tester.pumpAndSettle();
      verifyNever(() => wallets.delete(any(), onReauth: any(named: 'onReauth')));
    });

    testWidgets('404 on delete: treated as already deleted', (tester) async {
      when(() => wallets.delete(4, onReauth: any(named: 'onReauth'))).thenThrow(_notFound);
      await pumpDetail(tester, wallet);
      await confirmDelete(tester);
      expect(find.text('HOME'), findsOneWidget);
      expect(find.text('Eliminamos «Hogar»'), findsOneWidget);
    });

    testWidgets('other errors stay on the detail with the message', (tester) async {
      when(() => wallets.delete(4, onReauth: any(named: 'onReauth'))).thenThrow(_network);
      await pumpDetail(tester, wallet);
      await confirmDelete(tester);
      expect(find.text('Saldo inicial'), findsOneWidget);
      expect(find.text('No hay conexión.'), findsOneWidget);
    });
  });
}
