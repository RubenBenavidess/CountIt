import 'package:bloc_test/bloc_test.dart';
import 'package:countit_app/app/errors/app_failure.dart';
import 'package:countit_app/app/router/app_router.dart';
import 'package:countit_app/data/dtos/wallet.dart';
import 'package:countit_app/presentation/families/cubit/invite_member_cubit.dart';
import 'package:countit_app/presentation/families/view/family_members_page.dart';
import 'package:countit_app/presentation/families/view/invite_member_page.dart';
import 'package:countit_app/shared/state/submit_cubit.dart';
import 'package:countit_app/shared/utils/dates.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';

import '../../helpers/family_fixtures.dart';
import '../../helpers/mocks.dart';
import '../../helpers/pump_app.dart';
import '../../helpers/wallet_fixtures.dart';

AppFailure _failure(FailureKind kind, int status, String key, String message) =>
    AppFailure(kind: kind, message: message, key: key, status: status);

final _notInPlan = _failure(FailureKind.featureNotInPlan, 403, 'feature_not_in_plan', 'Tu plan no incluye familias');
final _memberQuota = _failure(
  FailureKind.conflict,
  409,
  'family_member_limit_exceeded',
  'Alcanzaste el límite de 3 miembros por familia de tu plan',
);
final _sharedQuota = _failure(
  FailureKind.conflict,
  409,
  'family_limit_exceeded',
  'Alcanzaste el límite de 2 billeteras compartidas de tu plan',
);
final _daily = _failure(
  FailureKind.rateLimited,
  429,
  'invitation_limit',
  'Alcanzaste el máximo de 20 invitaciones por día',
);
final _unknownUser = _failure(
  FailureKind.notFound,
  404,
  'user_not_found',
  'No existe un usuario con ese nombre de usuario',
);
final _already = _failure(FailureKind.conflict, 409, 'already_member', 'Este usuario ya es miembro de la familia');
final _pending = _failure(
  FailureKind.conflict,
  409,
  'invitation_pending',
  'Este usuario ya tiene una invitación pendiente',
);
final _self = _failure(FailureKind.validation, 400, 'self_invitation', 'No puedes invitarte a tu propia billetera');

