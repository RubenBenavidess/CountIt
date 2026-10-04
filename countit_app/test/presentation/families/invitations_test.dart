import 'dart:async';

import 'package:countit_app/app/errors/app_failure.dart';
import 'package:countit_app/app/router/app_router.dart';
import 'package:countit_app/data/dtos/family.dart';
import 'package:countit_app/presentation/families/cubit/invitations_cubit.dart';
import 'package:countit_app/presentation/families/view/invitations_page.dart';
import 'package:countit_app/presentation/home/view/home_page.dart';
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

const _network = AppFailure(kind: FailureKind.network, message: 'No hay conexión.');
const _expired = AppFailure(
  kind: FailureKind.conflict,
  message: 'La invitación expiró. Pide una nueva al dueño',
  key: 'invitation_expired',
  status: 409,
);
const _ownerPlan = AppFailure(
  kind: FailureKind.featureNotInPlan,
  message: 'El plan del dueño ya no incluye familias',
  key: 'feature_not_in_plan',
  status: 403,
);
const _missing = AppFailure(
  kind: FailureKind.notFound,
  message: 'Invitación no encontrada',
  key: 'invitation_not_found',
  status: 404,
);

void main() {
  late MockFamilyRepository families;
  late StreamController<void> changes;

  setUpAll(Dates.init);

  setUp(() {
    families = noFamilies();
    changes = StreamController<void>.broadcast();
    when(() => families.myMembershipChanges('u1')).thenAnswer((_) => changes.stream);
  });

  tearDown(() => changes.close());

  final viaje = invitationFixture();
  final finca = invitationFixture(walletId: 6, walletName: 'Finca', ownerUsername: 'pepe_r', ownerName: null);

  Future<void> flush() => Future<void>.delayed(Duration.zero);

  group('InvitationsCubit (COU-159, COU-161)', () {
    test('follows the user: loads, reloads on every Realtime signal, stops on sign-out', () async {
      when(families.myInvitations).thenAnswer((_) async => [viaje]);
      final cubit = InvitationsCubit(families);
      addTearDown(cubit.close);

      await cubit.setUser('u1');
      await flush();
      expect(cubit.state.invitations.data, [viaje]);
      expect(cubit.state.pendingCount, 1);
      expect(changes.hasListener, isTrue);

      when(families.myInvitations).thenAnswer((_) async => [finca, viaje]);
      final revision = cubit.state.revision;
      changes.add(null);
      await flush();
      expect(cubit.state.pendingCount, 2);
      expect(cubit.state.revision, revision + 1, reason: 'home reloads its wallets');

      await cubit.setUser(null);
      expect(changes.hasListener, isFalse, reason: 'the Realtime channel closes');
      expect(cubit.state.invitations, const LoadState<List<FamilyInvitation>>.initial());
      expect(cubit.state.pendingCount, 0);
    });

    test('the same user twice does not resubscribe; another account starts clean', () async {
      when(families.myInvitations).thenAnswer((_) async => [viaje]);
      when(() => families.myMembershipChanges('u9')).thenAnswer((_) => const Stream.empty());
      final cubit = InvitationsCubit(families);
      addTearDown(cubit.close);
      await cubit.setUser('u1');
      await cubit.setUser('u1');
      verify(() => families.myMembershipChanges('u1')).called(1);

      final gate = Completer<List<FamilyInvitation>>();
      when(families.myInvitations).thenAnswer((_) => gate.future);
      await cubit.setUser('u9');
      expect(changes.hasListener, isFalse);
      await cubit.setUser(null);
      gate.complete([finca]);
      await flush();
      expect(cubit.state.invitations.data, isNull, reason: 'a late answer for a signed-out user is dropped');
    });

    test('close cancels the subscription', () async {
      when(families.myInvitations).thenAnswer((_) async => const []);
      final cubit = InvitationsCubit(families);
      await cubit.setUser('u1');
      await cubit.close();
      expect(changes.hasListener, isFalse);
    });

    Future<InvitationsCubit> loaded() async {
      when(families.myInvitations).thenAnswer((_) async => [viaje, finca]);
      final cubit = InvitationsCubit(families);
      addTearDown(cubit.close);
      await cubit.setUser('u1');
      await flush();
      return cubit;
    }

    test('accept: leaves the list, bumps the revision', () async {
      when(() => families.respond(5, accept: true)).thenAnswer((_) async {});
      final cubit = await loaded();
      final revision = cubit.state.revision;
      await cubit.respond(viaje, accept: true);
      expect(cubit.state.invitations.data, [finca]);
      expect(cubit.state.lastResponse?.outcome, InvitationOutcome.accepted);
      expect(cubit.state.revision, revision + 1);
      expect(cubit.state.responding, isEmpty);
    });

    test('decline: leaves the list', () async {
      when(() => families.respond(6, accept: false)).thenAnswer((_) async {});
      final cubit = await loaded();
      await cubit.respond(finca, accept: false);
      expect(cubit.state.invitations.data, [viaje]);
      expect(cubit.state.lastResponse?.outcome, InvitationOutcome.declined);
    });

    for (final (failure, outcome, removed) in [
      (_expired, InvitationOutcome.expired, true),
      (_missing, InvitationOutcome.missing, true),
      (_ownerPlan, InvitationOutcome.failed, false),
      (_network, InvitationOutcome.failed, false),
    ]) {
      test('${failure.key ?? 'network'}: ${outcome.name}, ${removed ? 'removed' : 'kept'}', () async {
        when(() => families.respond(5, accept: true)).thenThrow(failure);
        final cubit = await loaded();
        await cubit.respond(viaje, accept: true);
        expect(cubit.state.lastResponse?.outcome, outcome);
        expect(cubit.state.lastResponse?.failure, failure);
        expect(cubit.state.invitations.data!.contains(viaje), !removed);
      });
    }

    test('a double tap answers once', () async {
      final gate = Completer<void>();
      when(() => families.respond(5, accept: true)).thenAnswer((_) => gate.future);
      final cubit = await loaded();
      final first = cubit.respond(viaje, accept: true);
      await cubit.respond(viaje, accept: true);
      gate.complete();
      await first;
      verify(() => families.respond(5, accept: true)).called(1);
    });
  });

  group('InvitationsPage (COU-91, COU-161)', () {
    Future<InvitationsCubit> pumpPage(WidgetTester tester) async {
      tester.view.physicalSize = const Size(420, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final session = await signedIn(familyProfile());
      final cubit = InvitationsCubit(families);
      addTearDown(cubit.close);
      await cubit.setUser('u1');
      await tester.pumpApp(const InvitationsPage(), families: families, session: session, invitations: cubit);
      await tester.pumpAndSettle();
      return cubit;
    }

    testWidgets('wallet, owner and expiry; new invitations arrive live', (tester) async {
      when(families.myInvitations).thenAnswer((_) async => [viaje]);
      await pumpPage(tester);
      expect(find.text('Viaje Galápagos'), findsOneWidget);
      expect(find.text('Te invita Lucía Mendoza (@lucia_m)'), findsOneWidget);
      expect(find.text('Vence el 10 oct 2026'), findsOneWidget, reason: '01:00 UTC is the day before in Guayaquil');
      expect(
        find.bySemanticsLabel('Invitación a Viaje Galápagos, Te invita Lucía Mendoza (@lucia_m), Vence el 10 oct 2026'),
        findsOneWidget,
      );

      when(families.myInvitations).thenAnswer((_) async => [finca, viaje]);
      changes.add(null);
      await tester.pumpAndSettle();
      expect(find.text('Finca'), findsOneWidget);
      expect(find.text('Te invita pepe_r (@pepe_r)'), findsOneWidget);
    });

    testWidgets('accept: confirmation and the card leaves', (tester) async {
      when(families.myInvitations).thenAnswer((_) async => [viaje]);
      when(() => families.respond(5, accept: true)).thenAnswer((_) async {});
      await pumpPage(tester);
      await tester.tap(find.byKey(const ValueKey('invitation-accept-5')));
      await tester.pumpAndSettle();
      expect(find.text('Ahora compartes «Viaje Galápagos». La verás en «Compartidas conmigo».'), findsOneWidget);
      expect(find.text('No tienes invitaciones pendientes'), findsOneWidget);
    });

    testWidgets('decline asks first; cancelling sends nothing', (tester) async {
      when(families.myInvitations).thenAnswer((_) async => [viaje]);
      when(() => families.respond(5, accept: false)).thenAnswer((_) async {});
      await pumpPage(tester);

      await tester.tap(find.byKey(const ValueKey('invitation-decline-5')));
      await tester.pumpAndSettle();
      expect(find.text('¿Rechazar la invitación?'), findsOneWidget);
      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();
      verifyNever(() => families.respond(any(), accept: any(named: 'accept')));

      await tester.tap(find.byKey(const ValueKey('invitation-decline-5')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Rechazar').last);
      await tester.pumpAndSettle();
      expect(find.text('Rechazaste la invitación a «Viaje Galápagos»'), findsOneWidget);
      expect(find.text('Viaje Galápagos'), findsNothing);
    });

    testWidgets('expired: the backend message and the card leaves', (tester) async {
      when(families.myInvitations).thenAnswer((_) async => [viaje]);
      when(() => families.respond(5, accept: true)).thenThrow(_expired);
      await pumpPage(tester);
      await tester.tap(find.byKey(const ValueKey('invitation-accept-5')));
      await tester.pumpAndSettle();
      expect(find.text('La invitación expiró. Pide una nueva al dueño'), findsOneWidget);
      expect(find.byKey(const ValueKey('invitation-5')), findsNothing);
    });

    testWidgets('owner\'s plan without families: message, the invitation stays', (tester) async {
      when(families.myInvitations).thenAnswer((_) async => [viaje]);
      when(() => families.respond(5, accept: true)).thenThrow(_ownerPlan);
      await pumpPage(tester);
      await tester.tap(find.byKey(const ValueKey('invitation-accept-5')));
      await tester.pumpAndSettle();
      expect(find.text('El plan del dueño ya no incluye familias'), findsOneWidget);
      expect(find.byKey(const ValueKey('invitation-5')), findsOneWidget);
    });

    testWidgets('load error with retry', (tester) async {
      when(families.myInvitations).thenThrow(_network);
      await pumpPage(tester);
      expect(find.text('No hay conexión.'), findsOneWidget);
      when(families.myInvitations).thenAnswer((_) async => [viaje]);
      await tester.tap(find.text('Reintentar'));
      await tester.pumpAndSettle();
      expect(find.text('Viaje Galápagos'), findsOneWidget);
    });
  });

  group('home badge (COU-91, COU-159)', () {
    testWidgets('pending count on the app bar and the shared section; live; opens the list', (tester) async {
      tester.view.physicalSize = const Size(420, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final wallets = MockWalletRepository();
      when(wallets.list).thenAnswer((_) async => [walletFixture()]);
      when(families.myInvitations).thenAnswer((_) async => const []);
      final session = await signedIn(familyProfile());
      final cubit = InvitationsCubit(families);
      addTearDown(cubit.close);
      await cubit.setUser('u1');
      final router = GoRouter(
        initialLocation: AppRoutes.home,
        routes: [
          GoRoute(path: AppRoutes.home, builder: (context, state) => const HomePage()),
          GoRoute(path: AppRoutes.invitations, builder: (context, state) => const InvitationsPage()),
        ],
      );
      await tester.pumpApp(
        const SizedBox(),
        wallets: wallets,
        families: families,
        session: session,
        invitations: cubit,
        router: router,
      );
      await tester.pumpAndSettle();
      expect(find.byTooltip('Invitaciones'), findsOneWidget);
      expect(find.byKey(const ValueKey('home-pending-invitations')), findsNothing);
      clearInteractions(wallets);

      // Lucía invites us while the home is open.
      when(families.myInvitations).thenAnswer((_) async => [viaje]);
      changes.add(null);
      await tester.pumpAndSettle();
      expect(find.byTooltip('Invitaciones: 1 pendiente'), findsOneWidget);
      expect(find.text('Tienes 1 invitación pendiente'), findsOneWidget);
      verify(wallets.list).called(1);

      await tester.tap(find.byKey(const ValueKey('home-pending-invitations')));
      await tester.pumpAndSettle();
      expect(find.text('Viaje Galápagos'), findsOneWidget);
    });
  });
}
