import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../app/errors/app_failure.dart';
import '../../../data/dtos/wallet.dart';
import '../../../data/repositories/wallet_repository.dart';
import '../../../shared/state/load_state.dart';

/// HU-08: the wallets of the home screen (COU-188).
///
/// [load] keeps the previous list while reloading and after a failure, so a
/// network error never wipes what the user was looking at.
class WalletsCubit extends Cubit<LoadState<List<Wallet>>> {
  WalletsCubit(this._wallets) : super(const LoadState.initial());

  final WalletRepository _wallets;
  Future<void>? _inFlight;

  /// Loads (or reloads) the list; concurrent calls share one request.
  Future<void> load() => _inFlight ??= _load().whenComplete(() => _inFlight = null);

  Future<void> _load() async {
    emit(state.reloading());
    try {
      final wallets = await _wallets.list();
      if (!isClosed) emit(LoadState.success(wallets));
    } on AppFailure catch (failure) {
      if (!isClosed) emit(LoadState.failure(failure, previous: state.data));
    }
  }
}

/// The home list split as the design shows it.
extension WalletGroups on List<Wallet> {
  List<Wallet> get own => where((w) => w.isOwner).toList(growable: false);

  List<Wallet> get sharedWithMe => where((w) => !w.isOwner).toList(growable: false);

  /// Sum of the balances of the caller's own wallets, in cents.
  int get ownBalanceCents => fold(0, (sum, w) => w.isOwner ? sum + w.balanceCents : sum);
}
