import 'dart:async';

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

/// «¿Descartar los cambios?» when leaving a form with unsaved edits; pops the
/// route only when the user confirms.
Future<void> confirmDiscardChanges(BuildContext context) async {
  final navigator = Navigator.of(context);
  final leave = await showConfirmDialog(
    context,
    title: '¿Descartar los cambios?',
    message: 'Tienes cambios sin guardar.',
    confirmLabel: 'Descartar',
    cancelLabel: 'Seguir editando',
    destructive: true,
  );
  if (leave) navigator.pop();
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

/// Asks «¿Descartar los cambios?» ([confirmDiscardChanges]) when the user
/// leaves a form while [dirty]; otherwise the route pops as usual.
class DiscardChangesGuard extends StatelessWidget {
  const DiscardChangesGuard({super.key, required this.dirty, required this.child});

  final bool dirty;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return PopScope<Object?>(
      canPop: !dirty,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) unawaited(confirmDiscardChanges(context));
      },
      child: child,
    );
  }
}
