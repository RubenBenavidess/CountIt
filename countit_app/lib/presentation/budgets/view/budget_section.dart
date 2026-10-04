import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../app/session/session_cubit.dart';
import '../../../app/theme/app_theme.dart';
import '../../../app/theme/tokens.dart';
import '../../../data/dtos/budget.dart';
import '../../../shared/state/load_state.dart';
import '../../../shared/utils/dates.dart';
import '../../../shared/widgets/app_button.dart';
import '../../../shared/widgets/app_card.dart';
import '../cubit/budget_list_cubit.dart';
import 'widgets/budget_card.dart';

/// «Presupuestos» of the wallet detail (HU-12 · COU-219, COU-220), as one
/// sliver: header, then loading, error, empty or the lazy list of cards.
///
/// Needs a [BudgetListCubit] above it.
class BudgetSection extends StatelessWidget {
  const BudgetSection({super.key});

  @override
  Widget build(BuildContext context) {
    // Windows and «empieza el…» use the user's own calendar day.
    final timezone = context.select((SessionCubit c) => c.state.profile?.timezone);
    final today = Dates.userToday(timezone);
    return SliverMainAxisGroup(
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.md),
            child: Semantics(header: true, child: const Text('Presupuestos', style: AppTypography.h2)),
          ),
        ),
        BlocBuilder<BudgetListCubit, LoadState<List<Budget>>>(
          builder: (context, state) => _content(context, state, today),
        ),
      ],
    );
  }

  Widget _content(BuildContext context, LoadState<List<Budget>> state, DateTime today) {
    final budgets = state.data;
    if (budgets == null) {
      return SliverToBoxAdapter(
        child: state.status == LoadStatus.failure
            ? _Note(
                icon: Icons.cloud_off_outlined,
                message: state.failure!.message,
                action: AppButton(
                  label: 'Reintentar',
                  variant: AppButtonVariant.ghost,
                  expand: false,
                  onPressed: context.read<BudgetListCubit>().load,
                ),
              )
            : const _Loading(),
      );
    }
    if (budgets.isEmpty) {
      return const SliverToBoxAdapter(
        child: _Note(
          icon: Icons.pie_chart_outline_rounded,
          message: 'Aún no hay presupuestos. Crea uno para controlar cuánto gastas o ganas en cada categoría.',
        ),
      );
    }
    return SliverList.separated(
      itemCount: budgets.length,
      separatorBuilder: (context, index) => const SizedBox(height: AppSpacing.md),
      itemBuilder: (context, index) {
        final budget = budgets[index];
        return BudgetCard(key: ValueKey(budget.budgetId), budget: budget, today: today);
      },
    );
  }
}

/// Placeholder card while the first load runs (the rest of the screen is usable).
class _Loading extends StatelessWidget {
  const _Loading();

  @override
  Widget build(BuildContext context) {
    return AppCard(
      outlined: true,
      child: Center(
        child: Semantics(
          label: 'Cargando presupuestos',
          child: const SizedBox.square(dimension: 24, child: CircularProgressIndicator(strokeWidth: 2.5)),
        ),
      ),
    );
  }
}

/// Outlined card with an icon, a message and an optional action (empty, error).
class _Note extends StatelessWidget {
  const _Note({required this.icon, required this.message, this.action});

  final IconData icon;
  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      outlined: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: AppSpacing.md,
        children: [
          Row(
            spacing: AppSpacing.md,
            children: [
              IconTile(icon),
              Expanded(
                child: Text(message, style: AppTypography.caption.copyWith(color: context.palette.muted)),
              ),
            ],
          ),
          ?action,
        ],
      ),
    );
  }
}
