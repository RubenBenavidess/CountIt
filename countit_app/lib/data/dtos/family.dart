import 'package:equatable/equatable.dart';

import 'json_parsing.dart';

/// `public.family_member_status` plus the `owner` row that `v_family_members`
/// adds for the wallet owner (who has no row in `families`).
///
/// The view only returns live rows (owner, accepted, pending in time); the
/// other states come back from the write RPCs and Realtime (history).
enum FamilyStatus {
  owner('owner', 'Dueño'),
  accepted('accepted', 'Miembro'),
  pending('pending', 'Invitación pendiente'),
  declined('declined', 'Rechazó la invitación'),
  removed('removed', 'Quitado'),
  left('left', 'Salió'),
  expired('expired', 'Invitación vencida');

  const FamilyStatus(this.apiValue, this.label);

  final String apiValue;

  /// Spanish label of the badge.
  final String label;

  /// Owner, accepted member or invitation still in time: shown in the list.
  bool get isLive => this == owner || this == accepted || this == pending;

  /// Null for a missing or unknown value (a newer API): the row is skipped.
  static FamilyStatus? parse(Object? value) {
    for (final status in values) {
      if (status.apiValue == value) return status;
    }
    return null;
  }
}

/// A row of `api.v_family_members` (HU-24) or the membership a family RPC
/// returns (`invite_family_member`, `remove_family_member`, …).
///
/// Only what the view exposes: username and display name, never e-mails.
class FamilyMember extends Equatable {
  const FamilyMember({
    required this.walletId,
    required this.userId,
    required this.username,
    required this.status,
    this.walletName,
    this.displayName,
    this.invitedAt,
    this.expiresAt,
    this.respondedAt,
  });

  factory FamilyMember.fromJson(Map<String, dynamic> json) => FamilyMember(
    walletId: (json['wallet_id'] as num).toInt(),
    walletName: json['wallet_name'] as String?,
    userId: json['user_id'] as String,
    username: (json['username'] as String?) ?? '',
    displayName: json['display_name'] as String?,
    // The view marks the owner both ways; the RPCs never return it.
    status: json['is_owner'] == true ? FamilyStatus.owner : FamilyStatus.parse(json['status']) ?? FamilyStatus.pending,
    invitedAt: parseTimestamp(json['invited_at']),
    expiresAt: parseTimestamp(json['expires_at']),
    respondedAt: parseTimestamp(json['responded_at']),
  );

  final int walletId;
  final String? walletName;
  final String userId;
  final String username;

  /// First and last name (or the username when the view has nothing else).
  final String? displayName;
  final FamilyStatus status;
  final DateTime? invitedAt;

  /// When a pending invitation stops being valid (7 days after [invitedAt]).
  final DateTime? expiresAt;
  final DateTime? respondedAt;

  bool get isOwner => status == FamilyStatus.owner;
  bool get isPending => status == FamilyStatus.pending;
  bool get isAccepted => status == FamilyStatus.accepted;

  /// Name to show: the display name, else the username.
  String get name {
    final display = displayName?.trim();
    return display == null || display.isEmpty ? username : display;
  }

  @override
  List<Object?> get props => [
    walletId,
    walletName,
    userId,
    username,
    displayName,
    status,
    invitedAt,
    expiresAt,
    respondedAt,
  ];
}

/// Owner first, then accepted members, then pending invitations; by name
/// inside each group (stable for equal names through the user id).
List<FamilyMember> sortMembers(Iterable<FamilyMember> members) {
  int rank(FamilyMember m) => switch (m.status) {
    FamilyStatus.owner => 0,
    FamilyStatus.accepted => 1,
    FamilyStatus.pending => 2,
    _ => 3,
  };
  final sorted = members.toList()
    ..sort((a, b) {
      final byRank = rank(a).compareTo(rank(b));
      if (byRank != 0) return byRank;
      final byName = a.name.toLowerCase().compareTo(b.name.toLowerCase());
      return byName != 0 ? byName : a.userId.compareTo(b.userId);
    });
  return List.unmodifiable(sorted);
}

/// A row of `get_my_invitations()` (HU-24): a pending invitation of the
/// caller that is still in time, with the owner's username and name.
class FamilyInvitation extends Equatable {
  const FamilyInvitation({
    required this.walletId,
    required this.walletName,
    required this.ownerUsername,
    this.ownerName,
    this.invitedAt,
    this.expiresAt,
  });

  factory FamilyInvitation.fromJson(Map<String, dynamic> json) => FamilyInvitation(
    walletId: (json['wallet_id'] as num).toInt(),
    walletName: (json['wallet_name'] as String?) ?? '',
    ownerUsername: (json['owner_username'] as String?) ?? '',
    ownerName: json['owner_name'] as String?,
    invitedAt: parseTimestamp(json['invited_at']),
    expiresAt: parseTimestamp(json['expires_at']),
  );

  final int walletId;
  final String walletName;
  final String ownerUsername;
  final String? ownerName;
  final DateTime? invitedAt;
  final DateTime? expiresAt;

  /// Who invited: the owner's name, else the username.
  String get owner {
    final name = ownerName?.trim();
    return name == null || name.isEmpty ? ownerUsername : name;
  }

  @override
  List<Object?> get props => [walletId, walletName, ownerUsername, ownerName, invitedAt, expiresAt];
}
