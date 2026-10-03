import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:go_router/go_router.dart';

import '../shared/widgets/secure_screen.dart';
import 'theme/app_theme.dart';

/// Root widget: theme, Spanish (Ecuador) locale and the router.
class CountItApp extends StatelessWidget {
  const CountItApp({super.key, required this.router});

  final GoRouter router;

  static const locale = Locale('es', 'EC');

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'Count It!',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      // The design is dark-first; a user setting can switch it later.
      themeMode: ThemeMode.dark,
      locale: locale,
      supportedLocales: const [locale],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      routerConfig: router,
      // Hides the content in the app switcher (COU-115).
      builder: (context, child) => PrivacyCurtain(child: child ?? const SizedBox.shrink()),
    );
  }
}
