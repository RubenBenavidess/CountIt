import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:countit_app/app/errors/app_failure.dart';
import 'package:countit_app/data/dtos/family.dart';
import 'package:countit_app/data/dtos/wallet.dart';
import 'package:countit_app/presentation/families/cubit/family_members_cubit.dart';
import 'package:countit_app/presentation/families/view/family_members_page.dart';
import 'package:countit_app/shared/state/load_state.dart';
import 'package:countit_app/shared/utils/dates.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../../helpers/family_fixtures.dart';
import '../../helpers/mocks.dart';
import '../../helpers/pump_app.dart';
import '../../helpers/wallet_fixtures.dart';

const _network = AppFailure(kind: FailureKind.network, message: 'No hay conexión.');

void main() {
  late MockFamilyRepository families;
  late StreamController<void> changes;

  setUpAll(Dates.init);

  setUp(() {
    families = MockFamilyRepository();
    changes = StreamController<void>.broadcast();
    when(() => families.walletMembershipChanges(4)).thenAnswer((_) => changes.stream);
  });

  tearDown(() => changes.close());

  final members = [ownerFixture(), memberFixture()];

  group('FamilyMembersCubit (COU-92)', () {
    blocTest<FamilyMembersCubit, FamilyMembersState>(
      'loads the members of its wallet',
      setUp: () => when(() => families.membersOf(4)).thenAnswer((_) async => members),
      build: () => FamilyMembersCubit(families, walletId: 4),
      act: (cubit) => cubit.load(),
      expect: () => [
        const FamilyMembersState(members: LoadState.loading()),
        FamilyMembersState(members: LoadState.success(members)),
      ],
    );

    blocTest<FamilyMembersCubit, FamilyMembersState>(
      'a failed reload keeps the list',
      setUp: () => when(() => families.membersOf(4)).thenThrow(_network),
      build: () => FamilyMembersCubit(families, walletId: 4),
      seed: () => FamilyMembersState(members: LoadState.success(members)),
      act: (cubit) => cubit.load(),
      expect: () => [
        FamilyMembersState(members: LoadState.loading(previous: members)),
        FamilyMembersState(members: LoadState.failure(_network, previous: members)),
      ],
    );

    test('watch: every Realtime signal reloads; close cancels the subscription', () async {
      when(() => families.membersOf(4)).thenAnswer((_) async => members);
      final cubit = FamilyMembersCubit(families, walletId: 4)..watch();
      await Future<void>.delayed(Duration.zero);
      expect(changes.hasListener, isTrue);
      verify(() => families.membersOf(4)).called(1);

      changes.add(null);
      await Future<void>.delayed(Duration.zero);
      verify(() => families.membersOf(4)).called(1);

      await cubit.close();
      expect(changes.hasListener, isFalse);
    });

    test('signals during a load coalesce into one more load', () async {
      final gate = Completer<List<FamilyMember>>();
      var calls = 0;
      when(() => families.membersOf(4)).thenAnswer((_) {
        calls++;
        return calls == 1 ? gate.future : Future.value(members);
      });
      final cubit = FamilyMembersCubit(families, walletId: 4);
      final first = cubit.load();
      unawaited(cubit.load());
      unawaited(cubit.load());
      gate.complete(const []);
      await first;
      expect(calls, 2);
      expect(cubit.state.members.data, members);
      await cubit.close();
    });

    test('ensureLoaded loads only once', () async {
      when(() => families.membersOf(4)).thenAnswer((_) async => members);
      final cubit = FamilyMembersCubit(families, walletId: 4);
      await cubit.ensureLoaded();
      await cubit.ensureLoaded();
      verify(() => families.membersOf(4)).called(1);
      await cubit.close();
    });
  });

  group('FamilyMembersPage (COU-92)', () {
    Future<void> pumpPage(WidgetTester tester, Wallet wallet, {String userId = 'u1'}) async {
      tester.view.physicalSize = const Size(420, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final session = await signedIn(familyProfile(userId: userId));
      await tester.pumpApp(
        FamilyMembersPage(wallet: wallet),
        families: families,
        session: session,
      );
      await tester.pumpAndSettle();
    }

    testWidgets('owner: owner, members and pending invitations with their expiry', (tester) async {
      when(() => families.membersOf(4)).thenAnswer(
        (_) async => [
          ownerFixture(),
          memberFixture(),
          memberFixture(userId: 'u3', username: 'carlos_q', displayName: 'Carlos', status: FamilyStatus.pending),
        ],
      );
      await pumpPage(tester, walletFixture(id: 4, name: 'Casa', memberCount: 1));

      expect(find.text('María Quishpe (tú)'), findsOneWidget);
      expect(find.text('Dueño'), findsOneWidget);
      expect(find.text('Luis Andrade'), findsOneWidget);
      expect(find.text('Miembro'), findsOneWidget);
      expect(find.text('Pendiente'), findsOneWidget);
      expect(find.text('@carlos_q · Vence el 8 oct 2026'), findsOneWidget);
      expect(find.bySemanticsLabel(RegExp('^Carlos, Pendiente, @carlos_q, Vence el 8 oct 2026')), findsOneWidget);
    });

    testWidgets('owner without members: invitation hint', (tester) async {
      when(() => families.membersOf(4)).thenAnswer((_) async => const []);
      await pumpPage(tester, walletFixture(id: 4));
      expect(find.text('Solo tú usas esta billetera'), findsOneWidget);
    });

    testWidgets('member: sees the owner; losing access shows it', (tester) async {
      final wallet = walletFixture(id: 4, isOwner: false, ownerName: 'María Quishpe', memberCount: 1);
      when(() => families.membersOf(4)).thenAnswer((_) async => [ownerFixture(), memberFixture()]);
      await pumpPage(tester, wallet, userId: 'u2');
      expect(find.textContaining('«Ahorros» es de María Quishpe'), findsOneWidget);
      expect(find.text('Luis Andrade (tú)'), findsOneWidget);

      // Realtime: the owner removed this member → the view no longer lists them.
      when(() => families.membersOf(4)).thenAnswer((_) async => const []);
      changes.add(null);
      await tester.pumpAndSettle();
      expect(find.text('Ya no compartes esta billetera'), findsOneWidget);
    });

    testWidgets('live: an invitee who accepts appears without reloading by hand', (tester) async {
      when(() => families.membersOf(4))
          .thenAnswer((_) async => [ownerFixture(), memberFixture(status: FamilyStatus.pending)]);
      await pumpPage(tester, walletFixture(id: 4));
      expect(find.text('Pendiente'), findsOneWidget);

      when(() => families.membersOf(4)).thenAnswer((_) async => [ownerFixture(), memberFixture()]);
      changes.add(null);
      await tester.pumpAndSettle();
      expect(find.text('Pendiente'), findsNothing);
      expect(find.text('Miembro'), findsOneWidget);
    });

    testWidgets('load error with retry', (tester) async {
      when(() => families.membersOf(4)).thenThrow(_network);
      await pumpPage(tester, walletFixture(id: 4));
      expect(find.text('No hay conexión.'), findsOneWidget);

      when(() => families.membersOf(4)).thenAnswer((_) async => [ownerFixture(), memberFixture()]);
      await tester.tap(find.text('Reintentar'));
      await tester.pumpAndSettle();
      expect(find.text('Luis Andrade'), findsOneWidget);
    });
  });
}
