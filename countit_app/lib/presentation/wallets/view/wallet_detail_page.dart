import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../app/plans/plan_gate.dart';
import '../../../app/router/app_router.dart';
import '../../../app/session/session_cubit.dart';
import '../../../app/theme/app_theme.dart';
import '../../../app/theme/tokens.dart';
import '../../../data/dtos/budget.dart';
import '../../../data/dtos/profile.dart';
import '../../../data/dtos/scheduled_transaction.dart';
import '../../../data/dtos/transaction.dart';
import '../../../data/dtos/wallet.dart';
import '../../../data/repositories/budget_repository.dart';
import '../../../data/repositories/family_repository.dart';
import '../../../data/repositories/transaction_repository.dart';
import '../../../data/repositories/wallet_repository.dart';
import '../../../shared/state/load_state.dart';
import '../../../shared/utils/dates.dart';
import '../../../shared/utils/money.dart';
import '../../../shared/widgets/app_card.dart';
import '../../../shared/widgets/app_dialogs.dart';
import '../../../shared/widgets/app_feedback.dart';
import '../../../shared/widgets/detail_rows.dart';
import '../../../shared/widgets/load_more_listener.dart';
import '../../account/view/reauth_sheet.dart';
import '../../budgets/cubit/budget_list_cubit.dart';
import '../../budgets/view/budget_form_page.dart';
import '../../budgets/view/budget_section.dart';
import '../../families/cubit/family_members_cubit.dart';
import '../../statistics/view/projection_page.dart';
import '../../transactions/cubit/transaction_list_cubit.dart';
import '../../transactions/view/transaction_detail_page.dart';
import '../../transactions/view/transaction_section.dart';
import '../../transactions/view/widgets/transaction_filters.dart';
import '../cubit/wallet_detail_cubit.dart';
import 'widgets/wallet_card.dart';
import 'widgets/wallet_type_icon.dart';

/// Wallet detail (HU-08/HU-10 · COU-195, COU-211, COU-212). [initial] is the
/// card the home list passed: shown at once while the fresh data loads.
class WalletDetailPage extends StatelessWidget {
  const WalletDetailPage({super.key, required this.walletId, this.initial});

  final int walletId;
  final Wallet? initial;

  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      providers: [
        BlocProvider(
          create: (context) =>
              WalletDetailCubit(context.read<WalletRepository>(), walletId: walletId, initial: initial)..load(),
        ),
        BlocProvider(
          create: (context) => BudgetListCubit(context.read<BudgetRepository>(), walletId: walletId)..load(),
        ),
        BlocProvider(
          create: (context) => TransactionListCubit(context.read<TransactionRepository>(), walletId: walletId)..load(),
        ),
        // Lazy: only the author filter of a shared wallet reads the members.
        BlocProvider(create: (context) => FamilyMembersCubit(context.read<FamilyRepository>(), walletId: walletId)),
      ],
      child: const _WalletDetailView(),
    );
  }
}

enum _MenuAction { edit, members, delete }

class _WalletDetailView extends StatelessWidget {
  const _WalletDetailView();

  /// Leaves to the home list, which reloads when this route pops.
  void _leave(BuildContext context, String message, SnackKind kind) {
    showAppSnackBar(context, message, kind: kind);
    if (context.canPop()) {
      context.pop();
    } else {
      context.go(AppRoutes.home);
    }
  }

  Future<void> _edit(BuildContext context, Wallet wallet) async {
    final cubit = context.read<WalletDetailCubit>();
    await context.push<Object?>(AppRoutes.editWallet(wallet.walletId), extra: wallet);
    if (!cubit.isClosed) unawaited(cubit.load());
  }

  Future<void> _delete(BuildContext context, Wallet wallet) async {
    final cubit = context.read<WalletDetailCubit>();
    final confirmed = await showConfirmDialog(
      context,
      title: '¿Eliminar «${wallet.name}»?',
      message:
          'La billetera dejará de aparecer junto con sus presupuestos y movimientos, '
          'sus movimientos programados se detendrán y sus miembros perderán el acceso.',
      confirmLabel: 'Eliminar',
      destructive: true,
    );
    if (!confirmed || !context.mounted) return;
    await cubit.delete(
      onReauth: reauthPrompt(context, action: 'eliminar «${wallet.name}»', confirmLabel: 'Eliminar billetera'),
    );
  }

  /// Budget form (create or edit); the list reloads on the way back.
  Future<void> _openBudgetForm(BuildContext context, String location, {Object? extra}) async {
    final budgets = context.read<BudgetListCubit>();
    final saved = await context.push<bool>(location, extra: extra);
    if (saved == true && !budgets.isClosed) unawaited(budgets.load());
  }

