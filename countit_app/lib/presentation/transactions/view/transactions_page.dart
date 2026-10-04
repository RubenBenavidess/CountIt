import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../app/errors/app_failure.dart';
import '../../../app/router/app_router.dart';
import '../../../app/session/session_cubit.dart';
import '../../../app/theme/app_theme.dart';
import '../../../app/theme/tokens.dart';
import '../../../data/dtos/budget.dart';
import '../../../data/dtos/scheduled_transaction.dart';
import '../../../data/dtos/transaction.dart';
import '../../../data/dtos/wallet.dart';
import '../../../data/repositories/budget_repository.dart';
import '../../../data/repositories/family_repository.dart';
import '../../../data/repositories/transaction_repository.dart';
import '../../../data/repositories/wallet_repository.dart';
import '../../../shared/state/load_state.dart';
import '../../../shared/utils/dates.dart';
import '../../../shared/widgets/app_dialogs.dart';
import '../../../shared/widgets/app_fields.dart';
import '../../../shared/widgets/app_layout.dart';
import '../../../shared/widgets/load_more_listener.dart';
import '../../home/cubit/wallets_cubit.dart';
import '../../shell/view/visible_tab_listener.dart';
import '../../wallets/view/widgets/wallet_type_icon.dart';
import '../cubit/transaction_list_cubit.dart';
import 'transaction_detail_page.dart';
import 'transaction_section.dart';
import 'widgets/transaction_filters.dart';

/// «Movimientos» tab: the movements of every wallet the user can read (own
/// and shared) or of the one picked, with the wallet list's filters,
/// infinite scroll, detail and «Movimiento» (choosing the wallet).
///
/// `v_transactions` is `security_invoker`: without `wallet_id` RLS already
/// limits the rows to the readable wallets, so one keyset query serves both.
class TransactionsPage extends StatelessWidget {
  const TransactionsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      providers: [
        BlocProvider(create: (context) => WalletsCubit(context.read<WalletRepository>())..load()),
        BlocProvider(create: (context) => TransactionListCubit(context.read<TransactionRepository>())..load()),
      ],
      child: const _TransactionsView(),
    );
  }
}

/// Value of «Todas las billeteras» in the selector (wallet ids start at 1).
const _allWallets = 0;

class _TransactionsView extends StatelessWidget {
  const _TransactionsView();

  static Wallet? _walletOf(BuildContext context, int walletId) {
    for (final wallet in context.read<WalletsCubit>().state.data ?? const <Wallet>[]) {
      if (wallet.walletId == walletId) return wallet;
    }
    return null;
  }

  /// Movements and balances may have changed in another tab or device.
  Future<void> _refresh(BuildContext context) =>
      Future.wait([context.read<TransactionListCubit>().load(), context.read<WalletsCubit>().load()]);

  /// Detail or form: a save or a deletion changes the list. A new movement
  /// with a future date comes back as a draft to schedule (HU-16 · COU-151).
  Future<void> _push(BuildContext context, String location, {required int walletId, Object? extra}) async {
    final result = await context.push<Object?>(location, extra: extra);
    if (!context.mounted) return;
    if (result == true) {
      unawaited(_refresh(context));
    } else if (result is ScheduledTransactionInput) {
      unawaited(context.push<bool>(AppRoutes.newScheduled(walletId), extra: result));
    }
  }

  void _open(BuildContext context, Transaction transaction) {
    final wallet = _walletOf(context, transaction.walletId);
    final userId = context.read<SessionCubit>().state.profile?.userId;
    unawaited(
      _push(
        context,
        AppRoutes.transaction(transaction.walletId, transaction.transactionId),
        walletId: transaction.walletId,
        extra: TransactionDetailArgs(
          transaction,
          canManage: transaction.canBeManagedBy(userId, walletIsOwner: wallet?.isOwner ?? false),
        ),
      ),
    );
  }

  /// «Movimiento»: in the wallet picked, or asking which one.
  Future<void> _create(BuildContext context) async {
    final wallets = context.read<WalletsCubit>().state.data ?? const <Wallet>[];
    final selected = context.read<TransactionListCubit>().walletId;
    final walletId = selected ?? (wallets.length == 1 ? wallets.single.walletId : await pickWallet(context, wallets));
    if (walletId == null || !context.mounted) return;
    await _push(context, AppRoutes.newTransaction(walletId), walletId: walletId);
  }

