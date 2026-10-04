import 'package:flutter/material.dart';

import '../../../app/theme/tokens.dart';
import '../../../data/dtos/wallet.dart';
import '../../../shared/widgets/app_layout.dart';

/// Create (no [initial]) or edit a wallet (HU-07/HU-09). The form lands with
/// COU-192..COU-194.
class WalletFormPage extends StatelessWidget {
  const WalletFormPage({super.key, this.initial});

  final Wallet? initial;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppTopBar(title: initial == null ? 'Nueva billetera' : 'Editar billetera'),
      body: Padding(
        padding: const EdgeInsets.all(AppSpacing.screen),
        child: Text('Muy pronto podrás crear y editar billeteras aquí.', style: Theme.of(context).textTheme.bodySmall),
      ),
    );
  }
}