  /// Transaction form or detail: a save or a deletion changes the balance,
  /// the budgets' progress and the list, so all three reload.
  ///
  /// A new movement with a future date comes back as a draft to schedule
  /// (HU-16 · COU-151): the scheduling form opens with its fields.
  Future<void> _openTransaction(BuildContext context, String location, {Object? extra}) async {
    final result = await context.push<Object?>(location, extra: extra);
    if (!context.mounted) return;
    if (result == true) {
      unawaited(_refresh(context));
    } else if (result is ScheduledTransactionInput) {
      final walletId = context.read<WalletDetailCubit>().walletId;
      unawaited(context.push<bool>(AppRoutes.newScheduled(walletId), extra: result));
    }
  }

  /// Scheduled rules (F06): they never move the balance until they run, so
  /// nothing reloads on the way back.
  void _openScheduled(BuildContext context, Wallet wallet) =>
      unawaited(context.push<Object?>(AppRoutes.scheduled(wallet.walletId), extra: wallet));

  /// Statistics (F08 · COU-93): read only, nothing reloads on the way back.
  void _openStatistics(BuildContext context, Wallet wallet) =>
      unawaited(context.push<Object?>(AppRoutes.statistics(wallet.walletId), extra: wallet));

  /// Projection (F08 · COU-99, COU-172): with the plan known to lack it the
  /// plans sheet explains it instead of a screen the API would refuse (403).
  void _openProjection(BuildContext context, Wallet wallet) {
    if (!context.planGate.allows(PlanFeatures.walletProjection)) {
      unawaited(showProjectionUpsell(context));
      return;
    }
    unawaited(context.push<Object?>(AppRoutes.projection(wallet.walletId), extra: wallet));
  }

  /// Members (F07 · COU-92): inviting, accepting or removing changes the
  /// member count and who may appear as author, so the wallet reloads.
  Future<void> _openMembers(BuildContext context, Wallet wallet) async {
    final cubit = context.read<WalletDetailCubit>();
    final members = context.read<FamilyMembersCubit>();
    await context.push<Object?>(AppRoutes.members(wallet.walletId), extra: wallet);
    if (!cubit.isClosed) unawaited(cubit.load());
    if (!members.isClosed && members.state.members.data != null) unawaited(members.load());
  }

  /// Authors offered by the filter of a shared wallet: everyone who shares it
  /// now (owner and accepted members, COU-234 gap) plus the authors already
  /// seen in the list (former members keep their movements).
  Future<Map<String, String>> _authors(BuildContext context, Wallet wallet) async {
    final seen = context.read<TransactionListCubit>().state.knownAuthors;
    if (!wallet.isShared) return const {};
    final members = context.read<FamilyMembersCubit>();
    await members.ensureLoaded();
    final current = members.state.members.data ?? const [];
    return {
      ...seen,
      for (final member in current)
        if (member.isOwner || member.isAccepted) member.userId: member.name,
    };
  }

  /// Filters sheet (COU-233): budgets come from the section above; authors
  /// only matter in shared wallets.
  Future<void> _editFilters(BuildContext context, Wallet wallet) async {
    final list = context.read<TransactionListCubit>();
    final budgets = context.read<BudgetListCubit>().state.data ?? const <Budget>[];
    final authors = await _authors(context, wallet);
    if (!context.mounted) return;
    final filter = await showTransactionFilters(
      context,
      current: list.state.filter,
      budgets: budgets,
      authors: authors,
      today: Dates.userToday(context.read<SessionCubit>().state.profile?.timezone),
    );
    if (filter != null && !list.isClosed) unawaited(list.applyFilter(filter));
  }

  /// Pull-to-refresh reloads the wallet, its budgets and its movements together.
  Future<void> _refresh(BuildContext context) => Future.wait([
    context.read<WalletDetailCubit>().load(),
    context.read<BudgetListCubit>().load(),
    context.read<TransactionListCubit>().load(),
  ]);

