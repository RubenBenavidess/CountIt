import 'package:countit_app/app/app.dart';
import 'package:countit_app/app/config/app_config.dart';
import 'package:countit_app/presentation/splash/view/splash_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

void main() {
  GoRouter splashOnly(AppEnvironment env) => GoRouter(
    routes: [
      GoRoute(
        path: '/',
        builder: (context, state) => SplashPage(environment: env),
      ),
    ],
  );

  testWidgets('starts on the splash with the wordmark, in Spanish (Ecuador) and dark mode', (tester) async {
    await tester.pumpWidget(CountItApp(router: splashOnly(AppEnvironment.staging)));
    await tester.pumpAndSettle();

    expect(find.bySemanticsLabel('Count It!'), findsOneWidget);
    expect(find.text('Cuéntalo todo.'), findsOneWidget);
    expect(find.text('STAGING'), findsOneWidget, reason: 'non-production builds show their environment');

    final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(app.locale, const Locale('es', 'EC'));
    expect(app.themeMode, ThemeMode.dark);
  });

  testWidgets('production builds hide the environment label', (tester) async {
    await tester.pumpWidget(CountItApp(router: splashOnly(AppEnvironment.prod)));
    await tester.pumpAndSettle();
    expect(find.text('PROD'), findsNothing);
  });
}
