import 'package:flutter/material.dart';

import '../../../app/theme/tokens.dart';
import '../../../data/dtos/wallet.dart';
import '../../../shared/widgets/app_layout.dart';
import 'widgets/wallet_card.dart';

/// Wallet detail (HU-08). For now it shows the card the home list passed;
/// the full screen with actions lands with COU-195/COU-211.
class WalletDetailPage extends StatelessWidget {
  const WalletDetailPage({super.key, required this.walletId, this.initial});

  final int walletId;
  final Wallet? initial;

  @override
  Widget build(BuildContext context) {
    final wallet = initial;
    return Scaffold(
      appBar: AppTopBar(title: wallet?.name ?? 'Billetera'),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.screen),
        children: [if (wallet != null) WalletCard(wallet: wallet)],
      ),
    );
  }
}
