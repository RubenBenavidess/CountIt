import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../app/errors/app_failure.dart';
import '../../../data/dtos/bank.dart';
import '../../../data/repositories/admin_repository.dart';
import '../../../shared/state/load_state.dart';
import 'admin_failures.dart';

class AdminBanksState extends Equatable {
  const AdminBanksState({
    this.banks = const LoadState.initial(),
    this.search = '',
    this.toggling = const {},
    this.failure,
    this.revision = 0,
  });

  /// Every bank, active or not (admins see all in `v_banks`).
  final LoadState<List<Bank>> banks;

  /// Local filter by name (the catalogue is short).
  final String search;

  /// Banks whose activation is being changed.
  final Set<int> toggling;

  /// Last failure of an activation change, shown once.
  final AppFailure? failure;

  /// Bumped with each [failure] so the same error is shown again.
  final int revision;

  /// [banks] filtered by [search], computed per state (not in `build`).
  List<Bank> get visible {
    final all = banks.data ?? const <Bank>[];
    final term = search.toLowerCase();
    return term.isEmpty ? all : all.where((b) => b.name.toLowerCase().contains(term)).toList(growable: false);
  }

  AdminBanksState copyWith({
    LoadState<List<Bank>>? banks,
    String? search,
    Set<int>? toggling,
    AppFailure? Function()? failure,
    int? revision,
  }) => AdminBanksState(
    banks: banks ?? this.banks,
    search: search ?? this.search,
    toggling: toggling ?? this.toggling,
    failure: failure == null ? this.failure : failure(),
    revision: revision ?? this.revision,
  );

  @override
  List<Object?> get props => [banks, search, toggling, failure, revision];
}

/// Banks for admins (HU-27 · COU-205, COU-207): the whole catalogue, a
/// local filter and activation changes in place.
class AdminBanksCubit extends Cubit<AdminBanksState> {
  AdminBanksCubit(this._admin) : super(const AdminBanksState());

  final AdminRepository _admin;
  int _request = 0;

  Future<void> load() async {
    final request = ++_request;
    emit(state.copyWith(banks: state.banks.reloading()));
    try {
      final banks = await _admin.listBanks();
      if (!isClosed && request == _request) emit(state.copyWith(banks: LoadState.success(banks)));
    } on AppFailure catch (failure) {
      if (!isClosed && request == _request) {
        emit(state.copyWith(banks: LoadState.failure(adminFailure(failure), previous: state.banks.data)));
      }
    }
  }

  void search(String term) {
    final trimmed = term.trim();
    if (trimmed != state.search) emit(state.copyWith(search: trimmed));
  }

  /// A bank created or edited in the form: inserted or replaced, by name.
  void upsert(Bank bank) {
    final all = [...?state.banks.data];
    final index = all.indexWhere((b) => b.bankId == bank.bankId);
    if (index < 0) {
      all.add(bank);
    } else {
      all[index] = bank;
    }
    all.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    emit(state.copyWith(banks: LoadState.success(all)));
  }

  /// `admin_set_bank_active`: wallets that use the bank keep it either way.
  Future<bool> setActive(Bank bank, {required bool active}) async {
    if (state.toggling.contains(bank.bankId) || bank.isActive == active) return false;
    emit(state.copyWith(toggling: {...state.toggling, bank.bankId}, failure: () => null));
    try {
      final saved = await _admin.setBankActive(bank.bankId, active: active);
      if (isClosed) return true;
      emit(state.copyWith(toggling: {...state.toggling}..remove(bank.bankId)));
      upsert(saved);
      return true;
    } on AppFailure catch (failure) {
      if (isClosed) return false;
      emit(
        state.copyWith(
          toggling: {...state.toggling}..remove(bank.bankId),
          failure: () => adminFailure(failure),
          revision: state.revision + 1,
        ),
      );
      return false;
    }
  }
}
