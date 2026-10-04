import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../app/errors/app_failure.dart';
import '../../../data/dtos/family.dart';
import '../../../data/remote/api_client.dart';
import '../../../data/repositories/family_repository.dart';
import '../../../shared/state/load_state.dart';

/// What removing a member, cancelling an invitation or leaving did.
enum MemberActionOutcome {
  /// An accepted member was removed (🔒).
  removed,

  /// A pending invitation was cancelled.
  cancelled,

  /// The caller left the family: the screen leaves the wallet.
  left,

  /// Already gone (404 `member_not_found`): it leaves the list.
  missing,

  /// Anything else: the list stays as it was.
  failed,
}

class MemberActionResult extends Equatable {
  const MemberActionResult(this.seq, this.outcome, {required this.name, this.failure});

  /// Grows with every result, so two equal outcomes in a row still notify.
  final int seq;
  final MemberActionOutcome outcome;

  /// The member's name, or the wallet's when leaving.
  final String name;
  final AppFailure? failure;

  @override
  List<Object?> get props => [seq, outcome, name, failure];
}

class FamilyMembersState extends Equatable {
  const FamilyMembersState({
    this.members = const LoadState.initial(),
    this.busy = const {},
    this.leaving = false,
    this.lastAction,
  });

  /// Live members, [sortMembers] order (owner, accepted, pending).
  final LoadState<List<FamilyMember>> members;

  /// Members (user ids) being removed: their buttons wait.
  final Set<String> busy;

  /// `leave_family` in flight.
  final bool leaving;
  final MemberActionResult? lastAction;

  FamilyMembersState copyWith({
    LoadState<List<FamilyMember>>? members,
    Set<String>? busy,
    bool? leaving,
    MemberActionResult? lastAction,
  }) => FamilyMembersState(
    members: members ?? this.members,
    busy: busy ?? this.busy,
    leaving: leaving ?? this.leaving,
    lastAction: lastAction ?? this.lastAction,
  );

  @override
  List<Object?> get props => [members, busy, leaving, lastAction];
}

/// HU-23/HU-24 (COU-92, COU-163, COU-165): who shares one wallet, removing
/// members (owner) and leaving (member). [watch] keeps the list live with
/// Realtime (an invitee accepts, an invitation expires, a member leaves).
///
/// The backend decides who may do what; the screen only hides what a role
/// cannot do (COU-167).
class FamilyMembersCubit extends Cubit<FamilyMembersState> {
  FamilyMembersCubit(this._families, {required this.walletId}) : super(const FamilyMembersState());

  final FamilyRepository _families;
  final int walletId;

  StreamSubscription<void>? _changes;
  Future<void>? _inFlight;
  bool _again = false;

  /// Loads (or reloads) the list; a call during a load runs once more after
  /// it, so a change signalled meanwhile is never lost.
  Future<void> load() {
    final current = _inFlight;
    if (current != null) {
      _again = true;
      return current;
    }
    return _inFlight = _loadLoop().whenComplete(() => _inFlight = null);
  }

  /// Loads once if nothing was loaded yet (the author filter of the wallet).
  Future<void> ensureLoaded() => state.members.data != null ? Future.value() : load();

  Future<void> _loadLoop() async {
    do {
      _again = false;
      await _load();
    } while (_again && !isClosed);
  }

  Future<void> _load() async {
    emit(state.copyWith(members: state.members.reloading()));
    try {
      final members = await _families.membersOf(walletId);
      if (!isClosed) emit(state.copyWith(members: LoadState.success(members)));
    } on AppFailure catch (failure) {
      if (!isClosed) emit(state.copyWith(members: LoadState.failure(failure, previous: state.members.data)));
    }
  }

  /// Loads and follows the wallet's memberships until the Cubit closes.
  void watch() {
    if (_changes != null) return;
    _changes = _families.walletMembershipChanges(walletId).listen((_) => unawaited(load()));
    unawaited(load());
  }

  /// `remove_family_member`: an accepted member needs the password
  /// ([onReauth] on `403 reauth_required`; closing the sheet changes
  /// nothing, silently); a pending invitation is cancelled without it.
  Future<void> remove(FamilyMember member, {ReauthPrompt? onReauth}) async {
    final id = member.userId;
    if (member.isOwner || state.busy.contains(id)) return;
    emit(state.copyWith(busy: {...state.busy, id}));
    try {
      await _families.remove(walletId, id, onReauth: member.isAccepted ? onReauth : null);
      if (isClosed) return;
      _finish(id, member.isPending ? MemberActionOutcome.cancelled : MemberActionOutcome.removed, member.name);
    } on AppFailure catch (failure) {
      if (isClosed) return;
      switch (failure.kind) {
        case FailureKind.notFound:
          _finish(id, MemberActionOutcome.missing, member.name, failure: failure);
        case FailureKind.reauthRequired:
          emit(state.copyWith(busy: {...state.busy}..remove(id)));
        default:
          _finish(id, MemberActionOutcome.failed, member.name, failure: failure, keep: true);
      }
    }
  }

  /// `leave_family` (accepted member, no password). Already out (404) counts as left.
  Future<void> leave({required String walletName}) async {
    if (state.leaving) return;
    emit(state.copyWith(leaving: true));
    try {
      await _families.leave(walletId);
      if (!isClosed) _left(walletName);
    } on AppFailure catch (failure) {
      if (isClosed) return;
      if (failure.kind == FailureKind.notFound) {
        _left(walletName);
      } else {
        emit(state.copyWith(leaving: false, lastAction: _result(MemberActionOutcome.failed, walletName, failure)));
      }
    }
  }

  void _left(String walletName) =>
      emit(state.copyWith(leaving: false, lastAction: _result(MemberActionOutcome.left, walletName, null)));

  MemberActionResult _result(MemberActionOutcome outcome, String name, AppFailure? failure) =>
      MemberActionResult((state.lastAction?.seq ?? 0) + 1, outcome, name: name, failure: failure);

  void _finish(String userId, MemberActionOutcome outcome, String name, {AppFailure? failure, bool keep = false}) {
    final current = state.members.data ?? const <FamilyMember>[];
    emit(
      state.copyWith(
        members: keep ? state.members : LoadState.success(List.unmodifiable(current.where((m) => m.userId != userId))),
        busy: {...state.busy}..remove(userId),
        lastAction: _result(outcome, name, failure),
      ),
    );
  }

  @override
  Future<void> close() async {
    await _changes?.cancel();
    return super.close();
  }
}
