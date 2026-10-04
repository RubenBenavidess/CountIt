import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../app/session/session_cubit.dart';
import '../../../app/theme/tokens.dart';
import '../../../data/dtos/budget.dart';
import '../../../shared/state/load_state.dart';
import '../../../shared/utils/dates.dart';
import '../../../shared/widgets/app_button.dart';
import '../../../shared/widgets/app_feedback.dart';
import '../../../shared/widgets/motion.dart';
import '../../../shared/widgets/section_header.dart';
import '../cubit/budget_list_cubit.dart';
import 'widgets/budget_card.dart';

/// «Presupuestos» of the wallet detail (HU-12 · COU-219, COU-220), as one
/// sliver: header, then loading, error, empty or the lazy list of cards.
///
/// Needs a [BudgetListCubit] above it. Owners and accepted members can
/// create and edit budgets (the API decides): [onCreate] and [onOpen] are
/// always offered.
class BudgetSection extends StatelessWidget {
  const BudgetSection({super.key, required this.onCreate, required this.onOpen});

  final VoidCallback onCreate;
  final ValueChanged<Budget> onOpen;

  @override
  Widget build(BuildContext context) {
    // Windows and «empieza el…» use the user's own calendar day.
    final timezone = context.select((SessionCubit c) => c.state.profile?.timezone);
    final today = Dates.userToday(timezone);
    return SliverMainAxisGroup(
      slivers: [
        SliverToBoxAdapter(
          child: SectionHeader(
            title: 'Presupuestos',
            actions: [
              SectionAction(
                key: const ValueKey('budget-new'),
                label: 'Nuevo',
                icon: Icons.add_rounded,
                onPressed: onCreate,
              ),
            ],
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
            ? NoteCard(
                icon: Icons.cloud_off_outlined,
                message: state.failure!.message,
                action: AppButton(
                  label: 'Reintentar',
                  variant: AppButtonVariant.ghost,
                  expand: false,
                  onPressed: context.read<BudgetListCubit>().load,
                ),
              )
            : const SectionLoading(label: 'Cargando presupuestos'),
      );
    }
    if (budgets.isEmpty) {
      return const SliverToBoxAdapter(
        child: NoteCard(
          icon: Icons.pie_chart_outline_rounded,
          message: 'Aún no hay presupuestos. Crea uno para controlar cuánto gastas o ganas en cada categoría.',
        ),
      );
    }
    // The cards of the first load enter one after another.
    return StaggerScope(
      child: SliverList.separated(
        itemCount: budgets.length,
        separatorBuilder: (context, index) => const SizedBox(height: AppSpacing.md),
        itemBuilder: (context, index) {
          final budget = budgets[index];
          return StaggeredEntrance(
            key: ValueKey(budget.budgetId),
            index: index,
            child: BudgetCard(budget: budget, today: today, onTap: () => onOpen(budget)),
          );
        },
      ),
    );
  }
}
