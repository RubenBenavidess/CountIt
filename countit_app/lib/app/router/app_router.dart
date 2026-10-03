import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:go_router/go_router.dart';

import '../../presentation/admin/view/admin_page.dart';
import '../../presentation/auth/view/login_page.dart';
import '../../presentation/home/view/home_page.dart';
import '../../presentation/splash/view/splash_page.dart';
import '../config/app_config.dart';
import '../session/session_cubit.dart';
import '../session/session_state.dart';

abstract final class AppRoutes {
  static const splash = '/splash';
  static const login = '/login';
  static const home = '/';
  static const admin = '/admin';

  /// Reachable without a session.
  static const public = {login};
}

/// Pure redirect rules (unit-tested): session first, then role (COU-46).
String? redirectFor(SessionState session, String location) {
  switch (session.status) {
    case SessionStatus.unknown:
      return location == AppRoutes.splash ? null : AppRoutes.splash;
    case SessionStatus.unauthenticated:
      return AppRoutes.public.contains(location) ? null : AppRoutes.login;
    case SessionStatus.authenticated:
      if (location == AppRoutes.splash || AppRoutes.public.contains(location)) return AppRoutes.home;
      if (location.startsWith(AppRoutes.admin) && !(session.profile?.role.canAdminister ?? false)) {
        return AppRoutes.home;
      }
      return null;
  }
}

GoRouter buildRouter({required SessionCubit session, required AppConfig config}) => GoRouter(
  initialLocation: AppRoutes.splash,
  refreshListenable: _StreamListenable(session.stream),
  redirect: (context, state) => redirectFor(session.state, state.matchedLocation),
  routes: [
    GoRoute(
      path: AppRoutes.splash,
      builder: (context, state) => SplashPage(environment: config.environment),
    ),
    GoRoute(path: AppRoutes.login, builder: (context, state) => const LoginPage()),
    GoRoute(path: AppRoutes.home, builder: (context, state) => const HomePage()),
    GoRoute(path: AppRoutes.admin, builder: (context, state) => const AdminPage()),
  ],
);

/// Re-runs the router redirect whenever the session changes.
class _StreamListenable extends ChangeNotifier {
  _StreamListenable(Stream<Object?> stream) {
    _subscription = stream.listen((_) => notifyListeners());
  }

  late final StreamSubscription<Object?> _subscription;

  @override
  void dispose() {
    unawaited(_subscription.cancel());
    super.dispose();
  }
}
