import 'package:bloc_test/bloc_test.dart';
import 'package:countit_app/app/errors/app_failure.dart';
import 'package:countit_app/app/router/app_router.dart';
import 'package:countit_app/app/session/session_cubit.dart';
import 'package:countit_app/app/session/session_state.dart';
import 'package:countit_app/data/dtos/bank.dart';
import 'package:countit_app/data/dtos/profile.dart';
import 'package:countit_app/presentation/admin/cubit/admin_banks_cubit.dart';
import 'package:countit_app/presentation/admin/cubit/admin_failures.dart';
import 'package:countit_app/presentation/admin/cubit/bank_form_cubit.dart';
import 'package:countit_app/presentation/admin/view/admin_banks_page.dart';
import 'package:countit_app/presentation/admin/view/admin_page.dart';
import 'package:countit_app/presentation/admin/view/bank_form_page.dart';
import 'package:countit_app/presentation/wallets/view/widgets/wallet_card.dart';
import 'package:countit_app/presentation/wallets/view/widgets/wallet_colors.dart';
import 'package:countit_app/shared/state/load_state.dart';
import 'package:countit_app/shared/utils/dates.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';

import '../../helpers/admin_fixtures.dart';
import '../../helpers/mocks.dart';
import '../../helpers/pump_app.dart';

const _pichincha = Bank(bankId: 1, name: 'Banco Pichincha', countryCode: 'EC', color: 0xFFFFDD00);
const _produbanco = Bank(bankId: 2, name: 'Produbanco', countryCode: 'EC', color: 0xFF00843D);
const _austro = Bank(bankId: 7, name: 'Banco del Austro', countryCode: 'EC', isActive: false);
const _forbidden = AppFailure(kind: FailureKind.forbidden, message: 'Acceso denegado', key: 'forbidden', status: 403);

Future<void> _save(WidgetTester tester) async {
  // The footer sliver is built lazily: scroll until it exists.
  await tester.scrollUntilVisible(
    find.byKey(const ValueKey('bank-save')),
    200,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const ValueKey('bank-save')));
  await tester.pumpAndSettle();
}

/// The switch's label (wrapped around the switch, merged into its node).
Finder _switchLabel(String label) =>
    find.byWidgetPredicate((widget) => widget is Semantics && widget.properties.label == label);

