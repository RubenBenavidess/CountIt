import 'package:bloc_test/bloc_test.dart';
import 'package:countit_app/app/errors/app_failure.dart';
import 'package:countit_app/app/router/app_router.dart';
import 'package:countit_app/data/dtos/family.dart';
import 'package:countit_app/data/dtos/wallet.dart';
import 'package:countit_app/data/remote/api_client.dart';
import 'package:countit_app/presentation/families/cubit/family_members_cubit.dart';
import 'package:countit_app/presentation/families/view/family_members_page.dart';
import 'package:countit_app/shared/state/load_state.dart';
import 'package:countit_app/shared/utils/dates.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';

import '../../helpers/family_fixtures.dart';
import '../../helpers/mocks.dart';
import '../../helpers/pump_app.dart';
import '../../helpers/wallet_fixtures.dart';

const _reauthRequired = AppFailure(
  kind: FailureKind.reauthRequired,
  message: 'Confirma tu contraseña para continuar',
  key: 'reauth_required',
  status: 403,
);
const _memberNotFound = AppFailure(
  kind: FailureKind.notFound,
  message: 'Miembro no encontrado',
  key: 'member_not_found',
  status: 404,
);
const _network = AppFailure(kind: FailureKind.network, message: 'No hay conexión.');

void main() {
  late MockFamilyRepository families;

  setUpAll(Dates.init);
  setUp(() => families = noFamilies());

  final owner = ownerFixture();
  final luis = memberFixture();
  final carlos = memberFixture(userId: 'u3', username: 'carlos_q', displayName: 'Carlos', status: FamilyStatus.pending);
  final members = [owner, luis, carlos];

  group('FamilyMembersCubit actions (COU-163, COU-165)', () {
    Future<bool> prompt() async => true;

    blocTest<FamilyMembersCubit, FamilyMembersState>(
      'removing an accepted member passes the password prompt and drops the row',
      setUp: () => when(() => families.remove(4, 'u2', onReauth: any(named: 'onReauth'))).thenAnswer((_) async {}),
      build: () => FamilyMembersCubit(families, walletId: 4),
      seed: () => FamilyMembersState(members: LoadState.success(members)),
      act: (cubit) => cubit.remove(luis, onReauth: prompt),
      expect: () => [
        FamilyMembersState(members: LoadState.success(members), busy: const {'u2'}),
        FamilyMembersState(
          members: LoadState.success([owner, carlos]),
          lastAction: const MemberActionResult(1, MemberActionOutcome.removed, name: 'Luis Andrade'),
        ),
      ],
      verify: (_) => verify(() => families.remove(4, 'u2', onReauth: prompt)).called(1),
    );

    blocTest<FamilyMembersCubit, FamilyMembersState>(
      'cancelling a pending invitation never asks for the password',
      setUp: () => when(() => families.remove(4, 'u3', onReauth: any(named: 'onReauth'))).thenAnswer((_) async {}),
      build: () => FamilyMembersCubit(families, walletId: 4),
      seed: () => FamilyMembersState(members: LoadState.success(members)),
      act: (cubit) => cubit.remove(carlos, onReauth: prompt),
      verify: (cubit) {
        verify(() => families.remove(4, 'u3')).called(1);
        expect(cubit.state.lastAction?.outcome, MemberActionOutcome.cancelled);
      },
    );

    blocTest<FamilyMembersCubit, FamilyMembersState>(
      'password sheet closed: nothing changes, nothing is reported',
      setUp: () => when(() => families.remove(4, 'u2', onReauth: any(named: 'onReauth'))).thenThrow(_reauthRequired),
      build: () => FamilyMembersCubit(families, walletId: 4),
      seed: () => FamilyMembersState(members: LoadState.success(members)),
      act: (cubit) => cubit.remove(luis, onReauth: prompt),
      expect: () => [
        FamilyMembersState(members: LoadState.success(members), busy: const {'u2'}),
        FamilyMembersState(members: LoadState.success(members)),
      ],
    );

    blocTest<FamilyMembersCubit, FamilyMembersState>(
      'already gone (404): the row leaves; other errors keep it',
      setUp: () {
        when(() => families.remove(4, 'u2', onReauth: any(named: 'onReauth'))).thenThrow(_memberNotFound);
        when(() => families.remove(4, 'u3', onReauth: any(named: 'onReauth'))).thenThrow(_network);
      },
      build: () => FamilyMembersCubit(families, walletId: 4),
      seed: () => FamilyMembersState(members: LoadState.success(members)),
      act: (cubit) async {
        await cubit.remove(luis);
        await cubit.remove(carlos);
      },
      verify: (cubit) {
        expect(cubit.state.members.data, [owner, carlos]);
        expect(cubit.state.lastAction?.outcome, MemberActionOutcome.failed);
        expect(cubit.state.lastAction?.failure, _network);
      },
    );

    blocTest<FamilyMembersCubit, FamilyMembersState>(
      'the owner row is never removed',
      build: () => FamilyMembersCubit(families, walletId: 4),
      act: (cubit) => cubit.remove(owner),
      expect: () => const <FamilyMembersState>[],
    );

    blocTest<FamilyMembersCubit, FamilyMembersState>(
      'leave: left; already out (404) also counts as left',
      setUp: () => when(() => families.leave(4)).thenThrow(_memberNotFound),
      build: () => FamilyMembersCubit(families, walletId: 4),
      act: (cubit) => cubit.leave(walletName: 'Casa'),
      expect: () => const [
        FamilyMembersState(leaving: true),
        FamilyMembersState(lastAction: MemberActionResult(1, MemberActionOutcome.left, name: 'Casa')),
      ],
    );

    blocTest<FamilyMembersCubit, FamilyMembersState>(
      'leave failure: stays with the error',
      setUp: () => when(() => families.leave(4)).thenThrow(_network),
      build: () => FamilyMembersCubit(families, walletId: 4),
      act: (cubit) => cubit.leave(walletName: 'Casa'),
      expect: () => const [
        FamilyMembersState(leaving: true),
        FamilyMembersState(
          lastAction: MemberActionResult(1, MemberActionOutcome.failed, name: 'Casa', failure: _network),
        ),
      ],
    );
  });

  group('members screen actions (COU-163, COU-165, COU-167)', () {
    late MockAuthRepository auth;

    setUp(() {
      auth = MockAuthRepository();
      when(() => auth.sessionChanges).thenAnswer((_) => const Stream.empty());
    });

    Future<void> pumpPage(WidgetTester tester, Wallet wallet, {String userId = 'u1'}) async {
      tester.view.physicalSize = const Size(420, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final session = await signedIn(familyProfile(userId: userId));
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
          ),
        ],
      );
      await tester.pumpApp(const SizedBox(), auth: auth, families: families, session: session, router: router);
      await tester.pumpAndSettle();
    }

    Finder inSheet(String text) => find.descendant(of: find.byType(BottomSheet), matching: find.text(text));

    /// Like [ApiClient.run]: on reauth_required asks [ReauthPrompt] and retries once.
    void removeNeedsReauth(String userId, List<String> calls) =>
        when(() => families.remove(4, userId, onReauth: any(named: 'onReauth'))).thenAnswer((invocation) async {
          calls.add(userId);
          if (calls.length > 1) return;
          final prompt = invocation.namedArguments[#onReauth] as ReauthPrompt?;
          if (prompt == null || !await prompt()) throw _reauthRequired;
          calls.add(userId);
        });

    testWidgets('owner removes an accepted member: confirmation, password, row leaves', (tester) async {
      when(() => families.membersOf(4)).thenAnswer((_) async => members);
      final calls = <String>[];
      removeNeedsReauth('u2', calls);
      when(() => auth.reauthenticate('Quito2026')).thenAnswer((_) async => DateTime(2026, 10, 4, 12, 5));
      await pumpPage(tester, walletFixture(id: 4, name: 'Casa', memberCount: 1));

      await tester.tap(find.byTooltip('Quitar a Luis Andrade'));
      await tester.pumpAndSettle();
      expect(find.text('¿Quitar a Luis Andrade?'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Quitar'));
      // Frames instead of settling: the row's spinner runs while the sheet is open.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('Confirma que eres tú'), findsOneWidget);
      expect(find.textContaining('Para quitar a Luis Andrade escribe tu contraseña'), findsOneWidget);

      await tester.enterText(find.byType(EditableText), 'Quito2026');
      await tester.tap(inSheet('Quitar miembro'));
      await tester.pump();
      await tester.pumpAndSettle();
      verify(() => auth.reauthenticate('Quito2026')).called(1);
      expect(calls, ['u2', 'u2'], reason: 'first attempt plus the retry');
      expect(find.text('Quitaste a Luis Andrade de la familia'), findsOneWidget);
      expect(find.byKey(const ValueKey('member-u2')), findsNothing);
    });

    testWidgets('closing the password sheet removes nobody and says nothing', (tester) async {
      when(() => families.membersOf(4)).thenAnswer((_) async => members);
      final calls = <String>[];
      removeNeedsReauth('u2', calls);
      await pumpPage(tester, walletFixture(id: 4));
      await tester.tap(find.byTooltip('Quitar a Luis Andrade'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Quitar'));
      // Frames instead of settling: the row's spinner runs while the sheet is open.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      await tester.tap(inSheet('Cancelar'));
      await tester.pumpAndSettle();
      expect(calls, ['u2']);
      expect(find.byKey(const ValueKey('member-u2')), findsOneWidget);
      expect(find.byType(SnackBar), findsNothing);
    });

    testWidgets('cancelling an invitation: confirmation only, no password', (tester) async {
      when(() => families.membersOf(4)).thenAnswer((_) async => members);
      when(() => families.remove(4, 'u3', onReauth: any(named: 'onReauth'))).thenAnswer((_) async {});
      await pumpPage(tester, walletFixture(id: 4));
      await tester.tap(find.byTooltip('Cancelar la invitación a Carlos'));
      await tester.pumpAndSettle();
      // «Volver» keeps it.
      await tester.tap(find.widgetWithText(FilledButton, 'Volver'));
      await tester.pumpAndSettle();
      verifyNever(() => families.remove(any(), any(), onReauth: any(named: 'onReauth')));

      await tester.tap(find.byTooltip('Cancelar la invitación a Carlos'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Cancelar invitación'));
      await tester.pumpAndSettle();
      expect(find.text('Confirma que eres tú'), findsNothing);
      expect(find.text('Cancelaste la invitación a Carlos'), findsOneWidget);
    });

    testWidgets('member leaves: confirmation, then back home', (tester) async {
      when(() => families.membersOf(4)).thenAnswer((_) async => [owner, luis]);
      when(() => families.leave(4)).thenAnswer((_) async {});
      await pumpPage(tester, walletFixture(id: 4, name: 'Casa', isOwner: false, memberCount: 1), userId: 'u2');
      expect(find.byTooltip('Quitar a María Quishpe'), findsNothing, reason: 'members never remove anyone');

      await tester.tap(find.byKey(const ValueKey('member-leave')));
      await tester.pumpAndSettle();
      expect(find.text('¿Salir de «Casa»?'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Salir'));
      await tester.pumpAndSettle();
      verify(() => families.leave(4)).called(1);
      expect(find.text('HOME'), findsOneWidget);
      expect(find.text('Saliste de «Casa»'), findsOneWidget);
    });

    testWidgets('leave error: stays with the message', (tester) async {
      when(() => families.membersOf(4)).thenAnswer((_) async => [owner, luis]);
      when(() => families.leave(4)).thenThrow(_network);
      await pumpPage(tester, walletFixture(id: 4, isOwner: false, memberCount: 1), userId: 'u2');
      await tester.tap(find.byKey(const ValueKey('member-leave')));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Salir'));
      await tester.pumpAndSettle();
      expect(find.text('No hay conexión.'), findsOneWidget);
      expect(find.text('HOME'), findsNothing);
    });

    testWidgets('owner never sees «Salir»; members see no remove buttons (COU-167)', (tester) async {
      when(() => families.membersOf(4)).thenAnswer((_) async => members);
      await pumpPage(tester, walletFixture(id: 4));
      expect(find.byKey(const ValueKey('member-leave')), findsNothing);
      expect(find.byTooltip('Quitar a María Quishpe (tú)'), findsNothing);
      expect(find.byKey(const ValueKey('member-remove-u1')), findsNothing, reason: 'not on the owner row');
      expect(find.byKey(const ValueKey('member-remove-u2')), findsOneWidget);
      final size = tester.getSize(find.byKey(const ValueKey('member-remove-u2')));
      expect(size.width >= 44 && size.height >= 44, isTrue, reason: 'touch target');
    });
  });
}
