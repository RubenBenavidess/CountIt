import 'package:flutter/material.dart';

import '../../../../data/dtos/wallet.dart';

/// Icon for each wallet type (card, selector, detail).
extension WalletTypeIcon on WalletType? {
  IconData get icon => switch (this) {
    WalletType.cash => Icons.payments_outlined,
    WalletType.checking => Icons.account_balance_outlined,
    WalletType.savings => Icons.savings_outlined,
    WalletType.creditCard => Icons.credit_card_rounded,
    WalletType.investment => Icons.trending_up_rounded,
    WalletType.other || null => Icons.account_balance_wallet_outlined,
  };

  /// Spanish label; a wallet without type reads «Sin tipo».
  String get displayLabel => this?.label ?? 'Sin tipo';
}
