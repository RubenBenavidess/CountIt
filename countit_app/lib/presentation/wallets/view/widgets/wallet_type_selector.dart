import 'package:flutter/material.dart';

import '../../../../app/theme/tokens.dart';
import '../../../../data/dtos/wallet.dart';
import 'wallet_type_icon.dart';

/// Wallet type chips (COU-191): one per backend value, with icon and Spanish name.
class WalletTypeSelector extends StatelessWidget {
  const WalletTypeSelector({super.key, required this.value, required this.onChanged, this.enabled = true});

  final WalletType? value;
  final ValueChanged<WalletType> onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: AppSpacing.sm,
      children: [
        Text('Tipo', style: AppTypography.label.copyWith(color: scheme.onSurface)),
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: [
            for (final type in WalletType.values)
              ChoiceChip(
                key: ValueKey('wallet-type-${type.apiValue}'),
                avatar: Icon(type.icon, size: 18, color: type == value ? scheme.onPrimary : scheme.onSurface),
                label: Text(type.label),
                selected: type == value,
                onSelected: enabled ? (_) => onChanged(type) : null,
              ),
          ],
        ),
      ],
    );
  }
}
