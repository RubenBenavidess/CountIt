import 'package:clock/clock.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../app/errors/app_failure.dart';

enum SubmitStatus { idle, submitting, success, failure }

/// State of a form that sends one request: the button spinner, the error to
/// show (with per-field messages) and the 429 cooldown.
class SubmitState extends Equatable {
  const SubmitState({this.status = SubmitStatus.idle, this.failure, this.blockedUntil});

  final SubmitStatus status;
  final AppFailure? failure;

  /// Set from `Retry-After` on 429: the button counts down until then (COU-63).
  final DateTime? blockedUntil;

  bool get submitting => status == SubmitStatus.submitting;

  /// Server message for one field (`validationErrors`), e.g. `fieldError('username')`.
  String? fieldError(String field) => failure?.fieldErrors[field];

  @override
  List<Object?> get props => [status, failure, blockedUntil];
}

/// Template for form Cubits: subclasses validate their input and call [submit]
/// with the request; this class owns the state transitions, so every form
/// handles double taps, errors and rate limits the same way.
abstract class SubmitCubit extends Cubit<SubmitState> {
  SubmitCubit({DateTime Function()? now}) : _now = now ?? clock.now, super(const SubmitState());

  final DateTime Function() _now;

  /// Runs [request] unless one is in flight; [onSuccess] may emit nothing else.
  Future<bool> submit(Future<void> Function() request) async {
    if (state.submitting) return false;
    emit(SubmitState(status: SubmitStatus.submitting, blockedUntil: state.blockedUntil));
    try {
      await request();
      if (!isClosed) emit(const SubmitState(status: SubmitStatus.success));
      return true;
    } on AppFailure catch (failure) {
      if (!isClosed) {
        final wait = failure.retryAfter;
        emit(
          SubmitState(
            status: SubmitStatus.failure,
            failure: failure,
            blockedUntil: wait == null ? null : _now().add(wait),
          ),
        );
      }
      return false;
    }
  }

  /// Hides the last error once the user edits the form; keeps the cooldown.
  void clearFailure() {
    if (state.failure != null) emit(SubmitState(blockedUntil: state.blockedUntil));
  }

  /// A local validation problem (never reaches the backend).
  void fail(String message) => emit(
    SubmitState(
      status: SubmitStatus.failure,
      failure: AppFailure(kind: FailureKind.validation, message: message),
      blockedUntil: state.blockedUntil,
    ),
  );
}
