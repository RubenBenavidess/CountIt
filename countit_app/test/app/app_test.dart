import 'package:countit_app/app/app.dart';
import 'package:countit_app/app/config/app_config.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  AppConfig config(AppEnvironment env) =>
      AppConfig(environment: env, supabaseUrl: 'https://x.supabase.co', supabaseAnonKey: 'k');

  testWidgets('starts on the splash with the wordmark, in Spanish (Ecuador) and dark mode', (tester) async {
    await tester.pumpWidget(CountItApp(config: config(AppEnvironment.staging)));

    expect(find.bySemanticsLabel('Count It!'), findsOneWidget);
    expect(find.text('Cuéntalo todo.'), findsOneWidget);
    expect(find.text('STAGING'), findsOneWidget, reason: 'non-production builds show their environment');

    final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(app.locale, const Locale('es', 'EC'));
    expect(app.themeMode, ThemeMode.dark);
  });

  testWidgets('production builds hide the environment label', (tester) async {
    await tester.pumpWidget(CountItApp(config: config(AppEnvironment.prod)));
    expect(find.text('PROD'), findsNothing);
  });
}
