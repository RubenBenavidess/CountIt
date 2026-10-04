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

    test('without a session only public routes are reachable; a fresh start shows the welcome', () {
      const s = SessionState.unauthenticated();
      expect(redirectFor(s, AppRoutes.home), AppRoutes.welcome);
      expect(redirectFor(s, AppRoutes.admin), AppRoutes.welcome);
      expect(redirectFor(s, AppRoutes.splash), AppRoutes.welcome);
      expect(redirectFor(s, AppRoutes.resetPassword), AppRoutes.welcome);
      for (final route in AppRoutes.public) {
        expect(redirectFor(s, route), isNull, reason: route);
      }
    });

    test('an involuntary sign-out lands on login, where the reason is shown (COU-81)', () {
      const s = SessionState.unauthenticated(message: 'Tu sesión ya no es válida');
      expect(redirectFor(s, AppRoutes.home), AppRoutes.login);
      expect(redirectFor(s, AppRoutes.splash), AppRoutes.login);
    });

    test('the recovery session only opens the new-password screen', () {
      const s = SessionState.passwordRecovery();
      expect(redirectFor(s, AppRoutes.home), AppRoutes.resetPassword);
      expect(redirectFor(s, AppRoutes.login), AppRoutes.resetPassword);
      expect(redirectFor(s, AppRoutes.admin), AppRoutes.resetPassword);
      expect(redirectFor(s, AppRoutes.resetPassword), isNull);
    });

    test('signed in: auth screens and splash lead home', () {
      final s = SessionState.authenticated(_profile(UserRole.user));
      expect(redirectFor(s, AppRoutes.login), AppRoutes.home);
      expect(redirectFor(s, AppRoutes.welcome), AppRoutes.home);
      expect(redirectFor(s, AppRoutes.resetPassword), AppRoutes.home);
      expect(redirectFor(s, AppRoutes.splash), AppRoutes.home);
      expect(redirectFor(s, AppRoutes.home), isNull);
      expect(redirectFor(s, AppRoutes.root), AppRoutes.home);
      expect(redirectFor(s, AppRoutes.wallet(4)), isNull);
    });

    test('admin area: every admin path, never a look-alike prefix (COU-127)', () {
      final user = SessionState.authenticated(_profile(UserRole.user));
      expect(redirectFor(user, AppRoutes.adminUsers), AppRoutes.home);
      expect(redirectFor(user, AppRoutes.adminUser('u2')), AppRoutes.home);
      expect(redirectFor(user, '/administrator'), isNull, reason: 'not under /admin');
      expect(redirectFor(SessionState.authenticated(_profile(UserRole.admin)), AppRoutes.adminUser('u2')), isNull);
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
