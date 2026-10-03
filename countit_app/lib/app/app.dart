import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import '../presentation/splash/view/splash_page.dart';
import 'config/app_config.dart';
import 'theme/app_theme.dart';

/// Root widget: theme, Spanish (Ecuador) locale and the first screen.
class CountItApp extends StatelessWidget {
  const CountItApp({super.key, required this.config});

  final AppConfig config;

  static const locale = Locale('es', 'EC');

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Count It!',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      // The design is dark-first; a user setting can switch it later.
      themeMode: ThemeMode.dark,
      locale: locale,
      supportedLocales: const [locale],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      home: SplashPage(environment: config.environment),
    );
  }
}