void main() {
  late MockAuthRepository auth;
  late MockAdminRepository admin;

  setUpAll(() async {
    await Dates.init();
    registerFallbackValue(const BankInput(name: '', countryCode: ''));
  });

  setUp(() {
    final view = TestWidgetsFlutterBinding.instance.platformDispatcher.views.first
      ..physicalSize = const Size(1200, 2800)
      ..devicePixelRatio = 3;
    addTearDown(view.reset);
    auth = MockAuthRepository();
    admin = MockAdminRepository();
    when(() => auth.sessionChanges).thenAnswer((_) => const Stream.empty());
  });

  group('AdminBanksCubit (COU-205, COU-207)', () {
    blocTest<AdminBanksCubit, AdminBanksState>(
      'loads every bank and filters locally',
      setUp: () => when(admin.listBanks).thenAnswer((_) async => [_austro, _pichincha, _produbanco]),
      build: () => AdminBanksCubit(admin),
      act: (cubit) async {
        await cubit.load();
        cubit.search(' pich ');
      },
      verify: (cubit) {
        expect(cubit.state.visible, [_pichincha]);
        verify(admin.listBanks).called(1);
      },
    );

    blocTest<AdminBanksCubit, AdminBanksState>(
      'deactivating updates the row in place; a 403 is neutral and keeps it',
      setUp: () {
        when(() => admin.setBankActive(1, active: false)).thenAnswer(
          (_) async =>
              const Bank(bankId: 1, name: 'Banco Pichincha', countryCode: 'EC', color: 0xFFFFDD00, isActive: false),
        );
        when(() => admin.setBankActive(2, active: false)).thenThrow(_forbidden);
      },
      build: () => AdminBanksCubit(admin),
      seed: () => const AdminBanksState(banks: LoadState.success([_pichincha, _produbanco])),
      act: (cubit) async {
        expect(await cubit.setActive(_pichincha, active: false), isTrue);
        expect(await cubit.setActive(_produbanco, active: false), isFalse);
        expect(await cubit.setActive(_austro, active: false), isFalse, reason: 'already inactive: no request');
      },
      verify: (cubit) {
        expect(cubit.state.banks.data!.first.isActive, isFalse);
        expect(cubit.state.banks.data!.last.isActive, isTrue);
        expect(cubit.state.failure!.message, adminForbiddenMessage);
        expect(cubit.state.toggling, isEmpty);
      },
    );

    blocTest<AdminBanksCubit, AdminBanksState>(
      'a saved bank is inserted sorted by name',
      build: () => AdminBanksCubit(admin),
      seed: () => const AdminBanksState(banks: LoadState.success([_pichincha, _produbanco])),
      act: (cubit) => cubit.upsert(const Bank(bankId: 20, name: 'Banco Amazonas', countryCode: 'EC')),
      verify: (cubit) => expect(cubit.state.banks.data!.map((b) => b.bankId), [20, 1, 2]),
    );
  });

  group('BankFormCubit validation (COU-206)', () {
    test('mirrors the backend rules', () {
      expect(BankFormCubit.validateName(''), 'Este campo no puede quedar vacío');
      expect(BankFormCubit.validateName('x' * 101), contains('100'));
      expect(BankFormCubit.validateName('Banco Nuevo'), isNull);
      expect(BankFormCubit.validateCountry('ec'), isNotNull);
      expect(BankFormCubit.validateCountry('ECU'), isNotNull);
      expect(BankFormCubit.validateCountry('EC'), isNull);
    });
  });

  group('banks screens', () {
    SessionCubit sessionAs(UserRole role) {
      final session = SessionCubit(auth: auth, profiles: MockProfileRepository())
        ..emit(SessionState.authenticated(adminProfile(role)));
      addTearDown(session.close);
      return session;
    }

    Future<void> pumpBanks(WidgetTester tester, {UserRole role = UserRole.admin}) async {
      await tester.pumpApp(
        const SizedBox.shrink(),
        auth: auth,
        admin: admin,
        session: sessionAs(role),
        router: GoRouter(
          initialLocation: AppRoutes.admin,
          routes: [
            GoRoute(
              path: AppRoutes.admin,
              builder: (context, state) => const AdminPage(),
              routes: [
                GoRoute(
                  path: 'banks',
                  builder: (context, state) => const AdminBanksPage(),
                  routes: [
                    GoRoute(path: 'new', builder: (context, state) => const BankFormPage()),
                    GoRoute(
                      path: ':bankId/edit',
                      builder: (context, state) => BankFormPage(initial: state.extra! as Bank),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('admin-banks')));
      await tester.pumpAndSettle();
    }

    testWidgets('list: inactive banks too, with colour code and switch', (tester) async {
      when(admin.listBanks).thenAnswer((_) async => [_austro, _pichincha]);
      await pumpBanks(tester);
      expect(find.text('Banco del Austro'), findsOneWidget);
      expect(find.text('EC · Sin color · Inactivo'), findsOneWidget);
      expect(find.text('EC · #FFDD00'), findsOneWidget);
      expect(_switchLabel('Banco del Austro inactivo'), findsOneWidget);
    });

    testWidgets('deactivating asks first; reactivating does not', (tester) async {
      when(admin.listBanks).thenAnswer((_) async => [_austro, _pichincha]);
      when(() => admin.setBankActive(1, active: false)).thenAnswer(
        (_) async =>
            const Bank(bankId: 1, name: 'Banco Pichincha', countryCode: 'EC', color: 0xFFFFDD00, isActive: false),
      );
      when(() => admin.setBankActive(7, active: true))
          .thenAnswer((_) async => const Bank(bankId: 7, name: 'Banco del Austro', countryCode: 'EC'));
      await pumpBanks(tester);
      await tester.tap(find.descendant(of: find.byKey(const ValueKey('bank-1')), matching: find.byType(Switch)));
      await tester.pumpAndSettle();
      expect(find.text('¿Desactivar «Banco Pichincha»?'), findsOneWidget);
      expect(find.textContaining('Las billeteras que ya lo usan lo conservan'), findsOneWidget);
      await tester.tap(find.descendant(of: find.byType(AlertDialog), matching: find.text('Desactivar')));
      await tester.pumpAndSettle();
      expect(find.text('«Banco Pichincha» quedó desactivado'), findsOneWidget);

      await tester.tap(find.descendant(of: find.byKey(const ValueKey('bank-7')), matching: find.byType(Switch)));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      verify(() => admin.setBankActive(7, active: true)).called(1);
      expect(find.text('EC · Sin color'), findsOneWidget);
    });

    testWidgets('create: local validation, colour swatch with preview, then the new row', (tester) async {
      when(admin.listBanks).thenAnswer((_) async => [_pichincha]);
      when(
        () => admin.createBank(any()),
      ).thenAnswer((_) async => const Bank(bankId: 20, name: 'Banco Amazonas', countryCode: 'EC', color: 0xFF00843D));
      await pumpBanks(tester);
      await tester.tap(find.byKey(const ValueKey('bank-new')));
      await tester.pumpAndSettle();
      expect(find.byType(BankFormPage), findsOneWidget);

      await _save(tester);
      expect(find.text('Este campo no puede quedar vacío'), findsOneWidget);
      verifyNever(() => admin.createBank(any()));

      await tester.enterText(find.byKey(const ValueKey('bank-name')), 'Banco Amazonas');
      await tester.tap(find.bySemanticsLabel('Color #00843D'));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(TextField, '#00843D'), findsOneWidget);
      await _save(tester);
      verify(() => admin.createBank(const BankInput(name: 'Banco Amazonas', countryCode: 'EC', color: 0xFF00843D)))
          .called(1);
      expect(find.byType(AdminBanksPage), findsOneWidget);
      expect(find.text('Banco Amazonas'), findsOneWidget);
    });

    testWidgets('edit: an invalid hex is refused; «Sin color» removes it; 409 next to the name', (tester) async {
      when(admin.listBanks).thenAnswer((_) async => [_pichincha]);
      when(() => admin.updateBank(1, any())).thenThrow(
        const AppFailure(
          kind: FailureKind.conflict,
          message: 'Ya existe un banco con ese nombre',
          key: 'bank_name_taken',
          status: 409,
        ),
      );
      await pumpBanks(tester);
      await tester.tap(find.text('Banco Pichincha'));
      await tester.pumpAndSettle();
      expect(find.text('Editar banco'), findsOneWidget);
      expect(find.widgetWithText(TextField, '#FFDD00'), findsOneWidget);

      await tester.enterText(find.byKey(const ValueKey('bank-color-hex')), '#12');
      await _save(tester);
      expect(find.text('Color no válido: usa el formato #RRGGBB'), findsOneWidget);
      verifyNever(() => admin.updateBank(any(), any()));

      await tester.tap(find.bySemanticsLabel('Sin color'));
      await tester.pumpAndSettle();
      await _save(tester);
      verify(() => admin.updateBank(1, const BankInput(name: 'Banco Pichincha', countryCode: 'EC'))).called(1);
      expect(find.text('Ya existe un banco con ese nombre'), findsOneWidget);
    });

    testWidgets('the colour is an accent: the preview card shows it muted', (tester) async {
      when(admin.listBanks).thenAnswer((_) async => const []);
      await pumpBanks(tester);
      await tester.tap(find.byKey(const ValueKey('bank-new')));
      await tester.pumpAndSettle();
      expect(find.text('COLOR DE ACENTO'), findsOneWidget);
      expect(find.textContaining('atenuado sobre la paleta de Count It!'), findsOneWidget);
      await tester.enterText(find.byKey(const ValueKey('bank-color-hex')), '#FFDD00');
      await tester.pumpAndSettle();
      final card = tester.widget<Material>(
        find.descendant(of: find.byType(WalletCard), matching: find.byType(Material)).first,
      );
      expect(card.color, mutedBankAccent(const Color(0xFFFFDD00)));
    });
  });
}
