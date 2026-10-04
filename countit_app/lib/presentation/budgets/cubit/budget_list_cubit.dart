import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../app/errors/app_failure.dart';
import '../../../data/dtos/budget.dart';
import '../../../data/repositories/budget_repository.dart';
import '../../../shared/state/load_state.dart';

/// HU-12: the budgets of one wallet, shown in its detail screen (COU-220).
///
/// Like the wallet list, [load] keeps the previous budgets while reloading and
/// after a failure, so a network error never wipes what is on screen.
class BudgetListCubit extends Cubit<LoadState<List<Budget>>> {
  BudgetListCubit(this._budgets, {required this.walletId}) : super(const LoadState.initial());

  final BudgetRepository _budgets;
  final int walletId;
  Future<void>? _inFlight;

  /// Loads (or reloads) the list; concurrent calls share one request.
  Future<void> load() => _inFlight ??= _load().whenComplete(() => _inFlight = null);

  Future<void> _load() async {
    emit(state.reloading());
    try {
      final budgets = await _budgets.listByWallet(walletId);
      if (!isClosed) emit(LoadState.success(budgets));
    } on AppFailure catch (failure) {
      if (!isClosed) emit(LoadState.failure(failure, previous: state.data));
    }
  }
}
