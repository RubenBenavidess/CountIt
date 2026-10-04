import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:countit_app/app/errors/app_failure.dart';
import 'package:countit_app/app/router/app_router.dart';
import 'package:countit_app/app/session/session_cubit.dart';
import 'package:countit_app/data/dtos/bank.dart';
import 'package:countit_app/data/dtos/profile.dart';
import 'package:countit_app/data/dtos/wallet.dart';
import 'package:countit_app/presentation/wallets/cubit/bank_picker_cubit.dart';
import 'package:countit_app/presentation/wallets/view/wallet_form_page.dart';
import 'package:countit_app/presentation/wallets/view/widgets/wallet_card.dart';
import 'package:countit_app/shared/state/load_state.dart';
import 'package:countit_app/shared/utils/dates.dart';
import 'package:countit_app/shared/widgets/app_banner.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';

import '../../helpers/mocks.dart';
import '../../helpers/pump_app.dart';
import '../../helpers/wallet_fixtures.dart';

const _regular = UserPlan(planId: 1, name: 'Regular', limits: {'max_wallets': 3});

const _profile = Profile(
  userId: 'u1',
  username: 'mariaq',
  email: 'maria@correo.ec',
  firstName: 'María',
  role: UserRole.user,
  timezone: 'America/Guayaquil',
  plan: _regular,
);

const _nameTaken = AppFailure(
  kind: FailureKind.conflict,
  message: 'Ya tienes una billetera con ese nombre',
  key: 'wallet_name_taken',
  status: 409,
);
const _limit = AppFailure(
  kind: FailureKind.conflict,
  message: 'Alcanzaste el límite de billeteras de tu plan',
  key: 'wallet_limit_exceeded',
  status: 409,
);
const _maxLength = AppFailure(
  kind: FailureKind.validation,
  message: 'Máximo de caracteres alcanzado (255) en la descripción',
  key: 'max_length',
  status: 400,
);
const _notFound = AppFailure(
  kind: FailureKind.notFound,
  message: 'Billetera no encontrada',
  key: 'wallet_not_found',
  status: 404,
);

