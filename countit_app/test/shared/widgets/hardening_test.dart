import 'package:countit_app/shared/utils/dates.dart';
import 'package:countit_app/shared/widgets/app_button.dart';
import 'package:countit_app/shared/widgets/app_fields.dart';
import 'package:countit_app/shared/widgets/secure_screen.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/pump_app.dart';

void main() {
  setUpAll(Dates.init);

  group('SecureScreen (COU-115)', () {
    late List<String> calls;

    setUp(() {
      calls = [];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(SecureScreen.channel, (
        call,
      ) async {
        calls.add(call.method);
        return null;
      });
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
    });

    tearDown(() {
      debugDefaultTargetPlatformOverride = null;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
        SecureScreen.channel,
        null,
      );
    });

    testWidgets('enables FLAG_SECURE once while any secure screen is shown', (tester) async {
      await tester.pumpApp(const SecureScreen(child: SecureScreen(child: Text('Contraseña'))));
      expect(calls, ['enable']);
      expect(SecureScreen.activeCount, 2);

      await tester.pumpApp(const Text('Pantalla normal'));
      expect(calls, ['enable', 'disable']);
      expect(SecureScreen.activeCount, 0);
      debugDefaultTargetPlatformOverride = null;
    });
  });

  testWidgets('PrivacyCurtain hides the content when the app leaves the foreground', (tester) async {
    await tester.pumpApp(const PrivacyCurtain(child: Text(r'Saldo $2.140,50')));
    expect(find.bySemanticsLabel('Count It!'), findsNothing);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();
    expect(find.bySemanticsLabel('Count It!'), findsOneWidget);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(find.bySemanticsLabel('Count It!'), findsNothing);
  });

  testWidgets('date picker opens even when today is outside the allowed range (audit A6)', (tester) async {
    await tester.pumpApp(
      AppDateField(
        label: 'Inicio de la regla',
        value: null,
        onChanged: (_) {},
        firstDate: DateTime.now().add(const Duration(days: 1)), // scheduled rules start tomorrow
        lastDate: DateTime.now().add(const Duration(days: 400)),
      ),
    );
    await tester.tap(find.text('Selecciona una fecha'));
    await tester.pumpAndSettle();
    expect(find.byType(DatePickerDialog), findsOneWidget);
  });

  testWidgets('dropdown follows a value changed by the parent (audit A7)', (tester) async {
    final value = ValueNotifier<String?>('cash');
    await tester.pumpApp(
      ValueListenableBuilder<String?>(
        valueListenable: value,
        builder: (context, v, _) => AppDropdownField<String>(
          label: 'Tipo',
          value: v,
          options: const [AppOption('cash', 'Efectivo'), AppOption('savings', 'Ahorros')],
          onChanged: (_) {},
        ),
      ),
    );
    expect(find.text('Efectivo'), findsOneWidget);
    value.value = 'savings';
    await tester.pump();
    expect(find.text('Ahorros'), findsOneWidget);
    expect(find.text('Efectivo'), findsNothing);
  });

  testWidgets('a loading button is announced once, with its label (audit A5)', (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpApp(AppButton(label: 'Guardar', loading: true, onPressed: () {}));
    expect(find.bySemanticsLabel('Guardar, cargando'), findsOneWidget);
    handle.dispose();
  });
}