void main() {
  late MockFamilyRepository families;

  setUpAll(Dates.init);

  setUp(() {
    families = noFamilies();
  });

  group('InviteMemberCubit (COU-157)', () {
    blocTest<InviteMemberCubit, SubmitState>(
      'invites the trimmed username to its wallet',
      setUp: () => when(() => families.invite(4, 'carlos_q')).thenAnswer((_) async => memberFixture()),
      build: () => InviteMemberCubit(families, walletId: 4),
      act: (cubit) => cubit.invite(' carlos_q '),
      expect: () => const [SubmitState(status: SubmitStatus.submitting), SubmitState(status: SubmitStatus.success)],
    );

    blocTest<InviteMemberCubit, SubmitState>(
      'keeps the backend failure',
      setUp: () => when(() => families.invite(4, any())).thenThrow(_daily),
      build: () => InviteMemberCubit(families, walletId: 4),
      act: (cubit) => cubit.invite('carlos_q'),
      expect: () => [
        const SubmitState(status: SubmitStatus.submitting),
        SubmitState(status: SubmitStatus.failure, failure: _daily),
      ],
    );
  });

  group('InviteMemberPage (COU-90, COU-157)', () {
    final wallet = walletFixture(id: 4, name: 'Casa');

    /// Members screen → «Invitar» → the real invite page.
    Future<void> pumpFlow(WidgetTester tester, {bool planHasFamilies = true}) async {
      tester.view.physicalSize = const Size(420, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final session = await signedIn(familyProfile(families: planHasFamilies));
      final router = GoRouter(
        initialLocation: AppRoutes.members(4),
        routes: [
          GoRoute(
            path: AppRoutes.home,
            builder: (context, state) => const Scaffold(body: Text('HOME')),
          ),
          GoRoute(
            path: '/wallets/:id/members',
            builder: (context, state) => FamilyMembersPage(wallet: wallet),
            routes: [
              GoRoute(
                path: 'invite',
                builder: (context, state) => InviteMemberPage(wallet: state.extra! as Wallet),
              ),
            ],
          ),
        ],
      );
      await tester.pumpApp(const SizedBox(), families: families, session: session, router: router);
      await tester.pumpAndSettle();
    }

    Future<void> openForm(WidgetTester tester) async {
      await tester.tap(find.byKey(const ValueKey('member-invite')));
      await tester.pumpAndSettle();
      expect(find.text('Invitar a la familia'), findsOneWidget);
    }

    Future<void> submit(WidgetTester tester, String username) async {
      await tester.enterText(find.byType(TextFormField), username);
      await tester.tap(find.text('Enviar invitación'));
      await tester.pumpAndSettle();
    }

    testWidgets('validates the username like the API before sending', (tester) async {
      await pumpFlow(tester);
      await openForm(tester);
      await submit(tester, '');
      expect(find.text('Este campo no puede quedar vacío'), findsOneWidget);
      await submit(tester, 'ana');
      expect(find.text('El nombre de usuario debe tener al menos 5 caracteres'), findsOneWidget);
      await tester.enterText(find.byType(TextFormField), 'ana q@x!');
      await tester.pump();
      expect(find.text('anaqx'), findsOneWidget, reason: 'spaces and symbols are filtered out');
      verifyNever(() => families.invite(any(), any()));
    });

    testWidgets('success: back to the members with a confirmation; the list reloads', (tester) async {
      when(() => families.invite(4, 'carlos_q')).thenAnswer((_) async => memberFixture());
      await pumpFlow(tester);
      clearInteractions(families);
      await openForm(tester);
      await submit(tester, 'carlos_q');
      expect(find.text('Invitamos a @carlos_q. Tiene 7 días para aceptar.'), findsOneWidget);
      expect(find.text('Miembros'), findsOneWidget);
      verify(() => families.membersOf(4)).called(1);
    });

    for (final failure in [_unknownUser, _already, _pending, _self]) {
      testWidgets('${failure.key}: message next to the field', (tester) async {
        when(() => families.invite(4, any())).thenThrow(failure);
        await pumpFlow(tester);
        await openForm(tester);
        await submit(tester, 'carlos_q');
        expect(find.text(failure.message), findsOneWidget);
        expect(find.text('Invitar a la familia'), findsOneWidget, reason: 'stays on the form');

        // Editing the username hides the server message.
        await tester.enterText(find.byType(TextFormField), 'carlos_r');
        await tester.pumpAndSettle();
        expect(find.text(failure.message), findsNothing);
      });
    }

    testWidgets('429 invitation_limit: banner with the daily limit', (tester) async {
      when(() => families.invite(4, any())).thenThrow(_daily);
      await pumpFlow(tester);
      await openForm(tester);
      await submit(tester, 'carlos_q');
      expect(find.text('Alcanzaste el máximo de 20 invitaciones por día'), findsOneWidget);
    });

    testWidgets('403 feature_not_in_plan: no local sheet or banner, the global handler opens it (COU-183)', (
      tester,
    ) async {
      when(() => families.invite(4, any())).thenThrow(_notInPlan);
      await pumpFlow(tester);
      await openForm(tester);
      await submit(tester, 'carlos_q');
      expect(find.text('Entendido'), findsNothing);
      expect(find.text(_notInPlan.message), findsNothing);
      expect(find.text('Enviar invitación'), findsOneWidget, reason: 'the form stays');
    });

    for (final quota in [_memberQuota, _sharedQuota]) {
      testWidgets('409 ${quota.key}: the plans sheet with the quota', (tester) async {
        when(() => families.invite(4, any())).thenThrow(quota);
        await pumpFlow(tester);
        await openForm(tester);
        await submit(tester, 'carlos_q');
        expect(find.text('Alcanzaste el límite de tu plan'), findsOneWidget);
        expect(find.text(quota.message), findsOneWidget);
      });
    }

    testWidgets('a plan without families explains it without opening the form', (tester) async {
      await pumpFlow(tester, planHasFamilies: false);
      await tester.tap(find.byKey(const ValueKey('member-invite')));
      await tester.pumpAndSettle();
      expect(find.text(familiesNotInPlanTitle), findsOneWidget);
      expect(find.text('Enviar invitación'), findsNothing);
    });

    testWidgets('members never see «Invitar» (COU-167)', (tester) async {
      tester.view.physicalSize = const Size(420, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final session = await signedIn(familyProfile(userId: 'u2'));
      when(() => families.membersOf(4)).thenAnswer((_) async => [ownerFixture(), memberFixture()]);
      await tester.pumpApp(
        FamilyMembersPage(wallet: walletFixture(id: 4, isOwner: false, memberCount: 1)),
        families: families,
        session: session,
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('member-invite')), findsNothing);
    });
  });
}