  /// Filters sheet: budget and author only make sense within one wallet.
  Future<void> _editFilters(BuildContext context) async {
    final list = context.read<TransactionListCubit>();
    final walletId = list.walletId;
    final wallet = walletId == null ? null : _walletOf(context, walletId);
    var budgets = const <Budget>[];
    var authors = const <String, String>{};
    if (walletId != null) {
      final budgetRepository = context.read<BudgetRepository>();
      final families = context.read<FamilyRepository>();
      // The sheet never waits for a failing request: it offers what it has.
      try {
        budgets = await budgetRepository.listByWallet(walletId);
      } on AppFailure {
        budgets = const [];
      }
      if (wallet?.isShared ?? false) {
        authors = {...list.state.knownAuthors};
        try {
          for (final member in await families.membersOf(walletId)) {
            if (member.isOwner || member.isAccepted) authors[member.userId] = member.name;
          }
        } on AppFailure {
          // The authors seen in the list remain.
        }
      }
    }
    if (!context.mounted) return;
    final filter = await showTransactionFilters(
      context,
      current: list.state.filter,
      budgets: budgets,
      authors: authors,
      showBudget: walletId != null,
      today: Dates.userToday(context.read<SessionCubit>().state.profile?.timezone),
    );
    if (filter != null && !list.isClosed) unawaited(list.applyFilter(filter));
  }

  @override
  Widget build(BuildContext context) {
    final hasWallets = context.select((WalletsCubit c) => c.state.data?.isNotEmpty ?? false);
    final walletId = context.select((TransactionListCubit c) => c.walletId);
    const padding = EdgeInsets.symmetric(horizontal: AppSpacing.screen);
    return VisibleTabListener(
      // Back on this tab: what changed elsewhere shows up without a pull.
      onVisible: () => unawaited(_refresh(context)),
      child: Scaffold(
        appBar: const AppTopBar(title: 'Movimientos', showBack: false),
        floatingActionButton: hasWallets
            ? FloatingActionButton.extended(
                key: const ValueKey('transactions-new'),
                tooltip: 'Registrar un movimiento',
                onPressed: () => unawaited(_create(context)),
                icon: const Icon(Icons.add_rounded),
                label: const Text('Movimiento'),
              )
            : null,
        body: RefreshIndicator(
          onRefresh: () => _refresh(context),
          child: LoadMoreListener(
            onLoadMore: context.read<TransactionListCubit>().loadMore,
            child: CustomScrollView(
              key: const PageStorageKey('transactions-tab'),
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                const SliverPadding(
                  padding: EdgeInsets.fromLTRB(AppSpacing.screen, AppSpacing.sm, AppSpacing.screen, AppSpacing.md),
                  sliver: SliverToBoxAdapter(child: _WalletFilter()),
                ),
                SliverPadding(
                  // Room below the last movement for the floating button.
                  padding: padding.copyWith(bottom: 96),
                  sliver: TransactionSection(
                    title: 'Historial',
                    showWallet: walletId == null,
                    showAuthorOf: (t) => _walletOf(context, t.walletId)?.isShared ?? false,
                    onOpen: (t) => _open(context, t),
                    onEditFilters: () => unawaited(_editFilters(context)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// «Billetera»: all of them or one; while the wallets load it waits.
class _WalletFilter extends StatelessWidget {
  const _WalletFilter();

  @override
  Widget build(BuildContext context) {
    final wallets = context.select((WalletsCubit c) => c.state);
    final walletId = context.select((TransactionListCubit c) => c.walletId);
    final data = wallets.data ?? const <Wallet>[];
    return AppDropdownField<int>(
      label: 'Billetera',
      hint: wallets.status == LoadStatus.failure ? 'No pudimos cargar tus billeteras' : 'Cargando billeteras…',
      options: [
        if (data.isNotEmpty) const AppOption(_allWallets, 'Todas las billeteras'),
        for (final wallet in data) AppOption(wallet.walletId, wallet.name),
      ],
      value: data.isEmpty ? null : (walletId ?? _allWallets),
      enabled: data.length > 1,
      onChanged: (id) {
        if (id == null) return;
        unawaited(context.read<TransactionListCubit>().selectWallet(id == _allWallets ? null : id));
      },
    );
  }
}

/// Asks in which wallet to register a movement; null when dismissed.
Future<int?> pickWallet(BuildContext context, List<Wallet> wallets) => showAppBottomSheet<int>(
  context,
  title: '¿En qué billetera?',
  builder: (sheetContext) => Flexible(
    child: ListView(
      shrinkWrap: true,
      children: [
        for (final wallet in wallets)
          ListTile(
            key: ValueKey('pick-wallet-${wallet.walletId}'),
            contentPadding: EdgeInsets.zero,
            leading: Icon(wallet.type.icon, color: sheetContext.palette.muted),
            title: Text(wallet.name, style: AppTypography.label, overflow: TextOverflow.ellipsis),
            subtitle: wallet.isOwner
                ? null
                : Text('Compartida por ${wallet.ownerName ?? 'otro usuario'}', style: AppTypography.caption),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => Navigator.of(sheetContext).pop(wallet.walletId),
          ),
      ],
    ),
  ),
);
