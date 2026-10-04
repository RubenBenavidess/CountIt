import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../app/errors/app_failure.dart';
import '../../../data/dtos/bank.dart';
import '../../../data/repositories/bank_repository.dart';
import '../../../shared/state/load_state.dart';

/// Bank catalogue with search (COU-190). Typing is debounced and only the
/// answer to the latest term is shown.
class BankPickerCubit extends Cubit<LoadState<List<Bank>>> {
  BankPickerCubit(this._banks, {this.debounce = const Duration(milliseconds: 300)}) : super(const LoadState.initial());

  final BankRepository _banks;
  final Duration debounce;
  Timer? _timer;
  String _term = '';
  int _request = 0;

  /// Loads the list for the current term (first open and «Reintentar»).
  Future<void> load() async {
    final request = ++_request;
    emit(state.reloading());
    try {
      final banks = await _banks.list(search: _term);
      if (!isClosed && request == _request) emit(LoadState.success(banks));
    } on AppFailure catch (failure) {
      if (!isClosed && request == _request) emit(LoadState.failure(failure, previous: state.data));
    }
  }

  /// Called on every keystroke; the request goes out after [debounce].
  void search(String term) {
    final trimmed = term.trim();
    if (trimmed == _term) return;
    _term = trimmed;
    _timer?.cancel();
    _timer = Timer(debounce, () => unawaited(load()));
  }

  @override
  Future<void> close() {
    _timer?.cancel();
    return super.close();
  }
}
