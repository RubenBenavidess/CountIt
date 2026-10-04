import 'package:clock/clock.dart';
import 'package:countit_app/shared/utils/dates.dart';
import 'package:countit_app/shared/widgets/app_banner.dart';
import 'package:countit_app/shared/widgets/cooldown_button.dart';
import 'package:countit_app/shared/widgets/password_checklist.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/pump_app.dart';

void main() {
  setUpAll(Dates.init);

  test('CooldownButton.format', () {
    expect(CooldownButton.format(const Duration(seconds: 5)), '0:05');
    expect(CooldownButton.format(const Duration(seconds: 125)), '2:05');
  });

  testWidgets('CooldownButton counts down and re-enables itself', (tester) async {
    var taps = 0;
    final start = clock.now();
    await tester.pumpApp(
      CooldownButton(label: 'Enviar', until: start.add(const Duration(seconds: 2)), onPressed: () => taps++),
    );
    expect(find.text('Espera 0:02'), findsOneWidget);
    await tester.tap(find.byType(FilledButton));
    expect(taps, 0);

    await tester.pump(const Duration(seconds: 3));
    expect(find.text('Enviar'), findsOneWidget);
    await tester.tap(find.byType(FilledButton));
    expect(taps, 1);
  });

  testWidgets('PasswordChecklist follows the controller', (tester) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    await tester.pumpApp(PasswordChecklist(controller: controller));
    expect(find.bySemanticsLabel('8 caracteres o más: pendiente'), findsOneWidget);
    controller.text = 'Quito2026';
    await tester.pump();
    expect(find.bySemanticsLabel(RegExp(r': cumplido$')), findsNWidgets(3));
  });

  testWidgets('AppBanner is announced and shows its action', (tester) async {
    await tester.pumpApp(
      AppBanner(
        tone: BannerTone.error,
        message: 'Correo o contraseña incorrectos',
        action: TextButton(onPressed: () {}, child: const Text('Reintentar')),
      ),
    );
    expect(find.text('Correo o contraseña incorrectos'), findsOneWidget);
    expect(find.text('Reintentar'), findsOneWidget);
    final semantics = tester.getSemantics(find.byType(AppBanner));
    expect(semantics.flagsCollection.isLiveRegion, isTrue);
  });
}
