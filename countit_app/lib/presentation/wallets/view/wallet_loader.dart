import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../data/dtos/wallet.dart';
import '../../../data/repositories/wallet_repository.dart';
import '../../../shared/state/load_state.dart';
import '../../../shared/widgets/app_feedback.dart';
import '../../../shared/widgets/app_layout.dart';
import '../cubit/wallet_detail_cubit.dart';

/// Builds a wallet sub-screen opened without the wallet in hand (a
/// notification or push leads straight to it): loads it first, with loading
/// and error states. A missing, foreign or deleted wallet shows the API's
/// «Billetera no encontrada» and never builds the screen.
class WalletLoader extends StatelessWidget {
  const WalletLoader({super.key, required this.walletId, required this.title, required this.builder});

  final int walletId;

  /// Title of the bar while loading or failing.
  final String title;
  final Widget Function(Wallet wallet) builder;

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) => WalletDetailCubit(context.read<WalletRepository>(), walletId: walletId)..load(),
      child: BlocBuilder<WalletDetailCubit, WalletDetailState>(
        buildWhen: (previous, current) => previous.wallet != current.wallet,
        builder: (context, state) {
          final wallet = state.wallet.data;
          if (wallet != null && state.wallet.status != LoadStatus.failure) return builder(wallet);
          return Scaffold(
            appBar: AppTopBar(title: title),
            body: state.wallet.status == LoadStatus.failure
                ? ErrorView.failure(state.wallet.failure!, onRetry: context.read<WalletDetailCubit>().load)
                : const LoadingView(),
          );
        },
      ),
    );
  }
}
