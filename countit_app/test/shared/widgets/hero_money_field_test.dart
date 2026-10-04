import 'dart:math' as math;

import 'package:countit_app/app/theme/app_theme.dart';
import 'package:countit_app/app/theme/tokens.dart';
import 'package:countit_app/shared/widgets/app_fields.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/pump_app.dart';

/// Hosts the hero field with a toggle for its kind.
class _Host extends StatefulWidget {
  const _Host({required this.controller, this.errorText});

  final TextEditingController controller;
  final String? errorText;

  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> {
  bool _income = false;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: AppSpacing.screen),
    child: Column(
      children: [
        AppMoneyField.hero(income: _income, controller: widget.controller, errorText: widget.errorText),
        TextButton(onPressed: () => setState(() => _income = !_income), child: const Text('toggle')),
      ],
    ),
  );
}

final _input = find.byKey(const ValueKey('hero-amount-input'));

TextStyle _valueStyle(WidgetTester tester) => tester.widget<TextField>(_input).style!;

Text _prefix(WidgetTester tester, String prefix) => tester.widget<Text>(find.text(prefix));

double _contrast(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
}

void main() {
  late TextEditingController controller;

  setUp(() => controller = TextEditingController());
  tearDown(() => controller.dispose());

  group('AppMoneyField.hero', () {
    for (final mode in [ThemeMode.dark, ThemeMode.light]) {
      testWidgets('expense is «−\$» in palette.expense, income «+\$» in palette.income ($mode)', (tester) async {
        controller.text = '25,00';
        await tester.pumpApp(_Host(controller: controller), themeMode: mode);
        final palette = mode == ThemeMode.dark ? AppPalette.dark : AppPalette.light;

        expect(find.text('−\$'), findsOneWidget);
        expect(_prefix(tester, '−\$').style!.color, palette.expense);
        expect(_valueStyle(tester).color, palette.expense);
        expect(_valueStyle(tester).fontSize, AppTypography.display.fontSize);
        expect(_valueStyle(tester).fontWeight, FontWeight.w800);

        await tester.tap(find.text('toggle'));
        await tester.pumpAndSettle();
        expect(find.text('−\$'), findsNothing);
        expect(_prefix(tester, '+\$').style!.color, palette.income);
        expect(_valueStyle(tester).color, palette.income);
      });
    }

    testWidgets('the colour animates in ~250 ms; instant with reduced motion', (tester) async {
      await tester.pumpApp(_Host(controller: controller));
      await tester.tap(find.text('toggle'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      final mid = _valueStyle(tester).color;
      expect(mid, isNot(AppPalette.dark.expense));
      expect(mid, isNot(AppPalette.dark.income));
      await tester.pump(const Duration(milliseconds: 200));
      expect(_valueStyle(tester).color, AppPalette.dark.income);
    });

    testWidgets('reduced motion: colour and sign change at once', (tester) async {
      await tester.pumpApp(
        Builder(
          builder: (context) => MediaQuery(
            data: MediaQuery.of(context).copyWith(disableAnimations: true),
            child: _Host(controller: controller),
          ),
        ),
      );
      await tester.tap(find.text('toggle'));
      await tester.pump();
      await tester.pump();
      expect(_valueStyle(tester).color, AppPalette.dark.income);
      expect(find.text('−\$'), findsNothing);
      expect(find.text('+\$'), findsOneWidget);
    });

    testWidgets('empty: dimmed «0,00» placeholder at the same size', (tester) async {
      await tester.pumpApp(_Host(controller: controller));
      final hint = tester.widget<TextField>(_input).decoration!;
      expect(hint.hintText, '0,00');
      expect(hint.hintStyle!.fontSize, _valueStyle(tester).fontSize);
      expect(hint.hintStyle!.color, AppColors.placeholder);
      expect(find.text('0,00'), findsOneWidget);
    });

    testWidgets('same input rules: decimal keyboard, at most 2 decimals, no letters', (tester) async {
      await tester.pumpApp(_Host(controller: controller));
      expect(tester.widget<TextField>(_input).keyboardType, const TextInputType.numberWithOptions(decimal: true));
      await tester.enterText(_input, '1234,56');
      expect(controller.text, '1234,56');
      await tester.enterText(_input, '1234,567');
      expect(controller.text, '1234,56');
      await tester.enterText(_input, '12a');
      expect(controller.text, '1234,56');
    });

    testWidgets('shows the error centred below the amount', (tester) async {
      await tester.pumpApp(_Host(controller: controller, errorText: 'Este campo no puede quedar vacío'));
      expect(find.text('Este campo no puede quedar vacío'), findsOneWidget);
    });

    testWidgets('tapping the amount focuses the input', (tester) async {
      await tester.pumpApp(_Host(controller: controller));
      await tester.tap(find.text('−\$'));
      await tester.pump();
      expect(tester.widget<TextField>(_input).focusNode!.hasFocus, isTrue);
    });

    testWidgets('one semantics node: «Monto, gasto» with the value in dollars', (tester) async {
      final handle = tester.ensureSemantics();
      controller.text = '25,00';
      await tester.pumpApp(_Host(controller: controller));
      expect(
        tester.getSemantics(_input),
        isSemantics(label: 'Monto, gasto', value: '25,00 dólares', isTextField: true),
      );
      await tester.tap(find.text('toggle'));
      await tester.pumpAndSettle();
      expect(tester.getSemantics(_input), isSemantics(label: 'Monto, ingreso'));
      handle.dispose();
    });

    for (final scale in [1.0, 2.0]) {
      testWidgets('long amounts shrink to fit 360 dp without overflow (text scale $scale)', (tester) async {
        tester.view
          ..physicalSize = const Size(360, 800)
          ..devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await tester.pumpApp(
          Builder(
            builder: (context) => MediaQuery(
              data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
              child: _Host(controller: controller),
            ),
          ),
        );
        await tester.enterText(_input, '999999999999,99');
        await tester.pump();
        expect(tester.takeException(), isNull);
        expect(_valueStyle(tester).fontSize, lessThan(AppTypography.display.fontSize!));
        final field = tester.getRect(_input);
        final prefix = tester.getRect(find.text('−\$'));
        expect(prefix.left, greaterThanOrEqualTo(0));
        expect(field.right, lessThanOrEqualTo(360));
      });
    }

    test('income and expense keep ≥ 3:1 (large text) on the background in both themes; 4.5:1 in fact', () {
      for (final (palette, background) in [(AppPalette.dark, AppColors.ink), (AppPalette.light, AppColors.alabaster)]) {
        for (final color in [palette.income, palette.expense]) {
          expect(_contrast(color, background), greaterThanOrEqualTo(4.5));
        }
      }
    });
  });
}
