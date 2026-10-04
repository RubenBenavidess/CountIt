import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router/app_router.dart';
import '../../../app/theme/tokens.dart';
import '../../../shared/widgets/app_button.dart';
import '../../../shared/widgets/app_card.dart';
import '../../../shared/widgets/wordmark.dart';

/// Welcome / onboarding (COU-80, design Main): shown when there is no session.
class WelcomePage extends StatelessWidget {
  const WelcomePage({super.key});

  static const _features = [
    (Icons.account_balance_wallet_outlined, 'Billeteras con saldo al día'),
    (Icons.sync_alt_rounded, 'Pagos y sueldos programados'),
    (Icons.group_outlined, 'Finanzas compartidas en familia'),
  ];

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Scaffold(
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            SliverFillRemaining(
              hasScrollBody: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(AppSpacing.xxl, AppSpacing.xxl, AppSpacing.xxl, 28),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Wordmark(),
                    const Spacer(),
                    Semantics(
                      header: true,
                      child: Text(
                        'Cuéntalo\ntodo.',
                        style: AppTypography.display.copyWith(color: textTheme.bodyLarge?.color),
                      ),
                    ),
                    const SizedBox(height: 18),
                    Text(
                      'Ingresos, gastos y presupuestos que se renuevan solos. Comparte billeteras con tu familia.',
                      style: AppTypography.body.copyWith(fontSize: 17, color: AppColors.muted),
                    ),
                    const SizedBox(height: 30),
                    for (final (icon, label) in _features)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 14),
                        child: Row(
                          spacing: AppSpacing.md,
                          children: [
                            IconTile(icon),
                            Expanded(child: Text(label, style: AppTypography.body)),
                          ],
                        ),
                      ),
                    const Spacer(),
                    AppButton(label: 'Crear mi cuenta', onPressed: () => context.push(AppRoutes.register)),
                    const SizedBox(height: AppSpacing.md),
                    AppButton(
                      label: 'Ya tengo cuenta',
                      variant: AppButtonVariant.ghost,
                      onPressed: () => context.push(AppRoutes.login),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    Text(
                      '© 2026 CountIt! · Hecho en Ecuador',
                      textAlign: TextAlign.center,
                      style: AppTypography.caption.copyWith(color: AppColors.muted),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
