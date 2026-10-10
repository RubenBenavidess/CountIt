import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../app/theme/app_theme.dart';
import '../../../app/theme/tokens.dart';
import '../../../shared/widgets/app_card.dart';
import '../../../shared/widgets/app_feedback.dart';
import '../../../shared/widgets/app_layout.dart';
import '../../wallets/view/widgets/bank_disclaimer.dart';

/// Opens [url] outside the app; false when nothing could open it.
typedef LinkOpener = Future<bool> Function(Uri url);

Future<bool> _openExternally(Uri url) async {
  try {
    return await launchUrl(url, mode: LaunchMode.externalApplication);
  } on Exception {
    return false;
  }
}

/// «Acerca de Count It!»: legal links and the non-affiliation notice of the
/// bank names.
class AboutPage extends StatelessWidget {
  const AboutPage({super.key, this.openLink = _openExternally});

  static final privacyUrl = Uri.parse('https://countit-bft.pages.dev/privacidad/');
  static final termsUrl = Uri.parse('https://countit-bft.pages.dev/terminos/');

  final LinkOpener openLink;

  Future<void> _open(BuildContext context, Uri url) async {
    final opened = await openLink(url);
    if (!opened && context.mounted) {
      showAppSnackBar(context, 'No pudimos abrir el enlace: ${url.toString()}', kind: SnackKind.error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Scaffold(
      appBar: const AppTopBar(title: 'Acerca de Count It!'),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(AppSpacing.screen, AppSpacing.md, AppSpacing.screen, AppSpacing.xxl),
        children: [
          const Text('Count It!', style: AppTypography.title),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Finanzas personales con billeteras compartidas.',
            style: AppTypography.caption.copyWith(color: palette.muted),
          ),
          const SizedBox(height: AppSpacing.lg),
          AppCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                _LinkTile(
                  key: const ValueKey('about-privacy'),
                  label: 'Política de privacidad',
                  url: privacyUrl,
                  onTap: () => unawaited(_open(context, privacyUrl)),
                ),
                Divider(height: 1, color: palette.line),
                _LinkTile(
                  key: const ValueKey('about-terms'),
                  label: 'Términos y condiciones',
                  url: termsUrl,
                  onTap: () => unawaited(_open(context, termsUrl)),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          Text('BANCOS', style: AppTypography.overline.copyWith(color: palette.muted)),
          const SizedBox(height: AppSpacing.sm),
          const BankDisclaimer(),
        ],
      ),
    );
  }
}

class _LinkTile extends StatelessWidget {
  const _LinkTile({super.key, required this.label, required this.url, required this.onTap});

  final String label;
  final Uri url;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      minTileHeight: 56,
      contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
      title: Text(label, style: AppTypography.label.copyWith(fontSize: 15)),
      subtitle: Text(url.toString(), style: AppTypography.caption.copyWith(color: AppColors.muted)),
      trailing: const Icon(Icons.open_in_new_rounded, color: AppColors.muted, size: 20),
      onTap: onTap,
    );
  }
}
