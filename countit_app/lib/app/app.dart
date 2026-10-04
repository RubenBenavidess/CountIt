import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:go_router/go_router.dart';

import '../presentation/notifications/view/push_notice_host.dart';
import '../presentation/plans/view/plan_upsell_host.dart';
import '../shared/widgets/secure_screen.dart';
import 'errors/app_failure.dart';
import 'push/push_open_handler.dart';
import 'router/app_router.dart';
import 'theme/app_theme.dart';

/// Root widget: theme, Spanish (Ecuador) locale and the router.
class CountItApp extends StatelessWidget {
  const CountItApp({super.key, required this.router, this.planNotices, this.pushNotices});

  final GoRouter router;

  /// `403 feature_not_in_plan` answers (COU-183): each opens the plans sheet.
  final Stream<AppFailure>? planNotices;

  /// Pushes received in the foreground (COU-179): each shows a snackbar.
  final Stream<PushNotice>? pushNotices;

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
      builder: (context, child) {
        final content = child ?? const SizedBox.shrink();
        final notices = planNotices;
        final pushes = pushNotices;
        final withPlans = notices == null
            ? content
            : PlanUpsellHost(notices: notices, navigatorKey: router.routerDelegate.navigatorKey, child: content);
        return PrivacyCurtain(
          child: pushes == null
              ? withPlans
              : PushNoticeHost(
                  notices: pushes,
                  onOpen: (location) => navigateForNotification(router, location),
                  child: withPlans,
                ),
        );
      },
    );
  }
}
