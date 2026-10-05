import 'dart:math' as math;

import 'package:countit_app/app/theme/tokens.dart';
import 'package:countit_app/data/dtos/wallet.dart';
import 'package:countit_app/presentation/wallets/view/widgets/wallet_card.dart';
import 'package:countit_app/presentation/wallets/view/widgets/wallet_colors.dart';
import 'package:countit_app/presentation/wallets/view/widgets/wallet_fragments_painter.dart';
import 'package:countit_app/shared/utils/money.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/pump_app.dart';
import '../../helpers/wallet_fixtures.dart';

/// Brand colours of the seeded catalogue (backend migration COU-13).
const _bankColors = [
  0xFFFFDD00, 0xFF00843D, 0xFFD6006E, 0xFF0072BC, 0xFF00387B, 0xFFE30613, 0xFFC8102E, //
  0xFFF7941D, 0xFFD51F2C, 0xFF004B87, 0xFF007A3D, 0xFF00953A, 0xFF1F4E9C, 0xFFF39200,
];

double _contrast(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
}

/// Goldens use the real Manrope files so the screenshots look like the app.
Future<void> _loadManrope() async {
  final loader = FontLoader(AppTypography.family);
  for (final weight in ['Regular', 'Medium', 'SemiBold', 'Bold', 'ExtraBold']) {
    loader.addFont(rootBundle.load('assets/fonts/Manrope-$weight.ttf'));
  }
  await loader.load();
}

