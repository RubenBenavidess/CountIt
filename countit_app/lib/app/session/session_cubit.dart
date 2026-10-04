import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';

import '../../data/repositories/auth_repository.dart';
import '../../data/repositories/profile_repository.dart';
import '../errors/app_failure.dart';
import 'session_state.dart';

/// Owns "who is signed in": restores the session at start-up, loads the
/// profile (role, plan, limits) and signs out when the backend says the
/// session is gone (COU-57).
class SessionCubit extends Cubit<SessionState> {
  SessionCubit({required this._auth, required this._profiles}) : super(const SessionState.unknown()) {
    _subscription = _auth.sessionChanges.listen(_onSessionChanged);
  }

  final AuthRepository _auth;
  final ProfileRepository _profiles;
  late final StreamSubscription<SessionChange> _subscription;

  /// Decides the first route: profile when a session was restored, else login.
  Future<void> restore() async {
    if (!_auth.hasSession) {
      emit(const SessionState.unauthenticated());
      return;
    }
    await refreshProfile();
  }

  /// Reloads `get_my_profile` (after login, plan or profile changes).
  Future<void> refreshProfile() async {
    try {
      emit(SessionState.authenticated(await _profiles.fetchMyProfile()));
    } on AppFailure catch (failure) {
      if (failure.endsSession) {
        await sessionEnded(failure);
      } else if (state.status == SessionStatus.unknown) {
        // Offline or server error at start-up: do not trap the user on the splash.
        emit(SessionState.unauthenticated(message: failure.message));
      }
    }
  }

  /// Wired to [ApiClient.onSessionEnded]: any 401 signs the device out.
  Future<void> sessionEnded(AppFailure failure) async {
    if (state.status == SessionStatus.unauthenticated) return;
    emit(SessionState.unauthenticated(message: failure.message));
    try {
      await _auth.signOut();
    } on AppFailure {
      // The server already considers the session closed; local cleanup is enough.
    }
  }

  Future<void> signOut() async {
    try {
      await _auth.signOut();
    } on AppFailure {
      // Sign-out must always succeed locally.
    }
    emit(const SessionState.unauthenticated());
  }

  /// The new password was saved with the recovery session: enter the app
  /// (design «Guardar y entrar»).
  Future<void> recoveryCompleted() => refreshProfile();

  void _onSessionChanged(SessionChange change) {
    switch (change) {
      case SessionChange.passwordRecovery:
        emit(const SessionState.passwordRecovery());
      case SessionChange.signedIn:
        // A recovery session must not open the app before the new password is set.
        if (state.status != SessionStatus.authenticated && state.status != SessionStatus.passwordRecovery) {
          unawaited(refreshProfile());
        }
      case SessionChange.signedOut:
        if (state.status != SessionStatus.unauthenticated && state.status != SessionStatus.unknown) {
          emit(const SessionState.unauthenticated());
        }
      case SessionChange.updated:
        break;
    }
  }

  @override
  Future<void> close() async {
    await _subscription.cancel();
    return super.close();
  }
}
