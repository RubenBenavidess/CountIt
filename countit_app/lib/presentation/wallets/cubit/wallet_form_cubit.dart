import '../../../data/dtos/wallet.dart';
import '../../../data/repositories/wallet_repository.dart';
import '../../../shared/state/submit_cubit.dart';

/// One form for creating and editing wallets (HU-07/HU-09 · COU-193, COU-194).
///
/// Editing sends the whole form ([WalletInput]): `update_wallet` replaces the
/// wallet and would clear an omitted bank, description or type. Editing never
/// asks for the password; only deleting does.
class WalletFormCubit extends SubmitCubit {
  WalletFormCubit(this._wallets, {this.walletId});

  final WalletRepository _wallets;

  /// The wallet being edited; null when creating.
  final int? walletId;

  bool get isEditing => walletId != null;

  Future<bool> save(WalletInput input) => submit(() async {
    final id = walletId;
    if (id == null) {
      await _wallets.create(input);
    } else {
      await _wallets.update(id, input);
    }
  });
}
