import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../app/errors/app_failure.dart';
import '../../../data/dtos/family.dart';
import '../../../data/repositories/family_repository.dart';
import '../../../shared/state/load_state.dart';

/// What answering an invitation did, for a one-off message.
enum InvitationOutcome {
  accepted,
  declined,

  /// 409 `invitation_expired`: it leaves the list.
  expired,

  /// 404 `invitation_not_found`: cancelled by the owner, or the wallet is gone.
  missing,

  /// Anything else (403 owner's plan without families, network…): it stays.
  failed,
}

class InvitationResponse extends Equatable {
  const InvitationResponse(this.seq, this.outcome, {required this.walletName, this.failure});

  /// Grows with every response, so two equal outcomes in a row still notify.
  final int seq;
  final InvitationOutcome outcome;
  final String walletName;
  final AppFailure? failure;

  @override
  List<Object?> get props => [seq, outcome, walletName, failure];
}

class InvitationsState extends Equatable {
  const InvitationsState({
    this.invitations = const LoadState.initial(),
    this.responding = const {},
    this.lastResponse,
    this.revision = 0,
  });

  /// Pending invitations still in time, newest first.
  final LoadState<List<FamilyInvitation>> invitations;

  /// Wallets whose invitation is being answered (their buttons wait).
  final Set<int> responding;
  final InvitationResponse? lastResponse;

  /// Grows whenever the caller's memberships may have changed (Realtime or
  /// an answer here): the home list reloads its wallets on it.
  final int revision;

  /// For the badge: 0 while unknown.
  int get pendingCount => invitations.data?.length ?? 0;

  InvitationsState copyWith({
    LoadState<List<FamilyInvitation>>? invitations,
    Set<int>? responding,
    InvitationResponse? lastResponse,
    int? revision,
  }) => InvitationsState(
    invitations: invitations ?? this.invitations,
    responding: responding ?? this.responding,
    lastResponse: lastResponse ?? this.lastResponse,
    revision: revision ?? this.revision,
  );

  @override
  List<Object?> get props => [invitations, responding, lastResponse, revision];
}

/// HU-22/HU-24 (COU-91, COU-159, COU-161): the signed-in user's pending
/// invitations, live with Realtime on `families`, and their answers.
///
/// One instance lives for the whole app; [setUser] follows the session:
/// signing out cancels the subscription (closing the Realtime channel) and
/// forgets the data, so nothing leaks to the next account.
class InvitationsCubit extends Cubit<InvitationsState> {
  InvitationsCubit(this._families) : super(const InvitationsState());

  final FamilyRepository _families;

  String? _userId;
  StreamSubscription<void>? _changes;
  Future<void>? _inFlight;
  bool _again = false;

  String? get userId => _userId;

  /// Starts following [userId]'s invitations, or stops with null.
  Future<void> setUser(String? userId) async {
    if (userId == _userId) return;
    _userId = userId;
    final old = _changes;
    _changes = null;
    await old?.cancel();
    if (isClosed) return;
    emit(InvitationsState(revision: state.revision + 1));
    if (userId == null) return;
    _changes = _families.myMembershipChanges(userId).listen((_) {
      if (isClosed) return;
      emit(state.copyWith(revision: state.revision + 1));
      unawaited(load());
    });
    unawaited(load());
  }

  /// Loads (or reloads) the list; a call during a load runs once more after it.
  Future<void> load() {
    if (_userId == null) return Future.value();
    final current = _inFlight;
    if (current != null) {
      _again = true;
      return current;
    }
    return _inFlight = _loadLoop().whenComplete(() => _inFlight = null);
  }

  Future<void> _loadLoop() async {
    do {
      _again = false;
      await _load();
    } while (_again && !isClosed && _userId != null);
  }

  Future<void> _load() async {
    final user = _userId;
    emit(state.copyWith(invitations: state.invitations.reloading()));
    try {
      final invitations = await _families.myInvitations();
      // A sign-out (or another account) meanwhile: drop the stale answer.
      if (!isClosed && user == _userId) emit(state.copyWith(invitations: LoadState.success(invitations)));
    } on AppFailure catch (failure) {
      if (!isClosed && user == _userId) {
        emit(state.copyWith(invitations: LoadState.failure(failure, previous: state.invitations.data)));
      }
    }
  }

  /// `respond_family_invitation`: accepting gives access to the wallet at
  /// once; declining is final (the owner may invite again).
  Future<void> respond(FamilyInvitation invitation, {required bool accept}) async {
    final id = invitation.walletId;
    if (state.responding.contains(id)) return;
    emit(state.copyWith(responding: {...state.responding, id}));
    try {
      await _families.respond(id, accept: accept);
      if (isClosed) return;
      _finish(invitation, accept ? InvitationOutcome.accepted : InvitationOutcome.declined, remove: true);
    } on AppFailure catch (failure) {
      if (isClosed) return;
      if (failure.key == 'invitation_expired') {
        _finish(invitation, InvitationOutcome.expired, remove: true, failure: failure);
      } else if (failure.kind == FailureKind.notFound) {
        _finish(invitation, InvitationOutcome.missing, remove: true, failure: failure);
      } else {
        _finish(invitation, InvitationOutcome.failed, remove: false, failure: failure);
      }
    }
  }

  void _finish(FamilyInvitation invitation, InvitationOutcome outcome, {required bool remove, AppFailure? failure}) {
    final current = state.invitations.data ?? const <FamilyInvitation>[];
    final responding = {...state.responding}..remove(invitation.walletId);
    emit(
      state.copyWith(
        invitations: remove
            ? LoadState.success(List.unmodifiable(current.where((i) => i.walletId != invitation.walletId)))
            : state.invitations,
        responding: responding,
        lastResponse: InvitationResponse(
          (state.lastResponse?.seq ?? 0) + 1,
          outcome,
          walletName: invitation.walletName,
          failure: failure,
        ),
        revision: remove ? state.revision + 1 : state.revision,
      ),
    );
  }

  @override
  Future<void> close() async {
    await _changes?.cancel();
    return super.close();
  }
}
