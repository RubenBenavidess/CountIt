import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router/app_router.dart';
import '../../../app/session/session_cubit.dart';
import '../../../app/theme/app_theme.dart';
import '../../../app/theme/tokens.dart';
import '../../../data/dtos/budget.dart';
import '../../../data/dtos/transaction.dart';
import '../../../data/dtos/wallet.dart';
import '../../../data/repositories/budget_repository.dart';
import '../../../data/repositories/transaction_repository.dart';
import '../../../data/repositories/wallet_repository.dart';
import '../../../shared/state/load_state.dart';
import '../../../shared/utils/dates.dart';
import '../../../shared/utils/money.dart';
import '../../../shared/widgets/app_card.dart';
import '../../../shared/widgets/app_dialogs.dart';
import '../../../shared/widgets/app_feedback.dart';
import '../../../shared/widgets/load_more_listener.dart';
import '../../account/view/reauth_sheet.dart';
import '../../budgets/cubit/budget_list_cubit.dart';
import '../../budgets/view/budget_form_page.dart';
import '../../budgets/view/budget_section.dart';
import '../../transactions/cubit/transaction_list_cubit.dart';
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

  /// Transaction form (register or edit): a save changes the balance, the
  /// budgets' progress and the list, so all three reload.
  Future<void> _openTransactionForm(BuildContext context, String location, {Object? extra}) async {
    final saved = await context.push<bool>(location, extra: extra);
    if (saved == true && context.mounted) unawaited(_refresh(context));
  }

  /// Filters sheet (COU-233): budgets come from the section above; authors
  /// only matter in shared wallets.
  Future<void> _editFilters(BuildContext context, Wallet wallet) async {
    final list = context.read<TransactionListCubit>();
    final filter = await showTransactionFilters(
      context,
      current: list.state.filter,
      budgets: context.read<BudgetListCubit>().state.data ?? const [],
      authors: wallet.isShared ? list.state.knownAuthors : const {},
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
        showAppSnackBar(context, 'Muy pronto podrás compartir esta billetera.');
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
                  onPressed: () => _openTransactionForm(context, AppRoutes.newTransaction(wallet.walletId)),
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
                      onOpenTransaction: (transaction) {
                        final userId = context.read<SessionCubit>().state.profile?.userId;
                        if (!transaction.canBeManagedBy(userId, walletIsOwner: wallet.isOwner)) return;
                        _openTransactionForm(
                          context,
                          AppRoutes.editTransaction(wallet.walletId, transaction.transactionId),
                          extra: transaction,
                        );
                      },
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
  });

  final Wallet wallet;
  final ValueChanged<Transaction> onOpenTransaction;
  final VoidCallback onEditFilters;
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

/// Totals of the wallet; the projection only when the plan includes it.
class _Figures extends StatelessWidget {
  const _Figures({required this.wallet});

  final Wallet wallet;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final rows = <(String, String, Color?)>[
      ('Tipo', wallet.type.displayLabel, null),
      ('Saldo inicial', Money.format(wallet.initialBalance), null),
      ('Ingresos totales', Money.signed(wallet.totalIncome, income: true), palette.income),
      ('Gastos totales', Money.signed(wallet.totalExpenses, income: false), palette.expense),
      ('Ingresos del mes', Money.signed(wallet.monthIncome, income: true), palette.income),
      ('Gastos del mes', Money.signed(wallet.monthExpenses, income: false), palette.expense),
      if (wallet.projectedBalance != null)
        ('Saldo proyectado a fin de mes', Money.format(wallet.projectedBalance!), null),
    ];
    return AppCard(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          for (final (index, (label, value, color)) in rows.indexed) ...[
            if (index > 0) Divider(height: 1, color: palette.line),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: 14),
              child: Row(
                spacing: AppSpacing.md,
                children: [
                  Expanded(
                    child: Text(label, style: AppTypography.caption.copyWith(color: palette.muted)),
                  ),
                  Text(value, style: AppTypography.money.copyWith(fontSize: 15, color: color)),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
