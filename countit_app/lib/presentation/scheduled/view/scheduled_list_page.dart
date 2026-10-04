import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router/app_router.dart';
import '../../../app/session/session_cubit.dart';
import '../../../app/theme/app_theme.dart';
import '../../../app/theme/tokens.dart';
import '../../../data/dtos/scheduled_transaction.dart';
import '../../../data/dtos/wallet.dart';
import '../../../data/repositories/scheduled_transaction_repository.dart';
import '../../../shared/state/load_state.dart';
import '../../../shared/widgets/app_button.dart';
import '../../../shared/widgets/app_feedback.dart';
import '../../../shared/widgets/app_layout.dart';
import '../../plans/view/plan_upsell_sheet.dart';
import '../cubit/scheduled_list_cubit.dart';
import 'scheduled_form_page.dart';
import 'widgets/scheduled_quota_card.dart';
import 'widgets/scheduled_tile.dart';

/// «Programados» of a wallet (HU-16/HU-20 · COU-88, COU-156): its running
/// and paused rules with their frequency and next run, and the plan quota.
class ScheduledListPage extends StatelessWidget {
  const ScheduledListPage({super.key, required this.wallet});

  /// The wallet the detail screen loaded (name, ownership, shared).
  final Wallet wallet;

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) => ScheduledListCubit(
        context.read<ScheduledTransactionRepository>(),
        walletId: wallet.walletId,
        userId: context.read<SessionCubit>().state.profile?.userId,
      )..load(),
      child: _ScheduledListView(wallet: wallet),
    );
  }
}

class _ScheduledListView extends StatelessWidget {
  const _ScheduledListView({required this.wallet});

  final Wallet wallet;

  /// HU-16 gating (COU-156): with the quota known to be full, the plans
  /// sheet explains it instead of a form the API would reject (409).
  Future<void> _create(BuildContext context) async {
    final cubit = context.read<ScheduledListCubit>();
    final quota = ScheduledQuota.of(context.read<SessionCubit>().state.profile?.plan, cubit.state.usage);
    if (!quota.canCreate) return showPlanUpsell(context, message: quota.limitMessage);
    final saved = await context.push<bool>(AppRoutes.newScheduled(wallet.walletId));
    if (saved == true && !cubit.isClosed) unawaited(cubit.load());
  }

  /// HU-20: only the author or the wallet owner may edit (the API decides).
  Future<void> _edit(BuildContext context, ScheduledTransaction rule) async {
    final cubit = context.read<ScheduledListCubit>();
    final saved = await context.push<bool>(
      AppRoutes.editScheduled(wallet.walletId, rule.scheduledTransactionId),
      extra: ScheduledEditArgs(rule, canDelete: true),
    );
    if (saved == true && !cubit.isClosed) unawaited(cubit.load());
  }

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<ScheduledListCubit>();
    final plan = context.select((SessionCubit c) => c.state.profile?.plan);
    return Scaffold(
      appBar: const AppTopBar(title: 'Programados'),
      floatingActionButton: FloatingActionButton.extended(
        key: const ValueKey('scheduled-new'),
        tooltip: 'Programar un ingreso o gasto',
        onPressed: () => _create(context),
        icon: const Icon(Icons.add_rounded),
        label: const Text('Programar'),
      ),
      body: RefreshIndicator(
        onRefresh: cubit.load,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(AppSpacing.screen, AppSpacing.sm, AppSpacing.screen, 0),
              sliver: SliverList.list(
                children: [
                  Text(
                    'Ingresos y gastos que se registran solos en «${wallet.name}» en su fecha.',
                    style: AppTypography.body.copyWith(color: context.palette.muted),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  BlocSelector<ScheduledListCubit, ScheduledListState, ScheduledUsage?>(
                    selector: (state) => state.usage,
                    builder: (context, usage) {
                      final quota = ScheduledQuota.of(plan, usage);
                      if (quota.limit == null || usage == null) return const SizedBox.shrink();
                      return Padding(
                        padding: const EdgeInsets.only(bottom: AppSpacing.lg),
                        child: ScheduledQuotaCard(quota: quota),
                      );
                    },
                  ),
                ],
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(AppSpacing.screen, 0, AppSpacing.screen, 96),
              sliver: BlocBuilder<ScheduledListCubit, ScheduledListState>(
                buildWhen: (previous, current) => previous.rules != current.rules,
                builder: (context, state) => _rules(context, state.rules),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _rules(BuildContext context, LoadState<List<ScheduledTransaction>> state) {
    final rules = state.data;
    final userId = context.read<SessionCubit>().state.profile?.userId;
    if (rules == null) {
      return SliverFillRemaining(
        hasScrollBody: false,
        child: state.status == LoadStatus.failure
            ? ErrorView(message: state.failure!.message, onRetry: context.read<ScheduledListCubit>().load)
            : const LoadingView(message: 'Cargando programados'),
      );
    }
    if (rules.isEmpty) {
      return const SliverFillRemaining(
        hasScrollBody: false,
        child: EmptyState(
          icon: Icons.event_repeat_rounded,
          title: 'Sin movimientos programados',
          message:
              'Programa un ingreso o gasto futuro, único o recurrente (sueldo, arriendo, suscripciones), '
              'y se registrará solo en su fecha.',
        ),
      );
    }
    return SliverMainAxisGroup(
      slivers: [
        if (state.status == LoadStatus.failure)
          SliverToBoxAdapter(
            child: NoteCard(
              icon: Icons.cloud_off_outlined,
              message: state.failure!.message,
              action: AppButton(
                label: 'Reintentar',
                variant: AppButtonVariant.ghost,
                expand: false,
                onPressed: context.read<ScheduledListCubit>().load,
              ),
            ),
          ),
        SliverList.builder(
          itemCount: rules.length,
          itemBuilder: (context, index) {
            final rule = rules[index];
            final canManage = rule.canBeManagedBy(userId, walletIsOwner: wallet.isOwner);
            return ScheduledTile(
              key: ValueKey(rule.scheduledTransactionId),
              rule: rule,
              showAuthor: wallet.isShared,
              onTap: canManage ? () => _edit(context, rule) : null,
            );
          },
        ),
      ],
    );
  }
}
