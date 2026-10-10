import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../app/theme/app_theme.dart';
import '../../../../app/theme/tokens.dart';
import '../../../../data/dtos/json_parsing.dart';
import '../../../../shared/widgets/app_fields.dart';
import '../../../wallets/view/widgets/wallet_colors.dart';

/// Brand-like colours offered as swatches (any `#RRGGBB` can be typed).
const bankSwatches = <int>[
  0xFFFFDD00,
  0xFFF39200,
  0xFFE30613,
  0xFFD6006E,
  0xFF7B2D8E,
  0xFF00387B,
  0xFF0072BC,
  0xFF00A3E0,
  0xFF00843D,
  0xFF8DC63F,
  0xFF5D4037,
  0xFF1B263B,
];

/// Colour of a bank (HU-27 · COU-206): swatches, «Sin color» and a hex
/// field. Each swatch shows a check in ink or white, whichever reads better
/// on it (the same rule as the wallet card text).
class BankColorPicker extends StatelessWidget {
  const BankColorPicker({
    super.key,
    required this.color,
    required this.hexController,
    required this.onChanged,
    this.errorText,
  });

  /// Opaque ARGB; null = no colour.
  final int? color;
  final TextEditingController hexController;

  /// A swatch, «Sin color» or a valid typed value.
  final ValueChanged<int?> onChanged;
  final String? errorText;

  void _pick(int? value) {
    hexController.text = toHexColor(value) ?? '';
    onChanged(value);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: AppSpacing.md,
      children: [
        Semantics(
          container: true,
          label: 'Color de acento del banco',
          child: Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              _Swatch(color: null, selected: color == null, onTap: () => _pick(null)),
              for (final swatch in bankSwatches)
                _Swatch(color: swatch, selected: color == swatch, onTap: () => _pick(swatch)),
            ],
          ),
        ),
        AppTextField(
          key: const ValueKey('bank-color-hex'),
          label: 'Código de color (opcional)',
          hint: '#RRGGBB',
          controller: hexController,
          errorText: errorText,
          maxLength: 7,
          textCapitalization: TextCapitalization.characters,
          inputFormatters: [FilteringTextInputFormatter.allow(RegExp('[#0-9A-Fa-f]'))],
          validator: (text) => (text ?? '').trim().isEmpty || parseHexColor(text) != null
              ? null
              : 'Color no válido: usa el formato #RRGGBB',
          onChanged: (text) {
            final parsed = parseHexColor(text);
            if (parsed != null || text.trim().isEmpty) onChanged(parsed);
          },
        ),
      ],
    );
  }
}

class _Swatch extends StatelessWidget {
  const _Swatch({required this.color, required this.selected, required this.onTap});

  final int? color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final fill = color == null ? null : Color(color!);
    final check = fill == null
        ? Theme.of(context).colorScheme.onSurface
        : (WalletColors.isLight(fill) ? AppColors.ink : AppColors.white);
    return Semantics(
      button: true,
      selected: selected,
      inMutuallyExclusiveGroup: true,
      label: color == null ? 'Sin color' : 'Color ${toHexColor(color)}',
      excludeSemantics: true,
      child: InkResponse(
        onTap: onTap,
        radius: 26,
        child: Container(
          width: AppSizes.iconButton,
          height: AppSizes.iconButton,
          decoration: BoxDecoration(
            color: fill,
            shape: BoxShape.circle,
            border: Border.all(
              color: selected ? AppColors.lavender : palette.line,
              width: selected ? 3 : AppSizes.borderWidth,
            ),
          ),
          child: selected
              ? Icon(Icons.check_rounded, color: check, size: 22)
              : color == null
              ? Icon(Icons.format_color_reset_outlined, color: palette.muted, size: 20)
              : null,
        ),
      ),
    );
  }
}
