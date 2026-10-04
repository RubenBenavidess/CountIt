import 'package:countit_app/data/dtos/family.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/family_fixtures.dart';

void main() {
  group('FamilyMember.fromJson (v_family_members)', () {
    test('owner row: status owner, no dates', () {
      final owner = FamilyMember.fromJson(const {
        'wallet_id': 1,
        'wallet_name': 'Ahorros Pichincha',
        'user_id': 'u1',
        'username': 'demo_ana',
        'display_name': 'Ana Quishpe',
        'status': 'owner',
        'is_owner': true,
        'invited_at': null,
        'expires_at': null,
        'responded_at': null,
      });
      expect(owner.isOwner, isTrue);
      expect(owner.name, 'Ana Quishpe');
      expect(owner.walletName, 'Ahorros Pichincha');
      expect(owner.expiresAt, isNull);
    });

    test('pending invitation with its expiry', () {
      final member = FamilyMember.fromJson(const {
        'wallet_id': 5,
        'user_id': 'u3',
        'username': 'demo_carlos',
        'display_name': 'Carlos Quishpe',
        'status': 'pending',
        'is_owner': false,
        'invited_at': '2026-10-04T01:25:26.958054+00:00',
        'expires_at': '2026-10-11T01:25:26.958054+00:00',
      });
      expect(member.isPending, isTrue);
      expect(member.expiresAt, DateTime.parse('2026-10-11T01:25:26.958054+00:00'));
    });

    test('RPC result (family_member_json): no is_owner, history status', () {
      final member = FamilyMember.fromJson(const {
        'id': 7,
        'wallet_id': 4,
        'user_id': 'u2',
        'username': 'luis_a',
        'status': 'removed',
        'ended_at': '2026-10-04T10:00:00Z',
      });
      expect(member.status, FamilyStatus.removed);
      expect(member.status.isLive, isFalse);
      expect(member.name, 'luis_a', reason: 'no display name → username');
    });
  });

  test('FamilyStatus.parse: every API value, null for unknown ones', () {
    for (final status in FamilyStatus.values) {
      expect(FamilyStatus.parse(status.apiValue), status);
    }
    expect(FamilyStatus.parse('banned'), isNull);
    expect(FamilyStatus.parse(null), isNull);
  });

  test('sortMembers: owner, accepted, pending; by name inside each group', () {
    final sorted = sortMembers([
      memberFixture(userId: 'p', displayName: 'Ana', status: FamilyStatus.pending),
      memberFixture(userId: 'b', displayName: 'Zoe'),
      ownerFixture(),
      memberFixture(userId: 'a', displayName: 'beto'),
    ]);
    expect(sorted.map((m) => m.userId), ['u1', 'a', 'b', 'p']);
  });

  test('FamilyInvitation.fromJson (get_my_invitations) and owner fallback', () {
    final invitation = FamilyInvitation.fromJson(const {
      'wallet_id': 5,
      'wallet_name': 'Viaje Galápagos',
      'owner_username': 'demo_lucia',
      'owner_name': 'Lucía Mendoza',
      'invited_at': '2026-10-04T01:25:26.958054+00:00',
      'expires_at': '2026-10-11T01:25:26.958054+00:00',
    });
    expect(invitation.walletId, 5);
    expect(invitation.owner, 'Lucía Mendoza');
    expect(invitationFixture(ownerName: ' ').owner, 'lucia_m');
  });
}
