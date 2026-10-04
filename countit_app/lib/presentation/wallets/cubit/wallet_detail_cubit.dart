import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../app/errors/app_failure.dart';
import '../../../data/dtos/wallet.dart';
import '../../../data/remote/api_client.dart';
import '../../../data/repositories/wallet_repository.dart';
import '../../../shared/state/load_state.dart';

/// How the detail screen ends on its own.
enum WalletDetailExit {
  /// Missing, someone else's or deleted elsewhere (`wallet_not_found`).
  notFound,

  /// Deleted from this screen (or it was already deleted: 404 on delete).
  deleted,
}

class WalletDetailState extends Equatable {
  const WalletDetailState({required this.wallet, this.deleting = false, this.actionFailure, this.exit});

  final LoadState<Wallet> wallet;

  /// `delete_wallet` in flight (the button shows a spinner).
  final bool deleting;

  /// Error of the last action (shown in a snackbar); loading errors live in [wallet].
  final AppFailure? actionFailure;

  /// Set once: the view leaves the screen with the matching message.
  final WalletDetailExit? exit;

  WalletDetailState copyWith({
    LoadState<Wallet>? wallet,
    bool? deleting,
    AppFailure? actionFailure,
    WalletDetailExit? exit,
  }) => WalletDetailState(
    wallet: wallet ?? this.wallet,
    deleting: deleting ?? this.deleting,
    actionFailure: actionFailure,
    exit: exit ?? this.exit,
  );

  @override
  List<Object?> get props => [wallet, deleting, actionFailure, exit];
}

/// HU-08/HU-10: fresh data of one wallet and its deletion (COU-211, COU-212).
class WalletDetailCubit extends Cubit<WalletDetailState> {
  WalletDetailCubit(this._wallets, {required this.walletId, Wallet? initial})
    : super(
        WalletDetailState(
          // The card the home list passed is shown at once while reloading.
          wallet: initial == null ? const LoadState.initial() : LoadState.loading(previous: initial),
        ),
      );

  final WalletRepository _wallets;
  final int walletId;

  Future<void> load() async {
    emit(state.copyWith(wallet: state.wallet.reloading()));
    try {
      final wallet = await _wallets.getById(walletId);
      if (!isClosed) emit(state.copyWith(wallet: LoadState.success(wallet)));
    } on AppFailure catch (failure) {
      if (isClosed) return;
      if (failure.kind == FailureKind.notFound) {
        emit(state.copyWith(wallet: LoadState.failure(failure), exit: WalletDetailExit.notFound));
      } else {
        emit(state.copyWith(wallet: LoadState.failure(failure, previous: state.wallet.data)));
      }
    }
  }

  /// `delete_wallet` 🔒. [onReauth] asks for the password on `403
  /// reauth_required`; cancelling it leaves everything as it was, silently.
  Future<void> delete({ReauthPrompt? onReauth}) async {
    if (state.deleting) return;
    emit(state.copyWith(deleting: true));
    try {
      await _wallets.delete(walletId, onReauth: onReauth);
      if (!isClosed) emit(state.copyWith(deleting: false, exit: WalletDetailExit.deleted));
    } on AppFailure catch (failure) {
      if (isClosed) return;
      switch (failure.kind) {
        // Deleted meanwhile (another device): the goal is met.
        case FailureKind.notFound:
          emit(state.copyWith(deleting: false, exit: WalletDetailExit.deleted));
        // The user closed the password sheet: nothing happened, nothing to report.
        case FailureKind.reauthRequired:
          emit(state.copyWith(deleting: false));
        default:
          emit(state.copyWith(deleting: false, actionFailure: failure));
      }
    }
  }
}
