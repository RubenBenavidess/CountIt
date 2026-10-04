import '../../../data/repositories/budget_repository.dart';
import '../../../shared/state/delete_cubit.dart';

typedef BudgetDeleteState = DeleteState;
typedef BudgetDeleteStatus = DeleteStatus;

/// HU-14: deleting a budget from its edit screen (COU-226), `delete_budget` 🔒.
class BudgetDeleteCubit extends DeleteCubit {
  BudgetDeleteCubit(BudgetRepository budgets, {required this.budgetId})
    : super(({onReauth}) => budgets.delete(budgetId, onReauth: onReauth));

  final int budgetId;
}
