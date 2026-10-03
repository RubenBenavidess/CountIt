import 'package:flutter/material.dart';

import '../../app/errors/app_failure.dart';
import '../../app/theme/app_theme.dart';
import '../../app/theme/tokens.dart';
import '../state/load_state.dart';
import 'app_button.dart';

/// Nothing to show yet: icon, title, text and an optional action.
class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.title, this.message, this.icon, this.actionLabel, this.onAction});

  final String title;
  final String? message;
  final IconData? icon;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          spacing: AppSpacing.md,
          children: [
            if (icon != null)
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(color: palette.surface2, borderRadius: BorderRadius.circular(18)),
                child: Icon(icon, size: 28, color: palette.muted),
              ),
            Text(title, style: AppTypography.h2, textAlign: TextAlign.center),
            if (message != null)
              Text(
                message!,
                style: AppTypography.caption.copyWith(color: palette.muted),
                textAlign: TextAlign.center,
              ),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: AppSpacing.sm),
              AppButton(label: actionLabel!, onPressed: onAction, expand: false),
            ],
          ],
        ),
      ),
    );
  }
}

/// Centered spinner with an optional caption.
class LoadingView extends StatelessWidget {
  const LoadingView({super.key, this.message});

  final String? message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Semantics(
        label: message ?? 'Cargando',
        child: Column(
          mainAxisSize: MainAxisSize.min,
          spacing: AppSpacing.md,
          children: [
            const CircularProgressIndicator(),
            if (message != null) Text(message!, style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      ),
    );
  }
}

/// Error with the backend's Spanish message and «Reintentar».
class ErrorView extends StatelessWidget {
  const ErrorView({super.key, required this.message, this.onRetry});

  ErrorView.failure(AppFailure failure, {Key? key, VoidCallback? onRetry})
    : this(key: key, message: failure.message, onRetry: onRetry);

  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return EmptyState(
      icon: Icons.cloud_off_outlined,
      title: 'No pudimos cargar esto',
      message: message,
      actionLabel: onRetry == null ? null : 'Reintentar',
      onAction: onRetry,
    );
  }
}

/// Renders a [LoadState]: spinner on the first load, error with retry, empty
/// state, or the data (kept visible while reloading).
class LoadStateView<T> extends StatelessWidget {
  const LoadStateView({super.key, required this.state, required this.builder, this.onRetry, this.isEmpty, this.empty});

  final LoadState<T> state;
  final Widget Function(BuildContext context, T data) builder;
  final VoidCallback? onRetry;
  final bool Function(T data)? isEmpty;
  final Widget? empty;

  @override
  Widget build(BuildContext context) {
    final data = state.data;
    if (data == null) {
      if (state.status == LoadStatus.failure) return ErrorView.failure(state.failure!, onRetry: onRetry);
      return const LoadingView();
    }
    if (empty != null && (isEmpty?.call(data) ?? false)) return empty!;
    return builder(context, data);
  }
}

enum SnackKind { info, success, error }

/// Shows a snackbar replacing the current one, so they never pile up.
void showAppSnackBar(BuildContext context, String message, {SnackKind kind = SnackKind.info}) {
  final palette = context.palette;
  final (IconData icon, Color color) = switch (kind) {
    SnackKind.info => (Icons.info_outline, Theme.of(context).colorScheme.onSurface),
    SnackKind.success => (Icons.check_circle_outline, palette.income),
    SnackKind.error => (Icons.error_outline, palette.expense),
  };
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Row(
          spacing: AppSpacing.md,
          children: [
            Icon(icon, color: color),
            Expanded(child: Text(message)),
          ],
        ),
      ),
    );
}

/// Error snackbar from an [AppFailure] (always the safe Spanish message).
void showFailureSnackBar(BuildContext context, AppFailure failure) =>
    showAppSnackBar(context, failure.message, kind: SnackKind.error);
