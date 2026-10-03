import 'package:countit_app/app/errors/app_failure.dart';
import 'package:countit_app/app/links/auth_links.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../helpers/mocks.dart';

void main() {
  setUpAll(() => registerFallbackValue(Uri()));

  group('AuthLink.parse', () {
    test('confirmation link, valid and expired', () {
      expect(
        AuthLink.parse(Uri.parse('countit://auth/confirmed#access_token=a&type=signup')),
        isA<EmailConfirmedLink>().having((l) => l.expired, 'expired', isFalse),
      );
      expect(
        AuthLink.parse(Uri.parse('countit://auth/confirmed#error=access_denied&error_code=otp_expired')),
        isA<EmailConfirmedLink>().having((l) => l.expired, 'expired', isTrue),
      );
    });

    test('reset link needs a token in the fragment', () {
      expect(
        AuthLink.parse(Uri.parse('countit://auth/reset-password#access_token=a&refresh_token=r&type=recovery')),
        isA<PasswordResetLink>().having((l) => l.expired, 'expired', isFalse),
      );
      expect(
        AuthLink.parse(Uri.parse('countit://auth/reset-password')),
        isA<PasswordResetLink>().having((l) => l.expired, 'expired', isTrue),
      );
    });

    test('other links are ignored', () {
      expect(AuthLink.parse(Uri.parse('https://countit.app/auth/confirmed')), isNull);
      expect(AuthLink.parse(Uri.parse('countit://wallets/3')), isNull);
      expect(AuthLink.parse(Uri.parse('countit://auth/unknown')), isNull);
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

    final reset = Uri.parse('countit://auth/reset-password#access_token=a&refresh_token=r&type=recovery');

    test('confirmation never signs in', () async {
      await handler.handle(Uri.parse('countit://auth/confirmed#access_token=a&refresh_token=r&type=signup'));
      expect(visited, [AuthLinkDestination.emailConfirmed]);
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
        initial: Future.value(Uri.parse('countit://auth/confirmed')),
        links: Stream.value(Uri.parse('countit://auth/confirmed')),
      );
      await Future<void>.delayed(Duration.zero);
      expect(visited, [AuthLinkDestination.emailConfirmed]);
      await handler.dispose();
    });
  });
}
