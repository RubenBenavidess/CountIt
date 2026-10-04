import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../app/plans/plan_gate.dart';
import '../../../app/router/app_router.dart';
import '../../../app/theme/app_theme.dart';
import '../../../app/theme/tokens.dart';
import '../../../data/dtos/profile.dart';
import '../../../data/dtos/statistics.dart';
import '../../../data/dtos/wallet.dart';
import '../../../data/repositories/analysis_repository.dart';
import '../../../data/repositories/wallet_repository.dart';
import '../../../shared/state/load_state.dart';
import '../../../shared/utils/dates.dart';
import '../../../shared/utils/money.dart';
import '../../../shared/widgets/app_button.dart';
import '../../../shared/widgets/app_card.dart';
import '../../../shared/widgets/app_feedback.dart';
import '../../../shared/widgets/app_fields.dart';
import '../../../shared/widgets/app_layout.dart';
import '../../../shared/widgets/detail_rows.dart';
import '../../../shared/widgets/section_header.dart';
import '../../plans/view/plan_upsell_sheet.dart';
import '../../shell/view/visible_tab_listener.dart';
import '../../wallets/view/widgets/entry_card.dart';
import '../cubit/statistics_cubit.dart';
import 'charts/evolution_chart.dart';
import 'charts/income_expense_chart.dart';
import 'projection_page.dart';
import 'widgets/distribution_section.dart';

/// «Estadísticas» of a wallet (HU-26 · COU-93): wallet and range selectors,
/// totals, growth against last month and, with the plan feature, the
/// distribution by budget. Every figure comes from `get_wallet_statistics`.
///
/// Opened from a wallet it starts on that wallet; as the «Estadísticas» tab
/// ([asTab], no [walletId]) it starts on the first wallet of the list.
class StatisticsPage extends StatelessWidget {
  const StatisticsPage({super.key, this.walletId, this.initial, this.asTab = false});

  final int? walletId;

  /// The wallet the detail screen loaded: names the selector at once.
  final Wallet? initial;

  /// A tab of the shell: no back button, and it refreshes when shown again.
  final bool asTab;

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) => StatisticsCubit(
        context.read<AnalysisRepository>(),
        context.read<WalletRepository>(),
        walletId: walletId,
        initial: initial,
      )..start(),
      child: _StatisticsView(asTab: asTab),
    );
  }
}

/// Title of the plans sheet when the plan lacks the distribution (COU-169).
const distributionNotInPlanTitle = 'Tu plan no incluye la distribución por presupuesto';

class _StatisticsView extends StatelessWidget {
  const _StatisticsView({required this.asTab});

  final bool asTab;

  Future<void> _refresh(BuildContext context) {
    final cubit = context.read<StatisticsCubit>();
    if (cubit.state.walletId == null) return cubit.start();
    return Future.wait([cubit.refresh(), if (asTab || cubit.state.wallets.data == null) cubit.loadWallets()]);
  }

  @override
  Widget build(BuildContext context) {
    final screen = _screen(context);
    // Back on the tab: movements or wallets may have changed meanwhile.
    return asTab ? VisibleTabListener(onVisible: () => unawaited(_refresh(context)), child: screen) : screen;
  }

