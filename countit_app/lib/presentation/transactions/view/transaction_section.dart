import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../app/session/session_cubit.dart';
import '../../../app/theme/tokens.dart';
import '../../../data/dtos/transaction.dart';
import '../../../shared/utils/dates.dart';
import '../../../shared/widgets/app_button.dart';
import '../../../shared/widgets/app_feedback.dart';
import '../../../shared/widgets/section_header.dart';
import '../cubit/transaction_list_cubit.dart';
import 'widgets/transaction_filters.dart';
import 'widgets/transaction_tile.dart';

/// «Movimientos» of the wallet detail (HU-17 · COU-231, COU-232, COU-235),
/// as one sliver: header, then loading, error, empty or the lazy list grouped
/// by day, with a footer for the next page.
///
/// Needs a [TransactionListCubit] above it; the screen's scroll view calls
/// [TransactionListCubit.loadMore] near the end (see `LoadMoreListener`).
class TransactionSection extends StatelessWidget {
  const TransactionSection({
    super.key,
    this.title = 'Movimientos',
    this.showAuthor = false,
    this.showAuthorOf,
    this.showWallet = false,
    this.onOpen,
    this.onEditFilters,
  });

  final String title;

  /// Shared wallets show who registered each movement.
  final bool showAuthor;

  /// Per movement instead of [showAuthor] (a list of several wallets).
  final bool Function(Transaction transaction)? showAuthorOf;

  /// A list of several wallets names the wallet of each movement.
  final bool showWallet;
  final ValueChanged<Transaction>? onOpen;

  /// Opens the filters sheet; without it the list has no filters.
  final VoidCallback? onEditFilters;

  @override
  Widget build(BuildContext context) {
    // «Hoy»/«Ayer» use the user's own calendar day, like the backend.
    final timezone = context.select((SessionCubit c) => c.state.profile?.timezone);
    final today = Dates.userToday(timezone);
    return SliverMainAxisGroup(
      slivers: [
        SliverToBoxAdapter(
          child: BlocSelector<TransactionListCubit, TransactionListState, TransactionFilter>(
            selector: (state) => state.filter,
            builder: (context, filter) => Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SectionHeader(
                  title: title,
                  actions: [
                    if (onEditFilters != null)
                      SectionAction(
                        key: const ValueKey('transaction-filters'),
                        label: filter.isEmpty ? 'Filtrar' : 'Filtros (${filter.activeCount})',
                        icon: Icons.tune_rounded,
                        onPressed: onEditFilters,
                      ),
                  ],
                ),
                if (!filter.isEmpty) _ActiveFilters(filter: filter),
              ],
            ),
          ),
        ),
        BlocBuilder<TransactionListCubit, TransactionListState>(
          builder: (context, state) => _content(context, state, today),
        ),
      ],
    );
  }

  Widget _content(BuildContext context, TransactionListState state, DateTime today) {
    final cubit = context.read<TransactionListCubit>();
    if (state.isFirstLoad) {
      return SliverToBoxAdapter(
        child: state.status == TransactionListStatus.failure
            ? NoteCard(
                icon: Icons.cloud_off_outlined,
                message: state.failure!.message,
                action: _RetryButton(onPressed: cubit.load),
              )
            : const SectionLoading(label: 'Cargando movimientos'),
      );
    }
    if (state.items.isEmpty && !state.filter.isEmpty) {
      return SliverToBoxAdapter(
        child: NoteCard(
          icon: Icons.filter_alt_off_outlined,
          message: 'No hay movimientos con estos filtros.',
          action: AppButton(
            label: 'Limpiar filtros',
            variant: AppButtonVariant.ghost,
            expand: false,
            onPressed: () => cubit.applyFilter(const TransactionFilter()),
          ),
        ),
      );
    }
    if (state.items.isEmpty) {
      return const SliverToBoxAdapter(
        child: NoteCard(
          icon: Icons.receipt_long_outlined,
          message: 'Aún no hay movimientos. Registra tus ingresos y gastos para ver aquí el historial.',
        ),
      );
    }
    final entries = state.entries;
    final footer = state.hasMore || state.moreFailure != null;
    return SliverList.builder(
      itemCount: entries.length + (footer ? 1 : 0),
      itemBuilder: (context, index) {
        if (index == entries.length) {
          return _Footer(
            key: const ValueKey('transactions-footer'),
            failed: state.moreFailure != null,
            onRetry: () => cubit.loadMore(retry: true),
          );
        }
        return switch (entries[index]) {
          TransactionDayHeader(:final day) => TransactionDayLabel(
            key: ValueKey('day-${Dates.toApi(day)}'),
            day: day,
            today: today,
          ),
          TransactionRow(:final transaction) => TransactionTile(
            key: ValueKey('transaction-${transaction.transactionId}'),
            transaction: transaction,
            showAuthor: showAuthorOf?.call(transaction) ?? showAuthor,
            showWallet: showWallet,
            onTap: onOpen == null ? null : () => onOpen!(transaction),
          ),
        };
      },
    );
  }
}

/// Removable chips of the active filters plus «Limpiar».
class _ActiveFilters extends StatelessWidget {
  const _ActiveFilters({required this.filter});

  final TransactionFilter filter;

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<TransactionListCubit>();
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Wrap(
        spacing: AppSpacing.sm,
        runSpacing: AppSpacing.xs,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          for (final active in filter.active)
            InputChip(
              key: ValueKey('filter-${active.key}'),
              label: Text(active.label),
              deleteButtonTooltipMessage: 'Quitar filtro ${active.label}',
              onDeleted: () => cubit.applyFilter(active.without),
            ),
          TextButton(
            onPressed: () => cubit.applyFilter(const TransactionFilter()),
            style: TextButton.styleFrom(minimumSize: const Size(AppSizes.iconButton, AppSizes.iconButton)),
            child: const Text('Limpiar'),
          ),
        ],
      ),
    );
  }
}

class _RetryButton extends StatelessWidget {
  const _RetryButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) =>
      AppButton(label: 'Reintentar', variant: AppButtonVariant.ghost, expand: false, onPressed: onPressed);
}

/// End of the loaded pages: a spinner while the next one loads, or a retry.
class _Footer extends StatelessWidget {
  const _Footer({super.key, required this.failed, required this.onRetry});

  final bool failed;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
      child: Center(
        child: failed
            ? Column(
                spacing: AppSpacing.sm,
                children: [
                  const Text('No pudimos cargar más movimientos.', style: AppTypography.caption),
                  _RetryButton(onPressed: onRetry),
                ],
              )
            : Semantics(
                label: 'Cargando más movimientos',
                child: const SizedBox.square(dimension: 24, child: CircularProgressIndicator(strokeWidth: 2.5)),
              ),
      ),
    );
  }
}
