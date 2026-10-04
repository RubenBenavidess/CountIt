import 'package:flutter/material.dart';

import '../../../../app/plans/plan_gate.dart';
import '../../../../app/theme/app_theme.dart';
import '../../../../app/theme/tokens.dart';
import '../../../../data/dtos/budget.dart';
import '../../../../data/dtos/profile.dart';
import '../../../../data/dtos/transaction.dart';
import '../../../../data/dtos/wallet.dart';
import '../../../../shared/utils/money.dart';
import '../../../../shared/widgets/app_card.dart';
import '../../../../shared/widgets/detail_rows.dart';
import '../../../budgets/view/budget_section.dart';
import '../../../transactions/view/transaction_section.dart';
import 'entry_card.dart';
import 'wallet_card.dart';
import 'wallet_type_icon.dart';

/// Scrollable content of the wallet detail: card, totals, ways into its
/// screens, budgets and movements.
class WalletDetailBody extends StatelessWidget {
  const WalletDetailBody({
    super.key,
    required this.wallet,
    required this.onCreateBudget,
    required this.onOpenBudget,
    required this.onOpenTransaction,
    required this.onEditFilters,
    required this.onOpenScheduled,
    required this.onOpenStatistics,
    required this.onOpenProjection,
    required this.onOpenMembers,
  });

  final Wallet wallet;
  final ValueChanged<Transaction> onOpenTransaction;
  final VoidCallback onEditFilters;
  final VoidCallback onOpenScheduled;
  final VoidCallback onOpenStatistics;
  final VoidCallback onOpenProjection;
  final VoidCallback onOpenMembers;
  final VoidCallback onCreateBudget;
  final ValueChanged<Budget> onOpenBudget;

  @override
  Widget build(BuildContext context) {
    final muted = context.palette.muted;
    final description = wallet.description?.trim();
    const padding = EdgeInsets.symmetric(horizontal: AppSpacing.screen);
    return CustomScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: [
        SliverPadding(
          padding: padding.copyWith(top: AppSpacing.sm, bottom: AppSpacing.xxl),
          sliver: SliverList.list(
            children: [
              WalletCard(wallet: wallet, hero: true, countUp: false),
              const SizedBox(height: AppSpacing.lg),
              _Figures(wallet: wallet),
              if ((description?.isNotEmpty ?? false) || !wallet.isOwner) ...[
                const SizedBox(height: AppSpacing.lg),
                AppCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    spacing: AppSpacing.xs,
                    children: [
                      if (!wallet.isOwner)
                        Text(
                          'Compartida contigo por ${wallet.ownerName ?? 'otro usuario'}',
                          style: AppTypography.label,
                        ),
                      if (description?.isNotEmpty ?? false)
                        Text(description!, style: AppTypography.body.copyWith(color: muted)),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: AppSpacing.lg),
              // Way into the wallet's scheduled rules (HU-16/HU-20 · COU-88).
              EntryCard(
                key: const ValueKey('wallet-scheduled'),
                icon: Icons.event_repeat_rounded,
                title: 'Movimientos programados',
                subtitle: 'Ingresos y gastos futuros que se registran solos',
                onTap: onOpenScheduled,
              ),
              const SizedBox(height: AppSpacing.md),
              // Statistics of the wallet (HU-26 · COU-93).
              EntryCard(
                key: const ValueKey('wallet-statistics'),
                icon: Icons.insights_rounded,
                title: 'Estadísticas',
                subtitle: 'Ingresos y gastos en el tiempo y por presupuesto',
                onTap: onOpenStatistics,
              ),
              const SizedBox(height: AppSpacing.md),
              // Projection (HU-25 · COU-99): Contador Profesional only (COU-172).
              Builder(
                builder: (context) {
                  final allowed = context.watchPlanAllows(PlanFeatures.walletProjection);
                  return EntryCard(
                    key: const ValueKey('wallet-projection'),
                    icon: allowed ? Icons.show_chart_rounded : Icons.lock_outline_rounded,
                    title: 'Proyección de saldo',
                    subtitle: allowed
                        ? 'Tu saldo con los movimientos programados'
                        : 'Disponible en el plan Contador Profesional',
                    onTap: onOpenProjection,
                  );
                },
              ),
              const SizedBox(height: AppSpacing.md),
              _MembersEntry(wallet: wallet, onTap: onOpenMembers),
            ],
          ),
        ),
        SliverPadding(
          padding: padding,
          sliver: BudgetSection(onCreate: onCreateBudget, onOpen: onOpenBudget),
        ),
        SliverPadding(
          // Room below the last movement for the floating «Movimiento» button.
          padding: padding.copyWith(top: AppSpacing.xxl, bottom: 96),
          sliver: TransactionSection(
            showAuthor: wallet.isShared,
            onOpen: onOpenTransaction,
            onEditFilters: onEditFilters,
          ),
        ),
      ],
    );
  }
}

/// Way into the wallet's family (HU-21…HU-24 · COU-92): who shares it.
class _MembersEntry extends StatelessWidget {
  const _MembersEntry({required this.wallet, required this.onTap});

  final Wallet wallet;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final count = wallet.memberCount;
    final people = count == 1 ? '1 miembro' : '$count miembros';
    final subtitle = wallet.isOwner
        ? (count > 0 ? 'Compartida con $people' : 'Compártela con tu familia por nombre de usuario')
        : 'De ${wallet.ownerName ?? 'otro usuario'} · $people';
    return EntryCard(
      key: const ValueKey('wallet-members'),
      icon: Icons.group_outlined,
      title: 'Familia',
      subtitle: subtitle,
      onTap: onTap,
    );
  }
}

/// Totals of the wallet; the projection only when the plan includes it.
class _Figures extends StatelessWidget {
  const _Figures({required this.wallet});

  final Wallet wallet;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return DetailRows(
      rows: [
        DetailRow('Tipo', wallet.type.displayLabel),
        DetailRow('Saldo inicial', Money.format(wallet.initialBalance), money: true),
        DetailRow(
          'Ingresos totales',
          Money.signed(wallet.totalIncome, income: true),
          color: palette.income,
          money: true,
        ),
        DetailRow(
          'Gastos totales',
          Money.signed(wallet.totalExpenses, income: false),
          color: palette.expense,
          money: true,
        ),
        DetailRow(
          'Ingresos del mes',
          Money.signed(wallet.monthIncome, income: true),
          color: palette.income,
          money: true,
        ),
        DetailRow(
          'Gastos del mes',
          Money.signed(wallet.monthExpenses, income: false),
          color: palette.expense,
          money: true,
        ),
        if (wallet.projectedBalance != null)
          DetailRow('Saldo proyectado a fin de mes', Money.format(wallet.projectedBalance!), money: true),
      ],
    );
  }
}
