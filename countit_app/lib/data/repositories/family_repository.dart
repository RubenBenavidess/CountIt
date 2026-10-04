import '../../app/errors/app_failure.dart';
import '../../app/errors/error_mapper.dart';
import '../dtos/family.dart';
import '../remote/api_client.dart';
import '../remote/realtime_watcher.dart';

/// Shared wallets (HU-21…HU-24 · COU-21): members, invitations and their
/// live changes. Reads come from `api.v_family_members` and
/// `get_my_invitations()`, writes are RPCs, and changes arrive through
/// Realtime on `public.families` (whose policy also requires a live session).
///
/// The backend decides every permission (owner vs member, plan, quotas);
/// the app only hides what a role cannot do (COU-167).
abstract interface class FamilyRepository {
  /// Live members of [walletId]: the owner (status `owner`), accepted members
  /// and, for the owner only, pending invitations still in time.
  Future<List<FamilyMember>> membersOf(int walletId);

  /// The caller's pending invitations that are still in time, newest first.
  Future<List<FamilyInvitation>> myInvitations();

  /// `invite_family_member` (owner): pending for 7 days. Errors: 404
  /// `wallet_not_found`/`user_not_found`, 403 `feature_not_in_plan`, 429
  /// `invitation_limit`, 400 `self_invitation`, 409 `already_member`,
  /// `invitation_pending`, `family_member_limit_exceeded`, `family_limit_exceeded`.
  Future<FamilyMember> invite(int walletId, String username);

  /// `respond_family_invitation`: 404 `invitation_not_found`, 409
  /// `invitation_expired`, 403 `feature_not_in_plan` (accepting only).
  Future<void> respond(int walletId, {required bool accept});

  /// `remove_family_member` (owner): removes an accepted member 🔒 or cancels
  /// a pending invitation (no password). [onReauth] asks for the password on
  /// `403 reauth_required`.
  Future<void> remove(int walletId, String userId, {ReauthPrompt? onReauth});

  /// `leave_family` (accepted member, no password).
  Future<void> leave(int walletId);

  /// Signals a change of the caller's own memberships (a new invitation, an
  /// expiry, being removed…) and every Realtime (re)join. Cancel to close.
  Stream<void> myMembershipChanges(String userId);

  /// Signals a change of the memberships of [walletId] the caller may see.
  Stream<void> walletMembershipChanges(int walletId);
}

class SupabaseFamilyRepository implements FamilyRepository {
  SupabaseFamilyRepository(this._api, this._realtime);

  final ApiClient _api;
  final RealtimeWatcher _realtime;

  static const view = 'v_family_members';
  static const table = 'families';

  @override
  Future<List<FamilyMember>> membersOf(int walletId) async {
    final rows = await _api.select(
      view,
      columns: 'wallet_id,wallet_name,user_id,username,display_name,status,is_owner,invited_at,expires_at,responded_at',
      query: (q) => q.eq('wallet_id', walletId).order('invited_at', ascending: true),
    );
    // Unknown statuses (a newer API) are skipped rather than mislabelled.
    final members = [
      for (final row in rows)
        if (row['is_owner'] == true || FamilyStatus.parse(row['status']) != null) FamilyMember.fromJson(row),
    ];
    return sortMembers(members);
  }

  @override
  Future<List<FamilyInvitation>> myInvitations() async {
    final rows = await _api.rpc<dynamic>('get_my_invitations');
    if (rows is! List) return const [];
    return List.unmodifiable([
      for (final row in rows.whereType<Map<dynamic, dynamic>>())
        FamilyInvitation.fromJson(Map<String, dynamic>.from(row)),
    ]);
  }

  @override
  Future<FamilyMember> invite(int walletId, String username) async {
    final json = await _api.rpc<dynamic>(
      'invite_family_member',
      params: {'p_wallet_id': walletId, 'p_username': username.trim()},
    );
    if (json is! Map) {
      throw const AppFailure(kind: FailureKind.server, message: ErrorMapper.genericMessage);
    }
    return FamilyMember.fromJson(Map<String, dynamic>.from(json));
  }

  @override
  Future<void> respond(int walletId, {required bool accept}) =>
      // A 403 here is about the owner's plan, not the caller's: no plans sheet.
      _api.rpc<dynamic>(
        'respond_family_invitation',
        params: {'p_wallet_id': walletId, 'p_accept': accept},
        planUpsell: false,
      );

  @override
  Future<void> remove(int walletId, String userId, {ReauthPrompt? onReauth}) => _api.rpc<dynamic>(
    'remove_family_member',
    params: {'p_wallet_id': walletId, 'p_user_id': userId},
    onReauth: onReauth,
  );

  @override
  Future<void> leave(int walletId) => _api.rpc<dynamic>('leave_family', params: {'p_wallet_id': walletId});

  @override
  Stream<void> myMembershipChanges(String userId) =>
      _realtime.watch(RealtimeTopic(table: table, column: 'user_id', value: userId));

  @override
  Stream<void> walletMembershipChanges(int walletId) =>
      _realtime.watch(RealtimeTopic(table: table, column: 'wallet_id', value: walletId));
}
