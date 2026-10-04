import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../app/errors/app_failure.dart';

enum DeleteStatus { idle, deleting, deleted, failure }

class DeleteState extends Equatable {
  const DeleteState({this.status = DeleteStatus.idle, this.failure});

  final DeleteStatus status;

  /// Set with [DeleteStatus.failure]: shown in a snackbar.
  final AppFailure? failure;

  bool get deleting => status == DeleteStatus.deleting;

  @override
  List<Object?> get props => [status, failure];
}

/// A destructive call that may need the password (`403 reauth_required`):
/// [onReauth] asks for it and the call is retried once (`ApiClient.run`).
typedef DeleteRequest = Future<void> Function({Future<bool> Function()? onReauth});

/// Deleting one record from its screen (budget, transaction…), kept apart
/// from the form's submit state so saving and deleting never mix errors.
class DeleteCubit extends Cubit<DeleteState> {
  DeleteCubit(this._request) : super(const DeleteState());

  final DeleteRequest _request;

  /// Cancelling the password sheet leaves everything as it was, silently; a
  /// 404 means it was already deleted (another device or member).
  Future<void> delete({Future<bool> Function()? onReauth}) async {
    if (state.deleting || state.status == DeleteStatus.deleted) return;
    emit(const DeleteState(status: DeleteStatus.deleting));
    try {
      await _request(onReauth: onReauth);
      if (!isClosed) emit(const DeleteState(status: DeleteStatus.deleted));
    } on AppFailure catch (failure) {
      if (isClosed) return;
      switch (failure.kind) {
        case FailureKind.notFound:
          emit(const DeleteState(status: DeleteStatus.deleted));
        case FailureKind.reauthRequired:
          emit(const DeleteState());
        default:
          emit(DeleteState(status: DeleteStatus.failure, failure: failure));
      }
    }
  }
}
