import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../app/errors/app_failure.dart';
import '../../../data/remote/api_client.dart';
import '../../../data/repositories/budget_repository.dart';

enum BudgetDeleteStatus { idle, deleting, deleted, failure }

class BudgetDeleteState extends Equatable {
  const BudgetDeleteState({this.status = BudgetDeleteStatus.idle, this.failure});

  final BudgetDeleteStatus status;

  /// Set with [BudgetDeleteStatus.failure]: shown in a snackbar.
  final AppFailure? failure;

  bool get deleting => status == BudgetDeleteStatus.deleting;

  @override
  List<Object?> get props => [status, failure];
}

/// HU-14: deleting a budget from its edit screen (COU-226). Kept apart from
/// the form's [SubmitState] so saving and deleting never mix their errors.
class BudgetDeleteCubit extends Cubit<BudgetDeleteState> {
  BudgetDeleteCubit(this._budgets, {required this.budgetId}) : super(const BudgetDeleteState());

  final BudgetRepository _budgets;
  final int budgetId;

  /// `delete_budget` 🔒. [onReauth] asks for the password on `403
  /// reauth_required`; cancelling it leaves everything as it was, silently.
  Future<void> delete({ReauthPrompt? onReauth}) async {
    if (state.deleting || state.status == BudgetDeleteStatus.deleted) return;
    emit(const BudgetDeleteState(status: BudgetDeleteStatus.deleting));
    try {
      await _budgets.delete(budgetId, onReauth: onReauth);
      if (!isClosed) emit(const BudgetDeleteState(status: BudgetDeleteStatus.deleted));
    } on AppFailure catch (failure) {
      if (isClosed) return;
      switch (failure.kind) {
        // Deleted meanwhile (another device or member): the goal is met.
        case FailureKind.notFound:
          emit(const BudgetDeleteState(status: BudgetDeleteStatus.deleted));
        // The user closed the password sheet: nothing happened, nothing to report.
        case FailureKind.reauthRequired:
          emit(const BudgetDeleteState());
        default:
          emit(BudgetDeleteState(status: BudgetDeleteStatus.failure, failure: failure));
      }
    }
  }
}
