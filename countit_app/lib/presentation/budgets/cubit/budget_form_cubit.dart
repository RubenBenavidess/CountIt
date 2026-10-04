import '../../../data/dtos/budget.dart';
import '../../../data/repositories/budget_repository.dart';
import '../../../shared/state/submit_cubit.dart';
import '../../../shared/utils/validators.dart';

/// One form for creating and editing budgets (HU-11/HU-13 · COU-223..COU-225).
///
/// Editing sends the whole form ([BudgetInput]): `update_budget` replaces the
/// budget and would clear an omitted icon. Editing never asks for the
/// password; only deleting does.
class BudgetFormCubit extends SubmitCubit {
  BudgetFormCubit(this._budgets, {required this.walletId, this.budgetId});

  final BudgetRepository _budgets;
  final int walletId;

  /// The budget being edited; null when creating.
  final int? budgetId;

  bool get isEditing => budgetId != null;

  Future<bool> save(BudgetInput input) => submit(() async {
    final id = budgetId;
    if (id == null) {
      await _budgets.create(walletId, input);
    } else {
      await _budgets.update(id, input);
    }
  });
}

/// Client-side mirror of `private.validate_budget_fields` (COU-223): the
/// server validates again, these only give immediate feedback. Each returns
/// null when valid, else the Spanish message.
abstract final class BudgetValidators {
  static const nameMax = 50;

  static String? name(String? value) => Validators.name(value, max: nameMax);

  /// The limit as typed («1.234,5»): the API amount rules.
  static String? limit(String? value) => Validators.amount(value);

  /// Cents of a valid [limit] text; null otherwise.
  static int? limitCents(String text) => Validators.amountCents(text);

  /// Only budgets without renewal have (and need) an end date, never before the start.
  static String? endDate(BudgetPeriod period, DateTime start, DateTime? end) {
    if (period.renews) return null;
    if (end == null) return Validators.requiredMessage;
    return end.isBefore(start) ? 'La fecha de fin no puede ser anterior a la de inicio' : null;
  }
}
