import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../app/errors/app_failure.dart';
import '../../../data/dtos/family.dart';
import '../../../data/repositories/family_repository.dart';
import '../../../shared/state/load_state.dart';

class FamilyMembersState extends Equatable {
  const FamilyMembersState({this.members = const LoadState.initial()});

  /// Live members, [sortMembers] order (owner, accepted, pending).
  final LoadState<List<FamilyMember>> members;

  FamilyMembersState copyWith({LoadState<List<FamilyMember>>? members}) =>
      FamilyMembersState(members: members ?? this.members);

  @override
  List<Object?> get props => [members];
}

/// HU-24 (COU-92): who shares one wallet. [watch] keeps the list live with
/// Realtime (an invitee accepts, an invitation expires, a member leaves).
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

  @override
  Future<void> close() async {
    await _changes?.cancel();
    return super.close();
  }
}