  void _onMenu(BuildContext context, Wallet wallet, _MenuAction action) {
    switch (action) {
      case _MenuAction.edit:
        unawaited(_edit(context, wallet));
      case _MenuAction.delete:
        unawaited(_delete(context, wallet));
      case _MenuAction.members:
        unawaited(_openMembers(context, wallet));
    }
  }

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<WalletDetailCubit, WalletDetailState>(
      listenWhen: (previous, current) =>
          previous.exit != current.exit ||
          (current.actionFailure != null && previous.actionFailure != current.actionFailure) ||
          (current.wallet.status == LoadStatus.failure &&
              current.wallet.data != null &&
              previous.wallet != current.wallet),
      listener: (context, state) {
        switch (state.exit) {
          case WalletDetailExit.notFound:
            return _leave(context, 'Billetera no encontrada', SnackKind.error);
          case WalletDetailExit.deleted:
            final name = state.wallet.data?.name;
            return _leave(context, name == null ? 'Eliminamos la billetera' : 'Eliminamos «$name»', SnackKind.success);
          case null:
            final failure = state.actionFailure ?? state.wallet.failure;
            if (failure != null) showFailureSnackBar(context, failure);
        }
      },
      builder: (context, state) {
        final wallet = state.wallet.data;
        return Scaffold(
          appBar: AppBar(
            automaticallyImplyLeading: false,
            leading: IconButton(
              tooltip: 'Volver',
              icon: const Icon(Icons.chevron_left_rounded, size: 28),
              onPressed: () => context.canPop() ? context.pop() : context.go(AppRoutes.home),
            ),
            titleSpacing: 0,
            title: Text(wallet?.name ?? 'Billetera', style: AppTypography.title, overflow: TextOverflow.ellipsis),
            bottom: state.deleting
                ? const PreferredSize(preferredSize: Size.fromHeight(2), child: LinearProgressIndicator(minHeight: 2))
                : null,
            actions: [
              if (wallet != null)
                PopupMenuButton<_MenuAction>(
                  tooltip: 'Acciones',
                  icon: const Icon(Icons.more_vert_rounded),
                  onSelected: (action) => _onMenu(context, wallet, action),
                  itemBuilder: (context) => [
                    if (wallet.isOwner) const PopupMenuItem(value: _MenuAction.edit, child: Text('Editar')),
                    const PopupMenuItem(value: _MenuAction.members, child: Text('Miembros')),
                    if (wallet.isOwner) const PopupMenuItem(value: _MenuAction.delete, child: Text('Eliminar')),
                  ],
                ),
            ],
          ),
          floatingActionButton: wallet == null
              ? null
              : FloatingActionButton.extended(
                  key: const ValueKey('transaction-new'),
                  tooltip: 'Registrar un movimiento',
                  onPressed: () => _openTransaction(context, AppRoutes.newTransaction(wallet.walletId)),
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('Movimiento'),
                ),
          body: wallet == null
              ? (state.wallet.status == LoadStatus.failure && state.exit == null
                    ? ErrorView.failure(state.wallet.failure!, onRetry: context.read<WalletDetailCubit>().load)
                    : const LoadingView())
              : RefreshIndicator(
                  onRefresh: () => _refresh(context),
                  child: LoadMoreListener(
                    onLoadMore: context.read<TransactionListCubit>().loadMore,
                    child: _DetailBody(
                      wallet: wallet,
                      onEditFilters: () => _editFilters(context, wallet),
                      onOpenScheduled: () => _openScheduled(context, wallet),
                      onOpenStatistics: () => _openStatistics(context, wallet),
                      onOpenProjection: () => _openProjection(context, wallet),
                      onOpenMembers: () => _openMembers(context, wallet),
                      onOpenTransaction: (transaction) => _openTransaction(
                        context,
                        AppRoutes.transaction(wallet.walletId, transaction.transactionId),
                        extra: TransactionDetailArgs(
                          transaction,
                          canManage: transaction.canBeManagedBy(
                            context.read<SessionCubit>().state.profile?.userId,
                            walletIsOwner: wallet.isOwner,
                          ),
                        ),
                      ),
                      onCreateBudget: () => _openBudgetForm(context, AppRoutes.newBudget(wallet.walletId)),
                      onOpenBudget: (budget) => _openBudgetForm(
                        context,
                        AppRoutes.editBudget(wallet.walletId, budget.budgetId),
                        extra: BudgetEditArgs(
                          budget,
                          canDelete: budget.canBeDeletedBy(
                            context.read<SessionCubit>().state.profile?.userId,
                            walletIsOwner: wallet.isOwner,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
        );
      },
    );
  }
}

class _DetailBody extends StatelessWidget {
  const _DetailBody({
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
              WalletCard(wallet: wallet),
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
              _EntryCard(
                key: const ValueKey('wallet-scheduled'),
                icon: Icons.event_repeat_rounded,
                title: 'Movimientos programados',
                subtitle: 'Ingresos y gastos futuros que se registran solos',
                onTap: onOpenScheduled,
              ),
              const SizedBox(height: AppSpacing.md),
              // Statistics of the wallet (HU-26 · COU-93).
              _EntryCard(
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
                  return _EntryCard(
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

/// Way into a screen of the wallet (programados, estadísticas…): icon,
/// title and a line of explanation, read as one button.
class _EntryCard extends StatelessWidget {
  const _EntryCard({super.key, required this.icon, required this.title, required this.subtitle, required this.onTap});

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      outlined: true,
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: AppSpacing.md),
      onTap: onTap,
      semanticLabel: '$title: $subtitle',
      child: ExcludeSemantics(
        child: Row(
          spacing: AppSpacing.md,
          children: [
            IconTile(icon),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: AppTypography.label),
                  Text(subtitle, style: AppTypography.caption.copyWith(color: context.palette.muted)),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded),
          ],
        ),
      ),
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
    return AppCard(
      key: const ValueKey('wallet-members'),
      outlined: true,
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: AppSpacing.md),
      onTap: onTap,
      semanticLabel: 'Familia: $subtitle',
      child: ExcludeSemantics(
        child: Row(
          spacing: AppSpacing.md,
          children: [
            const IconTile(Icons.group_outlined),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Familia', style: AppTypography.label),
                  Text(subtitle, style: AppTypography.caption.copyWith(color: context.palette.muted)),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded),
          ],
        ),
      ),
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
