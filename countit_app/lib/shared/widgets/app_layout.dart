import 'package:flutter/material.dart';

import '../../app/theme/tokens.dart';
import 'wordmark.dart';

/// Top bar of the design: 44 px back button plus a title or the wordmark.
/// Without [onBack] it pops the route when possible.
class AppTopBar extends StatelessWidget implements PreferredSizeWidget {
  const AppTopBar({super.key, this.title, this.showWordmark = false, this.showBack = true, this.onBack});

  final String? title;
  final bool showWordmark;
  final bool showBack;
  final VoidCallback? onBack;

  @override
  Size get preferredSize => const Size.fromHeight(64);

  @override
  Widget build(BuildContext context) {
    final canPop = Navigator.of(context).canPop();
    final back = showBack && (onBack != null || canPop)
        ? IconButton(
            tooltip: 'Volver',
            icon: const Icon(Icons.chevron_left_rounded, size: 28),
            onPressed: onBack ?? () => Navigator.of(context).maybePop(),
          )
        : null;
    return AppBar(
      automaticallyImplyLeading: false,
      leading: back,
      titleSpacing: back == null ? AppSpacing.screen : 0,
      title: showWordmark
          ? const Wordmark(size: 22)
          : title == null
          ? null
          : Text(title!, style: AppTypography.title),
    );
  }
}

/// Scrollable form body with the primary action pinned to the bottom when the
/// content is short and pushed below it when the keyboard or a long form needs
/// the space (design `.scroll` + `.spacer`). Uses a sliver instead of
/// IntrinsicHeight so layout stays a single pass.
///
/// The content is built eagerly on purpose: a lazy list would leave off-screen
/// fields unmounted and `FormState.validate()` would skip them. Long lists
/// (movements, wallets) use their own lazy builders instead.
class FormScreenBody extends StatelessWidget {
  const FormScreenBody({super.key, required this.content, this.footer = const [], this.gap = AppSpacing.lg});

  /// Fields, banners and texts, top to bottom.
  final List<Widget> content;

  /// Bottom actions (main button, secondary links).
  final List<Widget> footer;
  final double gap;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: CustomScrollView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(AppSpacing.screen, AppSpacing.md, AppSpacing.screen, 0),
            sliver: SliverToBoxAdapter(
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: gap, children: content),
            ),
          ),
          SliverFillRemaining(
            hasScrollBody: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(AppSpacing.screen, AppSpacing.xxl, AppSpacing.screen, AppSpacing.xxl),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.end,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                spacing: AppSpacing.md,
                children: footer,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Inline text link of the design (Lavender, semibold), with a 44 px tap target.
class AppLink extends StatelessWidget {
  const AppLink({super.key, required this.label, required this.onPressed});

  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        foregroundColor: AppColors.lavender,
        minimumSize: const Size(0, AppSizes.iconButton),
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
        tapTargetSize: MaterialTapTargetSize.padded,
        textStyle: AppTypography.label,
      ),
      child: Text(label),
    );
  }
}

/// «¿No tienes cuenta? Crea una»: caption plus a link, centred.
class AppLinkPrompt extends StatelessWidget {
  const AppLinkPrompt({super.key, required this.text, required this.link, required this.onPressed});

  final String text;
  final String link;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(text, style: AppTypography.caption.copyWith(color: AppColors.muted)),
        AppLink(label: link, onPressed: onPressed),
      ],
    );
  }
}