void main() {
  late MockWalletRepository wallets;
  late MockBankRepository banks;
  late MockAuthRepository auth;
  late MockProfileRepository profiles;

  setUpAll(() async {
    await Dates.init();
    registerFallbackValue(const WalletInput(name: ''));
  });

  setUp(() {
    wallets = MockWalletRepository();
    banks = MockBankRepository();
    auth = MockAuthRepository();
    profiles = MockProfileRepository();
    when(() => auth.sessionChanges).thenAnswer((_) => const Stream.empty());
    when(() => auth.hasSession).thenReturn(true);
    when(() => profiles.fetchMyProfile()).thenAnswer((_) async => _profile);
    when(() => banks.list(search: any(named: 'search'))).thenAnswer((_) async => banksFixture);
  });

  /// Home with a button that opens the form; [result] gets what the form pops.
  Future<List<Object?>> pumpForm(WidgetTester tester, {Wallet? initial}) async {
    tester.view.physicalSize = const Size(420, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final results = <Object?>[];
    final session = SessionCubit(auth: auth, profiles: profiles);
    addTearDown(session.close);
    await session.restore();
    final router = GoRouter(
      initialLocation: AppRoutes.home,
      routes: [
        GoRoute(
          path: AppRoutes.home,
          builder: (context, state) => Scaffold(
            body: TextButton(
              onPressed: () async => results.add(await context.push<Object?>('/form')),
              child: const Text('HOME'),
            ),
          ),
        ),
        GoRoute(
          path: '/form',
          builder: (context, state) => WalletFormPage(initial: initial),
        ),
      ],
    );
    await tester.pumpApp(
      const SizedBox(),
      auth: auth,
      wallets: wallets,
      banks: banks,
      session: session,
      router: router,
    );
    await tester.tap(find.text('HOME'));
    await tester.pumpAndSettle();
    return results;
  }

  Finder field(String label) => find.descendant(
    of: find.ancestor(of: find.text(label), matching: find.byType(Column)).first,
    matching: find.byType(EditableText),
  );

  /// Scrolls the form to [label]'s button and taps it.
  Future<void> tapButton(WidgetTester tester, String label) async {
    final button = find.widgetWithText(FilledButton, label);
    await tester.ensureVisible(button);
    await tester.pumpAndSettle();
    await tester.tap(button);
    await tester.pumpAndSettle();
  }

  Future<void> chooseBank(WidgetTester tester, String name) async {
    await tester.tap(find.byKey(const ValueKey('wallet-bank-field')));
    await tester.pumpAndSettle();
    await tester.tap(find.descendant(of: find.byType(ListTile), matching: find.text(name)));
    await tester.pumpAndSettle();
  }

  group('create (COU-192, COU-193)', () {
    testWidgets('name is required: nothing is sent', (tester) async {
      await pumpForm(tester);
      await tapButton(tester, 'Crear billetera');
      expect(find.text('Este campo no puede quedar vacío'), findsOneWidget);
      verifyNever(() => wallets.create(any()));
    });

    testWidgets('the preview follows the chosen bank and type', (tester) async {
      await pumpForm(tester);
      expect(find.descendant(of: find.byType(WalletCard), matching: find.text('Nueva billetera')), findsOneWidget);
      expect(find.descendant(of: find.byType(WalletCard), matching: find.text('Sin banco')), findsOneWidget);

      await tester.enterText(field('Nombre'), 'Casa');
      await tester.tap(find.byKey(const ValueKey('wallet-type-checking')));
      await chooseBank(tester, 'Banco Guayaquil');

      final card = find.byType(WalletCard);
      expect(find.descendant(of: card, matching: find.text('Casa')), findsOneWidget);
      expect(find.descendant(of: card, matching: find.text('Banco Guayaquil')), findsOneWidget);
      expect(find.descendant(of: card, matching: find.text('Cuenta corriente')), findsOneWidget);
      expect(tester.widget<WalletCard>(card).wallet.bankColor, 0xFFE6007E);
    });

    testWidgets('success sends every field, pops with true and confirms', (tester) async {
      when(() => wallets.create(any())).thenAnswer((_) async => 12);
      final results = await pumpForm(tester);
      await tester.enterText(field('Nombre'), '  Casa ');
      await tester.tap(find.byKey(const ValueKey('wallet-type-savings')));
      await chooseBank(tester, 'Banco Pichincha');
      await tester.enterText(field('Saldo inicial'), '150,5');
      await tester.enterText(field('Descripción (opcional)'), 'Gastos del hogar');
      await tapButton(tester, 'Crear billetera');

      verify(
        () => wallets.create(
          const WalletInput(
            name: 'Casa',
            type: WalletType.savings,
            bankId: 3,
            description: 'Gastos del hogar',
            initialBalanceCents: 15050,
          ),
        ),
      ).called(1);
      expect(results, [true]);
      expect(find.text('Creamos tu billetera «Casa»'), findsOneWidget);
    });

    testWidgets('an empty opening balance is 0', (tester) async {
      when(() => wallets.create(any())).thenAnswer((_) async => 1);
      await pumpForm(tester);
      await tester.enterText(field('Nombre'), 'Efectivo');
      await tapButton(tester, 'Crear billetera');
      verify(() => wallets.create(const WalletInput(name: 'Efectivo'))).called(1);
    });

    testWidgets('409 wallet_name_taken: shown on the name field', (tester) async {
      when(() => wallets.create(any())).thenThrow(_nameTaken);
      await pumpForm(tester);
      await tester.enterText(field('Nombre'), 'Ahorros');
      await tapButton(tester, 'Crear billetera');
      final name = tester.widget<TextField>(
        find.descendant(
          of: find.ancestor(of: find.text('Nombre'), matching: find.byType(Column)).first,
          matching: find.byType(TextField),
        ),
      );
      expect(name.decoration?.errorText, 'Ya tienes una billetera con ese nombre');
      expect(find.byType(AppBanner), findsNothing);
    });

    testWidgets('409 wallet_limit_exceeded: opens the plan upsell', (tester) async {
      when(() => wallets.create(any())).thenThrow(_limit);
      await pumpForm(tester);
      await tester.enterText(field('Nombre'), 'Cuarta');
      await tapButton(tester, 'Crear billetera');
      expect(find.text('Alcanzaste el límite de tu plan'), findsOneWidget);
      expect(find.text('Alcanzaste el límite de billeteras de tu plan'), findsOneWidget);
      expect(find.text('Billeteras'), findsOneWidget);
      expect(find.text('3'), findsOneWidget);
      await tester.tap(find.text('Entendido'));
      await tester.pumpAndSettle();
      expect(find.text('Crear billetera'), findsOneWidget, reason: 'the form stays open');
    });

    testWidgets('400 max_length: the backend message in the banner', (tester) async {
      when(() => wallets.create(any())).thenThrow(_maxLength);
      await pumpForm(tester);
      await tester.enterText(field('Nombre'), 'Casa');
      await tapButton(tester, 'Crear billetera');
      expect(find.widgetWithText(AppBanner, 'Máximo de caracteres alcanzado (255) en la descripción'), findsOneWidget);
    });

    testWidgets('no double submit while saving', (tester) async {
      final pending = Completer<int>();
      when(() => wallets.create(any())).thenAnswer((_) => pending.future);
      await pumpForm(tester);
      await tester.enterText(field('Nombre'), 'Casa');
      final create = find.widgetWithText(FilledButton, 'Crear billetera');
      await tester.ensureVisible(create);
      await tester.pumpAndSettle();
      await tester.tap(create);
      await tester.pump();
      await tester.tap(find.byType(FilledButton).last, warnIfMissed: false);
      await tester.pump();
      verify(() => wallets.create(any())).called(1);
      pending.complete(1);
      await tester.pumpAndSettle();
    });
  });

  group('edit (COU-194)', () {
    final existing = walletFixture(
      id: 5,
      name: 'Ahorros',
      type: WalletType.savings,
      bankId: 3,
      bankName: 'Banco Pichincha',
      bankColor: 0xFFF2C500,
      description: 'Fondo de emergencia',
      initialBalance: 1000,
    );

    testWidgets('prefilled; changing only the name keeps bank, type and description', (tester) async {
      when(() => wallets.update(any(), any())).thenAnswer((_) async {});
      final results = await pumpForm(tester, initial: existing);
      expect(find.text('Editar billetera'), findsOneWidget);
      expect(find.text('Fondo de emergencia'), findsOneWidget);
      expect(find.text('1000,00'), findsOneWidget);

      await tester.enterText(field('Nombre'), 'Ahorros 2026');
      await tapButton(tester, 'Guardar cambios');

      verify(
        () => wallets.update(
          5,
          const WalletInput(
            name: 'Ahorros 2026',
            type: WalletType.savings,
            bankId: 3,
            description: 'Fondo de emergencia',
            initialBalanceCents: 100000,
          ),
        ),
      ).called(1);
      expect(results, [true]);
      expect(find.text('Guardamos los cambios'), findsOneWidget);
    });

    testWidgets('«Sin banco» clears the bank explicitly', (tester) async {
      when(() => wallets.update(any(), any())).thenAnswer((_) async {});
      await pumpForm(tester, initial: existing);
      await chooseBank(tester, 'Sin banco');
      await tapButton(tester, 'Guardar cambios');
      final input = verify(() => wallets.update(5, captureAny())).captured.single as WalletInput;
      expect(input.bankId, isNull);
      expect(input.toParams().containsKey('p_bank_id'), isTrue);
    });

    testWidgets('409 wallet_name_taken on edit is shown on the name field', (tester) async {
      when(() => wallets.update(any(), any())).thenThrow(_nameTaken);
      await pumpForm(tester, initial: existing);
      await tester.enterText(field('Nombre'), 'Casa');
      await tapButton(tester, 'Guardar cambios');
      expect(find.text('Ya tienes una billetera con ese nombre'), findsOneWidget);
    });

    testWidgets('404: back home with «Billetera no encontrada»', (tester) async {
      when(() => wallets.update(any(), any())).thenThrow(_notFound);
      await pumpForm(tester, initial: existing);
      await tester.enterText(field('Nombre'), 'Otra');
      await tapButton(tester, 'Guardar cambios');
      expect(find.text('HOME'), findsOneWidget);
      expect(find.text('Billetera no encontrada'), findsOneWidget);
    });

    testWidgets('leaving with unsaved changes asks first', (tester) async {
      final results = await pumpForm(tester, initial: existing);
      await tester.enterText(field('Nombre'), 'Otra');
      await tester.pumpAndSettle();
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('¿Descartar los cambios?'), findsOneWidget);

      await tester.tap(find.text('Descartar'));
      await tester.pumpAndSettle();
      expect(find.text('HOME'), findsOneWidget);
      expect(results, [null]);
      verifyNever(() => wallets.update(any(), any()));
    });

    testWidgets('without changes «Guardar cambios» is disabled and back leaves at once', (tester) async {
      await pumpForm(tester, initial: existing);
      final button = tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Guardar cambios'));
      expect(button.onPressed, isNull);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('HOME'), findsOneWidget);
    });
  });

  group('BankPickerCubit (COU-190)', () {
    blocTest<BankPickerCubit, LoadState<List<Bank>>>(
      'debounces the search and asks only for the last term',
      build: () => BankPickerCubit(banks, debounce: const Duration(milliseconds: 20)),
      act: (cubit) async {
        cubit
          ..search('p')
          ..search('pi')
          ..search('pich');
        await Future<void>.delayed(const Duration(milliseconds: 60));
      },
      verify: (_) {
        verify(() => banks.list(search: 'pich')).called(1);
        verifyNever(() => banks.list(search: 'p'));
        verifyNever(() => banks.list(search: 'pi'));
      },
    );

    blocTest<BankPickerCubit, LoadState<List<Bank>>>(
      'a failure keeps the previous banks for retry',
      setUp: () =>
          when(() => banks.list(search: any(named: 'search')))
              .thenThrow(const AppFailure(kind: FailureKind.network, message: 'No hay conexión.')),
      build: () => BankPickerCubit(banks),
      seed: () => const LoadState.success(banksFixture),
      act: (cubit) => cubit.load(),
      expect: () => [
        const LoadState<List<Bank>>.loading(previous: banksFixture),
        const LoadState<List<Bank>>.failure(
          AppFailure(kind: FailureKind.network, message: 'No hay conexión.'),
          previous: banksFixture,
        ),
      ],
    );

    testWidgets('the sheet lists the catalogue with «Sin banco» and filters while typing', (tester) async {
      when(() => banks.list(search: 'jep')).thenAnswer((_) async => [banksFixture.last]);
      await pumpForm(tester);
      await tester.tap(find.byKey(const ValueKey('wallet-bank-field')));
      await tester.pumpAndSettle();
      expect(find.text('Elige un banco'), findsOneWidget);
      expect(find.descendant(of: find.byType(ListTile), matching: find.text('Sin banco')), findsOneWidget);
      expect(find.text('Banco Guayaquil'), findsOneWidget);

      await tester.enterText(field('Buscar'), 'jep');
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
      expect(find.text('Banco Guayaquil'), findsNothing);
      expect(find.text('Cooperativa JEP'), findsOneWidget);
    });
  });
}
