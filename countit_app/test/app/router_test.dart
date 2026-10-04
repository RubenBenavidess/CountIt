import 'package:countit_app/app/router/app_router.dart';
import 'package:countit_app/app/session/session_state.dart';
import 'package:countit_app/data/dtos/profile.dart';
import 'package:flutter_test/flutter_test.dart';

Profile _profile(UserRole role) =>
    Profile(userId: 'u', username: 'ana', email: 'a@t.com', role: role, timezone: 'America/Guayaquil');

void main() {
  group('redirectFor (COU-46)', () {
    test('while restoring, everything goes to the splash', () {
      const s = SessionState.unknown();
      expect(redirectFor(s, AppRoutes.home), AppRoutes.splash);
      expect(redirectFor(s, AppRoutes.splash), isNull);
    });

    test('without a session only public routes are reachable', () {
      const s = SessionState.unauthenticated();
      expect(redirectFor(s, AppRoutes.home), AppRoutes.login);
      expect(redirectFor(s, AppRoutes.admin), AppRoutes.login);
      expect(redirectFor(s, AppRoutes.splash), AppRoutes.login);
      expect(redirectFor(s, AppRoutes.login), isNull);
    });

    test('signed in: auth screens and splash lead home', () {
      final s = SessionState.authenticated(_profile(UserRole.user));
      expect(redirectFor(s, AppRoutes.login), AppRoutes.home);
      expect(redirectFor(s, AppRoutes.splash), AppRoutes.home);
      expect(redirectFor(s, AppRoutes.home), isNull);
    });

    test('admin area only for admin and superadmin', () {
      expect(redirectFor(SessionState.authenticated(_profile(UserRole.user)), AppRoutes.admin), AppRoutes.home);
      expect(redirectFor(SessionState.authenticated(_profile(UserRole.admin)), AppRoutes.admin), isNull);
      expect(
        redirectFor(SessionState.authenticated(_profile(UserRole.superadmin)), '${AppRoutes.admin}/banks'),
        isNull,
      );
    });
  });
}
