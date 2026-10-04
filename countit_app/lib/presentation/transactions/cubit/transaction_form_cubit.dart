import '../../../data/dtos/budget.dart';
import '../../../data/dtos/transaction.dart';
import '../../../data/repositories/transaction_repository.dart';
import '../../../shared/state/submit_cubit.dart';
import '../../../shared/utils/validators.dart';

/// One form for registering and editing transactions (HU-15/HU-18 ·
/// COU-237..COU-239).
///
/// Editing sends the whole form ([TransactionInput]): `update_transaction`
/// replaces the row, and an omitted budget means «Sin presupuesto». Editing
/// never asks for the password; only deleting does.
class TransactionFormCubit extends SubmitCubit {
  TransactionFormCubit(this._transactions, {required this.walletId, this.transactionId});

  final TransactionRepository _transactions;
  final int walletId;

  /// The transaction being edited; null when registering a new one.
  final int? transactionId;

  bool get isEditing => transactionId != null;

  Future<bool> save(TransactionInput input) => submit(() async {
    final id = transactionId;
    if (id == null) {
      await _transactions.create(walletId, input);
    } else {
      await _transactions.update(id, input);
    }
  });
}

/// Client-side mirror of `private.validate_transaction_fields` and the
/// budget guard: the server validates again, these only give immediate
/// feedback. Each returns null when valid, else the Spanish message.
abstract final class TransactionValidators {
  static const nameMax = 100;

  static String? name(String? value) => Validators.name(value, max: nameMax);

  static String? amount(String? value) => Validators.amount(value);

  /// Never after the user's own calendar day (400 `future_date`): future
  /// movements are scheduled instead (F06).
  static String? date(DateTime day, {required DateTime today}) =>
      day.isAfter(today) ? 'Para fechas futuras programa la transacción' : null;

  /// A budget only takes transactions of its own type (400 `budget_type_mismatch`).
  static bool budgetAccepts(Budget budget, TransactionType type) => budget.type == type;
}
