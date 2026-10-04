import 'package:countit_app/app/session/session_cubit.dart';
import 'package:countit_app/data/dtos/family.dart';
import 'package:countit_app/data/dtos/profile.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'mocks.dart';

/// A member as `v_family_members` returns it.
FamilyMember memberFixture({
  String userId = 'u2',
  String username = 'luis_a',
  String? displayName = 'Luis Andrade',
  FamilyStatus status = FamilyStatus.accepted,
  int walletId = 4,
  DateTime? expiresAt,
}) => FamilyMember(
  walletId: walletId,
  walletName: 'Casa',
  userId: userId,
  username: username,
  displayName: displayName,
  status: status,
  invitedAt: DateTime.utc(2026, 10, 1, 15),
  expiresAt: expiresAt ?? (status == FamilyStatus.pending ? DateTime.utc(2026, 10, 8, 15) : null),
);

/// The owner row the view adds (`status = 'owner'`).
FamilyMember ownerFixture({String userId = 'u1', String name = 'María Quishpe', int walletId = 4}) => FamilyMember(
  walletId: walletId,
  userId: userId,
  username: 'maria_q',
  displayName: name,
  status: FamilyStatus.owner,
);

/// A row of `get_my_invitations()`.
FamilyInvitation invitationFixture({
  int walletId = 5,
  String walletName = 'Viaje Galápagos',
  String ownerUsername = 'lucia_m',
  String? ownerName = 'Lucía Mendoza',
}) => FamilyInvitation(
  walletId: walletId,
  walletName: walletName,
  ownerUsername: ownerUsername,
  ownerName: ownerName,
  invitedAt: DateTime.utc(2026, 10, 4, 1),
  expiresAt: DateTime.utc(2026, 10, 11, 1),
);

/// Profile of the signed-in user in family tests; [families] toggles the plan feature.
Profile familyProfile({String userId = 'u1', bool families = true}) => Profile(
  userId: userId,
  username: 'maria_q',
  email: 'maria@correo.ec',
  role: UserRole.user,
  timezone: 'America/Guayaquil',
  plan: UserPlan(
    planId: families ? 3 : 1,
    name: families ? 'Contador' : 'Regular',
    limits: {'family_feature': families ? 1 : 0, 'max_family_users': 3, 'max_families': 2},
  ),
);

/// A restored session signed in as [profile] (closed at tear-down).
Future<SessionCubit> signedIn(Profile profile) async {
  final auth = MockAuthRepository();
  final profiles = MockProfileRepository();
  when(() => auth.sessionChanges).thenAnswer((_) => const Stream.empty());
  when(() => auth.hasSession).thenReturn(true);
  when(profiles.fetchMyProfile).thenAnswer((_) async => profile);
  final session = SessionCubit(auth: auth, profiles: profiles);
  addTearDown(session.close);
  await session.restore();
  return session;
}