  Widget _screen(BuildContext context) {
    const padding = EdgeInsets.symmetric(horizontal: AppSpacing.screen);
    return Scaffold(
      appBar: AppTopBar(title: 'Estadísticas', showBack: !asTab),
      body: RefreshIndicator(
        onRefresh: () => _refresh(context),
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverPadding(
              padding: padding.copyWith(top: AppSpacing.sm),
              sliver: const SliverList(
                delegate: SliverChildListDelegate.fixed([
                  _WalletSelector(),
                  SizedBox(height: AppSpacing.lg),
                  _RangeSelector(),
                  SizedBox(height: AppSpacing.lg),
                  _ProjectionEntry(),
                  SizedBox(height: AppSpacing.xl),
                ]),
              ),
            ),
            SliverPadding(
              padding: padding.copyWith(bottom: AppSpacing.xxl * 2),
              sliver: BlocBuilder<StatisticsCubit, StatisticsState>(
                buildWhen: (previous, current) =>
                    previous.statistics != current.statistics ||
                    (current.walletId == null && previous.wallets != current.wallets),
                builder: (context, state) =>
                    state.walletId == null ? _noWallet(context, state.wallets) : _content(context, state.statistics),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// The tab before a wallet is chosen: its list loading, failing or empty.
  Widget _noWallet(BuildContext context, LoadState<List<Wallet>> wallets) {
    final cubit = context.read<StatisticsCubit>();
    return SliverToBoxAdapter(
      child: switch (wallets) {
        LoadState(status: LoadStatus.failure, :final failure?) => _FailureNote(
          message: failure.message,
          onRetry: cubit.start,
        ),
        LoadState(data: final data?) when data.isEmpty => const NoteCard(
          icon: Icons.account_balance_wallet_outlined,
          message: 'Crea una billetera y registra movimientos para ver aquí tus estadísticas.',
        ),
        _ => const SectionLoading(label: 'Cargando estadísticas'),
      },
    );
  }

  Widget _content(BuildContext context, LoadState<WalletStatistics> state) {
    final cubit = context.read<StatisticsCubit>();
    final statistics = state.data;
    if (statistics == null) {
      return SliverToBoxAdapter(
        child: state.status == LoadStatus.failure
            ? _FailureNote(message: state.failure!.message, onRetry: cubit.refresh)
            : const SectionLoading(label: 'Cargando estadísticas'),
      );
    }
    return SliverMainAxisGroup(
      slivers: [
        SliverList.list(
          children: [
            if (state.status == LoadStatus.failure) ...[
              _FailureNote(message: state.failure!.message, onRetry: cubit.refresh),
              const SizedBox(height: AppSpacing.lg),
            ],
            if (state.status == LoadStatus.loading) ...[
              const LinearProgressIndicator(minHeight: 2),
              const SizedBox(height: AppSpacing.md),
            ],
            Text(
              '${Dates.range(statistics.from, statistics.to)} · ${statistics.bucket.label}',
              style: AppTypography.caption.copyWith(color: context.palette.muted),
            ),
            const SizedBox(height: AppSpacing.md),
            if (statistics.isEmpty)
              const NoteCard(
                icon: Icons.insights_outlined,
                message: 'Sin movimientos en este periodo. Registra ingresos o gastos, o elige un periodo más largo.',
              )
            else ...[
              _Totals(totals: statistics.totals),
              const SizedBox(height: AppSpacing.xxl),
              const SectionHeader(title: 'Ingresos vs. gastos'),
              AppCard(child: IncomeExpenseChart(statistics: statistics)),
              const SizedBox(height: AppSpacing.xxl),
              const SectionHeader(title: 'Evolución'),
              AppCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  spacing: AppSpacing.md,
                  children: [
                    Text(
                      'Balance acumulado del periodo (ingresos menos gastos).',
                      style: AppTypography.caption.copyWith(color: context.palette.muted),
                    ),
                    EvolutionChart(statistics: statistics),
                  ],
                ),
              ),
            ],
            const SizedBox(height: AppSpacing.lg),
            _Growth(growth: statistics.growth),
            const SizedBox(height: AppSpacing.xxl),
          ],
        ),
        if (statistics.distribution == null)
          const SliverToBoxAdapter(child: _DistributionLocked())
        else if (!statistics.isEmpty)
          DistributionSection(distribution: statistics.distribution!),
      ],
    );
  }
}

class _FailureNote extends StatelessWidget {
  const _FailureNote({required this.message, required this.onRetry});

  final String message;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    return NoteCard(
      icon: Icons.cloud_off_outlined,
      message: message,
      action: AppButton(
        label: 'Reintentar',
        variant: AppButtonVariant.ghost,
        expand: false,
        small: true,
        onPressed: () => unawaited(onRetry()),
      ),
    );
  }
}

/// Own and shared wallets; while the list loads (or if it fails) it offers
/// the wallet on screen.
class _WalletSelector extends StatelessWidget {
  const _WalletSelector();

  @override
  Widget build(BuildContext context) {
    final (wallets, walletId) = context.select(
      (StatisticsCubit cubit) => (cubit.state.wallets.data ?? const <Wallet>[], cubit.state.walletId),
    );
    final options = [for (final wallet in wallets) AppOption(wallet.walletId, wallet.name)];
    return AppDropdownField<int>(
      label: 'Billetera',
      options: options,
      value: options.any((o) => o.value == walletId) ? walletId : null,
      hint: 'Cargando billeteras…',
      enabled: options.length > 1,
      onChanged: (id) {
        if (id != null) unawaited(context.read<StatisticsCubit>().selectWallet(id));
      },
    );
  }
}

class _RangeSelector extends StatelessWidget {
  const _RangeSelector();

  @override
  Widget build(BuildContext context) {
    final range = context.select((StatisticsCubit cubit) => cubit.state.range);
    return AppChoiceChips<StatisticsRange>(
      label: 'Periodo',
      options: [for (final r in StatisticsRange.values) AppOption(r, r.label)],
      value: range,
      onChanged: (r) => unawaited(context.read<StatisticsCubit>().selectRange(r)),
    );
  }
}

class _Totals extends StatelessWidget {
  const _Totals({required this.totals});

  final StatisticsTotals totals;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final net = totals.net;
    return DetailRows(
      rows: [
        DetailRow('Ingresos', Money.signed(totals.income, income: true), color: palette.income, money: true),
        DetailRow('Gastos', Money.signed(totals.expense, income: false), color: palette.expense, money: true),
        DetailRow('Balance del periodo', Money.signed(net.abs(), income: net >= 0), money: true),
      ],
    );
  }
}

/// This month against the previous one (COU-93): arrow, sign and words, never colour alone.
class _Growth extends StatelessWidget {
  const _Growth({required this.growth});

