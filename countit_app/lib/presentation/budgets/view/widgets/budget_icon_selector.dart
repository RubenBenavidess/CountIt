import 'package:flutter/material.dart';

import '../../../../app/theme/app_theme.dart';
import '../../../../app/theme/tokens.dart';
import '../../../../data/dtos/budget.dart';
import 'budget_icon.dart';

/// Category of a budget (COU-222): the 18 icons the API accepts. The icon is
/// optional: tapping the selected one clears it.
class BudgetIconSelector extends StatelessWidget {
  const BudgetIconSelector({super.key, required this.value, required this.onChanged, this.enabled = true});

  final BudgetIcon? value;
  final ValueChanged<BudgetIcon?> onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: AppSpacing.sm,
      children: [
        Text(
          'Ícono (opcional) · ${value?.label ?? 'Sin ícono'}',
          style: AppTypography.label.copyWith(color: scheme.onSurface),
        ),
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: [
            for (final icon in BudgetIcon.values)
              _IconOption(
                icon: icon,
                selected: icon == value,
                onTap: enabled ? () => onChanged(icon == value ? null : icon) : null,
              ),
          ],
        ),
      ],
    );
  }
}

class _IconOption extends StatelessWidget {
  const _IconOption({required this.icon, required this.selected, required this.onTap});

  final BudgetIcon icon;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final palette = context.palette;
    final radius = BorderRadius.circular(AppRadii.md);
    return Semantics(
      button: true,
      selected: selected,
      label: icon.label,
      excludeSemantics: true,
      child: Tooltip(
        message: icon.label,
        child: Material(
          key: ValueKey('budget-icon-${icon.apiValue}'),
          color: selected ? scheme.primary : palette.surface2,
          shape: RoundedRectangleBorder(
            borderRadius: radius,
            side: BorderSide(color: selected ? scheme.primary : palette.line, width: AppSizes.borderWidth),
          ),
          child: InkWell(
            borderRadius: radius,
            onTap: onTap,
            child: SizedBox.square(
              dimension: AppSizes.iconButton + 4,
              child: Icon(icon.iconData, size: 22, color: selected ? scheme.onPrimary : scheme.onSurface),
            ),
          ),
        ),
      ),
    );
  }
}
