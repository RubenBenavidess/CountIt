import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../app/errors/app_failure.dart';
import '../../../data/dtos/transaction.dart';
import '../../../data/repositories/transaction_repository.dart';
import '../../../shared/state/delete_cubit.dart';

class TransactionDetailState extends Equatable {
  const TransactionDetailState({
    required this.transaction,
    this.reloading = false,
    this.changed = false,
    this.missing = false,
  });

  final Transaction transaction;
  final bool reloading;

  /// Edited from this screen: the wallet must reload when leaving.
  final bool changed;

  /// Deleted elsewhere (404 on reload): the screen leaves.
  final bool missing;

  TransactionDetailState copyWith({Transaction? transaction, bool? reloading, bool? changed, bool? missing}) =>
      TransactionDetailState(
        transaction: transaction ?? this.transaction,
        reloading: reloading ?? this.reloading,
        changed: changed ?? this.changed,
        missing: missing ?? this.missing,
      );

  @override
  List<Object?> get props => [transaction, reloading, changed, missing];
}

/// HU-17/HU-18: one transaction as the wallet listed it, refreshed after an
/// edit (COU-241). A failed refresh keeps what is on screen.
class TransactionDetailCubit extends Cubit<TransactionDetailState> {
  TransactionDetailCubit(this._transactions, {required Transaction initial})
    : super(TransactionDetailState(transaction: initial));

  final TransactionRepository _transactions;

  /// After a save in the edit form: fresh data and «changed» for the wallet.
  Future<void> edited() async {
    emit(state.copyWith(reloading: true, changed: true));
    try {
      final fresh = await _transactions.getById(state.transaction.transactionId);
      if (!isClosed) emit(state.copyWith(transaction: fresh, reloading: false));
    } on AppFailure catch (failure) {
      if (isClosed) return;
      emit(state.copyWith(reloading: false, missing: failure.kind == FailureKind.notFound));
    }
  }
}

/// HU-19: `delete_transaction` 🔒 from the detail screen (COU-240).
class TransactionDeleteCubit extends DeleteCubit {
  TransactionDeleteCubit(TransactionRepository transactions, {required int transactionId})
    : super(({onReauth}) => transactions.delete(transactionId, onReauth: onReauth));
}
