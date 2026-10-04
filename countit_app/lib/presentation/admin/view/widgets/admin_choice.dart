import 'package:flutter/material.dart';

import '../../../../app/theme/app_theme.dart';
import '../../../../app/theme/tokens.dart';

/// One option of an [AdminChoiceGroup].
class AdminChoice<T> {
  const AdminChoice(this.value, this.label, {this.key, this.caption});

  final T value;
  final String label;
  final String? caption;
  final Key? key;
}

/// Single choice list (plan, role): 56 px rows, the selection marked with a
/// check and announced as selected inside a mutually exclusive group.
class AdminChoiceGroup<T> extends StatelessWidget {
  const AdminChoiceGroup({
    super.key,
    required this.label,
    required this.options,
    required this.selected,
    required this.onSelected,
  });

  final String label;
  final List<AdminChoice<T>> options;
  final T selected;
  final ValueChanged<T> onSelected;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Semantics(
      container: true,
      label: label,
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border.all(color: palette.line),
          borderRadius: BorderRadius.circular(AppRadii.lg),
        ),
        child: Column(
          children: [
            for (final (index, option) in options.indexed) ...[
              if (index > 0) Divider(height: 1, color: palette.line),
              Semantics(
                key: option.key,
                inMutuallyExclusiveGroup: true,
                selected: option.value == selected,
                button: true,
                child: ListTile(
                  minTileHeight: 56,
                  title: Text(option.label, style: AppTypography.label),
                  subtitle: option.caption == null
                      ? null
                      : Text(option.caption!, style: AppTypography.caption.copyWith(color: palette.muted)),
                  trailing: option.value == selected
                      ? const Icon(Icons.check_circle_rounded, color: AppColors.lavender)
                      : Icon(Icons.circle_outlined, color: palette.muted),
                  onTap: () => onSelected(option.value),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
