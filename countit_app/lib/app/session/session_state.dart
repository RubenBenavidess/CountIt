import 'package:equatable/equatable.dart';

import '../../data/dtos/profile.dart';

enum SessionStatus {
  /// Restoring the persisted session at start-up (splash).
  unknown,

  /// Signed in and the profile is loaded.
  authenticated,

  /// No session: login and the public auth screens only.
  unauthenticated,
}

class SessionState extends Equatable {
  const SessionState._(this.status, {this.profile, this.message});

  const SessionState.unknown() : this._(SessionStatus.unknown);

  const SessionState.authenticated(Profile profile) : this._(SessionStatus.authenticated, profile: profile);

  /// [message] explains an involuntary sign-out (e.g. the session was closed elsewhere).
  const SessionState.unauthenticated({String? message}) : this._(SessionStatus.unauthenticated, message: message);

  final SessionStatus status;
  final Profile? profile;
  final String? message;

  @override
  List<Object?> get props => [status, profile, message];
}
