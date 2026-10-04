import '../../../data/repositories/family_repository.dart';
import '../../../shared/state/submit_cubit.dart';

/// HU-21 (COU-90, COU-157): the owner invites a user to [walletId] by
/// username. The backend checks the plan, the quotas, the daily limit and
/// who may be invited; the form only mirrors the username format.
class InviteMemberCubit extends SubmitCubit {
  InviteMemberCubit(this._families, {required this.walletId});

  final FamilyRepository _families;
  final int walletId;

  Future<bool> invite(String username) => submit(() => _families.invite(walletId, username.trim()));
}
