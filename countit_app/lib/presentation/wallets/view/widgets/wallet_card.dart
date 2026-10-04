import 'package:flutter/material.dart';

import '../../../../app/theme/app_theme.dart';
import '../../../../app/theme/tokens.dart';
import '../../../../data/dtos/wallet.dart';
import '../../../../shared/utils/money.dart';
import '../../../../shared/widgets/app_card.dart';
import 'wallet_type_icon.dart';

/// Wallet summary for the home list: name, bank and balance.
class WalletCard extends StatelessWidget {
  const WalletCard({super.key, required this.wallet, this.onTap});

  final Wallet wallet;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final color = wallet.bankColor == null ? AppColors.defaultWallet : Color(wallet.bankColor!);
    return AppCard(
      onTap: onTap,
      semanticLabel: '${wallet.name}, saldo ${Money.format(wallet.balance)}',
      child: Row(
        spacing: AppSpacing.md,
        children: [
          IconTile(wallet.type.icon, color: color),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(wallet.name, style: AppTypography.h2, maxLines: 1, overflow: TextOverflow.ellipsis),
                Text(
                  wallet.bankName ?? 'Sin banco',
                  style: AppTypography.caption.copyWith(color: palette.muted),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          Text(
            Money.format(wallet.balance),
            style: AppTypography.money.copyWith(fontSize: 17, color: wallet.balanceCents < 0 ? palette.expense : null),
          ),
        ],
      ),
    );
  }
}