void main() {
  setUpAll(_loadManrope);

  group('WalletColors (COU-170)', () {
    test('text keeps at least 4.5:1 on every catalogue colour and on the default', () {
      for (final value in [..._bankColors, null]) {
        final colors = WalletColors.of(value);
        expect(
          _contrast(colors.foreground, colors.base),
          greaterThanOrEqualTo(4.5),
          reason: value?.toRadixString(16) ?? 'default',
        );
      }
    });

    test('light colours get dark text and dark colours white text', () {
      expect(WalletColors.of(0xFFFFDD00).foreground, AppColors.ink);
      expect(WalletColors.of(0xFF00387B).foreground, AppColors.white);
    });

    test('no bank colour uses the default wallet colour; legible brand colours are kept', () {
      expect(WalletColors.of(null).base, AppColors.defaultWallet);
      expect(WalletColors.of(0xFFD6006E).base, const Color(0xFFD6006E));
      // BanEcuador's green reaches 4.5:1 with neither text colour: darkened a bit.
      final green = WalletColors.of(0xFF00953A);
      expect(green.base, isNot(const Color(0xFF00953A)));
      expect(HSLColor.fromColor(green.base).hue, closeTo(HSLColor.fromColor(const Color(0xFF00953A)).hue, 1));
    });

    test('four tones of the same hue, lightest first', () {
      final colors = WalletColors.of(0xFF0072BC);
      final hue = HSLColor.fromColor(colors.base).hue;
      final lightness = <double>[for (final tone in colors.tones) HSLColor.fromColor(tone).lightness];
      expect(colors.tones, hasLength(4));
      for (final tone in colors.tones) {
        expect(HSLColor.fromColor(tone).hue, closeTo(hue, 1));
      }
      for (var i = 1; i < lightness.length; i++) {
        expect(lightness[i], lessThan(lightness[i - 1]));
      }
    });

    test('the painter only repaints when the colours change', () {
      final painter = WalletFragmentsPainter(WalletColors.of(0xFF0072BC));
      expect(painter.shouldRepaint(WalletFragmentsPainter(WalletColors.of(0xFF0072BC))), isFalse);
      expect(painter.shouldRepaint(WalletFragmentsPainter(WalletColors.of(null))), isTrue);
    });
  });

  group('WalletCard content (COU-171, COU-174)', () {
    /// Settled: the balance counts up with a short animation.
    Future<void> pumpCard(WidgetTester tester, Wallet wallet, {double width = 360}) async {
      await tester.pumpApp(
        Center(
          child: SizedBox(
            width: width,
            child: WalletCard(wallet: wallet),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('name, bank, type and balance', (tester) async {
      await pumpCard(tester, walletFixture(name: 'Ahorros', bankName: 'Banco Pichincha', balance: 1250.5));
      expect(find.text('Ahorros'), findsNWidgets(2), reason: 'name and the savings type');
      expect(find.text('Banco Pichincha'), findsOneWidget);
      expect(find.text(r'$1.250,50'), findsOneWidget);
      expect(find.text('Compartida'), findsNothing);
    });

    testWidgets('without bank: «Sin banco»; without type: «Sin tipo»', (tester) async {
      await pumpCard(tester, walletFixture(bankName: null, bankColor: null, type: null));
      expect(find.text('Sin banco'), findsOneWidget);
      expect(find.text('Sin tipo'), findsOneWidget);
    });

    testWidgets('other plans: incomes and expenses of the month, never «null»', (tester) async {
      await pumpCard(tester, walletFixture(monthIncome: 300, monthExpenses: 120.25));
      expect(find.byKey(const ValueKey('wallet-month')), findsOneWidget);
      expect(find.byKey(const ValueKey('wallet-projection')), findsNothing);
      expect(find.text(r'+ $300,00'), findsOneWidget);
      expect(find.text('${Money.minus} \$120,25'), findsOneWidget);
      expect(find.textContaining('null'), findsNothing);
      expect(find.textContaining('NaN'), findsNothing);
    });

    testWidgets('a month without movements shows zeros, not empty values', (tester) async {
      await pumpCard(tester, walletFixture(monthIncome: 0, monthExpenses: 0));
      expect(find.text(r'$0,00'), findsNWidgets(2));
    });

    testWidgets('plan Contador Profesional: balance projected to the end of the month', (tester) async {
      await pumpCard(tester, walletFixture(projectedBalance: 1180.95));
      expect(find.byKey(const ValueKey('wallet-projection')), findsOneWidget);
      expect(find.byKey(const ValueKey('wallet-month')), findsNothing);
      expect(find.text('Saldo proyectado a fin de mes'), findsOneWidget);
      expect(find.text(r'$1.180,95'), findsOneWidget);
    });

    testWidgets('negative balance is marked in text, not only by colour', (tester) async {
      await pumpCard(tester, walletFixture(balance: -42.1));
      expect(find.text('${Money.minus}\$42,10'), findsOneWidget);
      expect(find.text('Saldo negativo'), findsOneWidget);
    });

    for (final balance in [42.1, -42.1]) {
      testWidgets('balance $balance: no underline nor border under the number', (tester) async {
        await pumpCard(tester, walletFixture(balance: balance));
        final number = find.byKey(const ValueKey('wallet-balance'));
        final texts = find.descendant(of: number, matching: find.byType(Text), matchRoot: true);
        expect(texts, findsWidgets);
        for (final text in tester.widgetList<Text>(texts)) {
          expect(text.style?.decoration, TextDecoration.none);
        }
        for (final box in tester.widgetList<DecoratedBox>(
          find.descendant(of: number, matching: find.byType(DecoratedBox)),
        )) {
          expect((box.decoration as BoxDecoration).border, isNull);
        }
      });
    }

    testWidgets('shared wallets show the badge, members and owner', (tester) async {
      await pumpCard(tester, walletFixture(memberCount: 2));
      expect(find.text('Compartida · 2'), findsOneWidget);

      await pumpCard(tester, walletFixture(isOwner: false, ownerName: 'Luis Andrade', memberCount: 1));
      expect(find.text('Compartida · 1'), findsOneWidget);
      expect(find.text('Banco Pichincha · de Luis Andrade'), findsOneWidget);
    });

    testWidgets('long names are truncated without overflow on a small phone', (tester) async {
      await pumpCard(
        tester,
        walletFixture(
          name: 'Billetera con un nombre larguísimo que jamás cabría en la tarjeta',
          bankName: 'Banco del Instituto Ecuatoriano de Seguridad Social (BIESS)',
          memberCount: 3,
          balance: 987654321.99,
        ),
        width: 300,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('screen readers hear the whole card in one label', (tester) async {
      await pumpCard(tester, walletFixture(name: 'Casa', memberCount: 2, balance: 10));
      expect(
        find.bySemanticsLabel(RegExp(r'^Casa, Banco Pichincha, Ahorros, compartida con 2 miembros, saldo \$10,00')),
        findsOneWidget,
      );
    });
  });

  group('goldens (COU-213)', () {
    Future<void> pumpGolden(WidgetTester tester, List<Wallet> wallets, {ThemeMode mode = ThemeMode.dark}) async {
      tester.view.physicalSize = const Size(400, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpApp(
        RepaintBoundary(
          key: const ValueKey('golden'),
          // The screen background, so the goldens show the card in its theme.
          child: Builder(
            builder: (context) => ColoredBox(
              color: Theme.of(context).scaffoldBackgroundColor,
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  spacing: 12,
                  children: [for (final wallet in wallets) WalletCard(wallet: wallet)],
                ),
              ),
            ),
          ),
        ),
        themeMode: mode,
      );
      // The final frame: balances count up when they first show.
      await tester.pumpAndSettle();
    }

    final catalogue = [
      walletFixture(name: 'Ahorros', bankName: 'Banco Pichincha', bankColor: 0xFFFFDD00, memberCount: 2),
      walletFixture(
        id: 2,
        name: 'Tarjeta',
        bankName: 'Banco Guayaquil',
        bankColor: 0xFFD6006E,
        type: WalletType.creditCard,
        balance: -320.4,
      ),
      walletFixture(
        id: 3,
        name: 'Nómina',
        bankName: 'Banco del Pacífico',
        bankColor: 0xFF0072BC,
        type: WalletType.checking,
      ),
    ];

    testWidgets('bank colours, dark theme, month figures', (tester) async {
      await pumpGolden(tester, catalogue);
      await expectLater(find.byKey(const ValueKey('golden')), matchesGoldenFile('goldens/wallet_cards_dark.png'));
    });

    testWidgets('bank colours, light theme, with projection', (tester) async {
      await pumpGolden(tester, [
        for (final wallet in catalogue)
          walletFixture(
            id: wallet.walletId,
            name: wallet.name,
            bankName: wallet.bankName,
            bankColor: wallet.bankColor,
            type: wallet.type,
            memberCount: wallet.memberCount,
            balance: wallet.balance,
            projectedBalance: wallet.balance + 180.25,
          ),
      ], mode: ThemeMode.light);
      await expectLater(find.byKey(const ValueKey('golden')), matchesGoldenFile('goldens/wallet_cards_light.png'));
    });

    testWidgets('default colour: no bank, shared with me', (tester) async {
      await pumpGolden(tester, [
        walletFixture(bankName: null, bankColor: null, type: WalletType.cash, name: 'Efectivo'),
        walletFixture(id: 2, isOwner: false, ownerName: 'Luis Andrade', bankName: null, bankColor: null, name: 'Casa'),
      ]);
      await expectLater(find.byKey(const ValueKey('golden')), matchesGoldenFile('goldens/wallet_cards_default.png'));
    });
  });
}
