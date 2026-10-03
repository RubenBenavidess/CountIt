import 'package:flutter/material.dart';

import '../../app/theme/tokens.dart';
import 'app_button.dart';

/// Confirmation dialog. Returns true only when the user confirms; dismissing
/// it (back, tap outside) returns false.
Future<bool> showConfirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  String confirmLabel = 'Confirmar',
  String cancelLabel = 'Cancelar',
  bool destructive = false,
}) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(AppRadii.card))),
      title: Text(title, style: AppTypography.h2),
      content: Text(message, style: AppTypography.body),
      actionsPadding: const EdgeInsets.fromLTRB(AppSpacing.xl, 0, AppSpacing.xl, AppSpacing.xl),
      actions: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: AppSpacing.sm,
          children: [
            AppButton(
              label: confirmLabel,
              variant: destructive ? AppButtonVariant.dangerSolid : AppButtonVariant.primary,
              onPressed: () => Navigator.of(context).pop(true),
            ),
            AppButton(
              label: cancelLabel,
              variant: AppButtonVariant.ghost,
              onPressed: () => Navigator.of(context).pop(false),
            ),
          ],
        ),
      ],
    ),
  );
  return confirmed ?? false;
}

/// Bottom sheet of the design (radius 24, grabber, scrim) that grows with the keyboard.
Future<T?> showAppBottomSheet<T>(BuildContext context, {required WidgetBuilder builder, String? title}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (context) => Padding(
      padding: EdgeInsets.fromLTRB(
        AppSpacing.screen,
        0,
        AppSpacing.screen,
        MediaQuery.viewInsetsOf(context).bottom + 28,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 18,
        children: [
          if (title != null) Semantics(header: true, child: Text(title, style: AppTypography.h2)),
          builder(context),
        ],
      ),
    ),
  );
}