  final StatisticsGrowth growth;

  @override
  Widget build(BuildContext context) {
    final muted = context.palette.muted;
    return AppCard(
      outlined: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: AppSpacing.md,
        children: [
          Text('ESTE MES VS. EL ANTERIOR', style: AppTypography.overline.copyWith(color: muted)),
          _GrowthLine(label: 'Ingresos', pct: growth.incomePct),
          _GrowthLine(label: 'Gastos', pct: growth.expensePct),
        ],
      ),
    );
  }
}

class _GrowthLine extends StatelessWidget {
  const _GrowthLine({required this.label, required this.pct});

  final String label;
  final double? pct;

  @override
  Widget build(BuildContext context) {
    final muted = context.palette.muted;
    final value = pct;
    final (IconData icon, String text, String spoken) = switch (value) {
      null => (Icons.remove_rounded, 'Sin datos del mes anterior', 'sin datos del mes anterior'),
      > 0 => (Icons.trending_up_rounded, Percent.change(value), 'subieron ${Percent.format(value)}'),
      < 0 => (Icons.trending_down_rounded, Percent.change(value), 'bajaron ${Percent.format(value)}'),
      _ => (Icons.trending_flat_rounded, Percent.change(0), 'sin cambios'),
    };
    return Semantics(
      label: '$label: $spoken',
      container: true,
      excludeSemantics: true,
      child: Row(
        spacing: AppSpacing.md,
        children: [
          Expanded(child: Text(label, style: AppTypography.label)),
          Icon(icon, size: 20, color: muted),
          Text(
            text,
            style: value == null
                ? AppTypography.caption.copyWith(color: muted)
                : AppTypography.money.copyWith(fontSize: 15),
          ),
        ],
      ),
    );
  }
}

/// Projection of the wallet on screen (HU-25 · COU-99): Contador Profesional
/// only (COU-172); with another plan the plans sheet explains it.
class _ProjectionEntry extends StatelessWidget {
  const _ProjectionEntry();

  void _open(BuildContext context, Wallet? wallet) {
    if (!context.planGate.allows(PlanFeatures.walletProjection)) {
      unawaited(showProjectionUpsell(context));
      return;
    }
    if (wallet != null) unawaited(context.push<Object?>(AppRoutes.projection(wallet.walletId), extra: wallet));
  }

  @override
  Widget build(BuildContext context) {
    final allowed = context.watchPlanAllows(PlanFeatures.walletProjection);
    final wallet = context.select((StatisticsCubit cubit) => cubit.state.wallet);
    return EntryCard(
      key: const ValueKey('statistics-projection'),
      icon: allowed ? Icons.show_chart_rounded : Icons.lock_outline_rounded,
      title: 'Proyección de saldo',
      subtitle: allowed ? 'Tu saldo con los movimientos programados' : 'Disponible en el plan Contador Profesional',
      onTap: () => _open(context, wallet),
    );
  }
}

/// COU-169: the Regular plan has no distribution by budget; the API sends
/// none and the card offers the plans instead.
class _DistributionLocked extends StatelessWidget {
  const _DistributionLocked();

  static const message =
      'La distribución de ingresos y gastos por presupuesto está disponible en los planes '
      'Contador y Contador Profesional.';

  @override
  Widget build(BuildContext context) {
    return AppCard(
      key: const ValueKey('distribution-locked'),
      outlined: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: AppSpacing.md,
        children: [
          const Row(
            spacing: AppSpacing.md,
            children: [
              IconTile(Icons.lock_outline_rounded),
              Expanded(child: Text('Distribución por presupuesto', style: AppTypography.label)),
              AppBadge('Contador', tone: BadgeTone.pro),
            ],
          ),
          Text(message, style: AppTypography.caption.copyWith(color: context.palette.muted)),
          AppButton(
            label: 'Ver planes',
            variant: AppButtonVariant.ghost,
            small: true,
            expand: false,
            onPressed: () => unawaited(showPlanUpsell(context, title: distributionNotInPlanTitle, message: message)),
          ),
        ],
      ),
    );
  }
}
