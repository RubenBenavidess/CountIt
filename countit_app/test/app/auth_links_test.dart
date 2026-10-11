import 'package:countit_app/app/config/app_config.dart';
import 'package:countit_app/app/errors/app_failure.dart';
import 'package:countit_app/app/links/auth_links.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../helpers/mocks.dart';

void main() {
  setUpAll(() => registerFallbackValue(Uri()));

  group('AuthLink.parse', () {
    const base = 'https://countit-bft.pages.dev';

    test('the default host is the beta site', () {
      expect(AppConfig.authLinkHost, 'countit-bft.pages.dev');
    });

    test('confirmation link, valid and expired', () {
      expect(
        AuthLink.parse(Uri.parse('$base/auth/confirmed#access_token=a&type=signup')),
        isA<EmailConfirmedLink>().having((l) => l.expired, 'expired', isFalse),
      );
      expect(
        AuthLink.parse(Uri.parse('$base/auth/confirmed#error=access_denied&error_code=otp_expired')),
        isA<EmailConfirmedLink>().having((l) => l.expired, 'expired', isTrue),
      );
      expect(
        AuthLink.parse(Uri.parse('$base/auth/confirmed?error=access_denied')),
        isA<EmailConfirmedLink>().having((l) => l.expired, 'expired', isTrue),
      );
    });

    test('reset link needs a token in the fragment', () {
      expect(
        AuthLink.parse(Uri.parse('$base/auth/reset-password#access_token=a&refresh_token=r&type=recovery')),
        isA<PasswordResetLink>().having((l) => l.expired, 'expired', isFalse),
      );
      expect(
        AuthLink.parse(Uri.parse('$base/auth/reset-password')),
        isA<PasswordResetLink>().having((l) => l.expired, 'expired', isTrue),
      );
      expect(
        AuthLink.parse(Uri.parse('$base/auth/reset-password#error=access_denied&error_code=otp_expired')),
        isA<PasswordResetLink>().having((l) => l.expired, 'expired', isTrue),
      );
    });

    test('a trailing slash and an upper-case host are accepted', () {
      expect(AuthLink.parse(Uri.parse('$base/auth/confirmed/')), isA<EmailConfirmedLink>());
      expect(
        AuthLink.parse(Uri.parse('$base/auth/reset-password/#access_token=a&refresh_token=r&type=recovery')),
        isA<PasswordResetLink>().having((l) => l.expired, 'expired', isFalse),
      );
      expect(AuthLink.parse(Uri.parse('https://CountIt-BFT.pages.dev/auth/confirmed')), isA<EmailConfirmedLink>());
    });

    test('a configured host replaces the default', () {
      expect(
        AuthLink.parse(Uri.parse('https://countit.ec/auth/confirmed'), host: 'countit.ec'),
        isA<EmailConfirmedLink>(),
      );
      expect(AuthLink.parse(Uri.parse('$base/auth/confirmed'), host: 'countit.ec'), isNull);
    });

    test('the custom scheme is no longer accepted', () {
      expect(
        AuthLink.parse(Uri.parse('countit://auth/reset-password#access_token=a&refresh_token=r&type=recovery')),
        isNull,
      );
      expect(AuthLink.parse(Uri.parse('countit://auth/confirmed')), isNull);
    });

    test('other schemes, hosts, ports, user info and paths are ignored', () {
      for (final link in [
        'http://countit-bft.pages.dev/auth/reset-password#access_token=a',
        'https://evil.com/auth/reset-password#access_token=a',
        'https://countit-bft.pages.dev.evil.com/auth/reset-password#access_token=a',
        'https://evil.countit-bft.pages.dev/auth/reset-password#access_token=a',
        'https://countit-bft.pages.dev@evil.com/auth/reset-password#access_token=a',
        'https://user@countit-bft.pages.dev/auth/reset-password#access_token=a',
        'https://countit-bft.pages.dev:8443/auth/reset-password#access_token=a',
        '$base/auth/unknown',
        '$base/auth/confirmed/extra',
        '$base/auth/reset-password-x#access_token=a',
        '$base/AUTH/confirmed',
        '$base/confirmed',
        '$base/',
        'intent://countit-bft.pages.dev/auth/confirmed',
      ]) {
        expect(AuthLink.parse(Uri.parse(link)), isNull, reason: link);
      }
    });
  });

  group('AuthLinkHandler', () {
    late MockAuthRepository auth;
    late List<AuthLinkDestination> visited;
    late AuthLinkHandler handler;

    setUp(() {
      auth = MockAuthRepository();
      visited = [];
      handler = AuthLinkHandler(auth: auth, navigate: visited.add);
    });

    final reset = Uri.parse(
      'https://countit-bft.pages.dev/auth/reset-password#access_token=a&refresh_token=r&type=recovery',
    );

    test('confirmation never signs in', () async {
      await handler.handle(
        Uri.parse('https://countit-bft.pages.dev/auth/confirmed#access_token=a&refresh_token=r&type=signup'),
      );
      expect(visited, [AuthLinkDestination.emailConfirmed]);
      verifyNever(() => auth.recoverSession(any()));
    });

    test('a custom-scheme recovery link is ignored and never adopts the session', () async {
      await handler.handle(Uri.parse('countit://auth/reset-password#access_token=a&refresh_token=r&type=recovery'));
      expect(visited, isEmpty);
      verifyNever(() => auth.recoverSession(any()));
    });

    test('a reset link adopts the recovery session', () async {
      when(() => auth.recoverSession(reset)).thenAnswer((_) async {});
      await handler.handle(reset);
      expect(visited, [AuthLinkDestination.resetPassword]);
    });

    test('a rejected recovery session sends the user to request a new link', () async {
      when(() => auth.recoverSession(reset))
          .thenThrow(const AppFailure(kind: FailureKind.forbidden, message: 'El enlace venció', key: 'otp_expired'));
      await handler.handle(reset);
      expect(visited, [AuthLinkDestination.resetLinkExpired]);
    });

    test('the cold-start link delivered twice is handled once', () async {
      await handler.listen(
        initial: Future.value(Uri.parse('https://countit-bft.pages.dev/auth/confirmed')),
        links: Stream.value(Uri.parse('https://countit-bft.pages.dev/auth/confirmed')),
      );
      await Future<void>.delayed(Duration.zero);
      expect(visited, [AuthLinkDestination.emailConfirmed]);
      await handler.dispose();
    });
  });
}
