import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router/app_router.dart';
import '../../../app/session/session_cubit.dart';
import '../../../app/theme/app_theme.dart';
import '../../../app/theme/tokens.dart';
import '../../../data/dtos/profile.dart';
import '../../../data/repositories/plan_repository.dart';
import '../../../shared/utils/dates.dart';
import '../../../shared/widgets/app_button.dart';
import '../../../shared/widgets/app_card.dart';
import '../../../shared/widgets/app_feedback.dart';
import '../../../shared/widgets/app_layout.dart';
import '../cubit/plan_catalog_cubit.dart';
import 'plan_details.dart';
import 'widgets/plan_widgets.dart';

/// «Mi plan» (HU-28 · COU-113): the active plan of `get_my_profile`, its
/// validity, limits and features, with the expiry notice (COU-117).
///
/// Pull to refresh reloads the profile: a superadmin may have changed the
/// plan, or the daily job moved an expired plan to Regular.
class MyPlanPage extends StatelessWidget {
  const MyPlanPage({super.key});

  @override
  Widget build(BuildContext context) => BlocProvider(
    // Only for the plan description: without the catalogue it is omitted.
    create: (context) => PlanCatalogCubit(context.read<PlanRepository>())..load(),
    child: const _MyPlanView(),
  );
}

class _MyPlanView extends StatelessWidget {
  const _MyPlanView();

  @override
  Widget build(BuildContext context) {
    final profile = context.select((SessionCubit c) => c.state.profile);
    final plan = profile?.plan;
    return Scaffold(
      appBar: const AppTopBar(title: 'Mi plan'),
      body: profile == null
          ? const LoadingView()
          : RefreshIndicator(
              onRefresh: () => Future.wait([
                context.read<SessionCubit>().refreshProfile(),
                context.read<PlanCatalogCubit>().load(refresh: true),
              ]),
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(AppSpacing.screen, AppSpacing.md, AppSpacing.screen, AppSpacing.xxl),
                children: plan == null
                    ? const [
                        EmptyState(
                          icon: Icons.workspace_premium_outlined,
                          title: 'Sin plan activo',
                          message: 'No encontramos un plan activo en tu cuenta. Desliza hacia abajo para actualizar.',
                        ),
                      ]
                    : [_PlanBody(plan: plan, today: Dates.userToday(profile.timezone))],
              ),
            ),
    );
  }
}

class _PlanBody extends StatelessWidget {
  const _PlanBody({required this.plan, required this.today});

  final UserPlan plan;
  final DateTime today;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final price = planPrice(plan);
    final description = context.select((PlanCatalogCubit c) => c.byId(plan.planId)?.description);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: AppSpacing.lg,
      children: [
        PlanExpiryBanner(plan: plan, today: today),
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('TU PLAN', style: AppTypography.overline.copyWith(color: palette.muted)),
              const SizedBox(height: AppSpacing.xs),
              Row(
                spacing: AppSpacing.md,
                children: [
                  Expanded(
                    child: Semantics(header: true, child: Text(plan.name, style: AppTypography.h1)),
                  ),
                  PlanValidityPill(plan: plan, today: today),
                ],
              ),
              if (price != null || (description?.isNotEmpty ?? false)) const SizedBox(height: AppSpacing.xs),
              if (price != null) Text(price, style: AppTypography.label),
              if (description != null && description.isNotEmpty)
                Text(description, style: AppTypography.caption.copyWith(color: palette.muted)),
              const SizedBox(height: AppSpacing.lg),
              Divider(height: 1, color: palette.line),
              const SizedBox(height: AppSpacing.md),
              PlanLimits(plan: plan),
            ],
          ),
        ),
        Text(
          plan.isPaid
              ? 'Al vencer pasarás al plan Regular: no se borra nada, pero terminan las membresías de billeteras '
                    'compartidas que superen sus límites y se pausan las programadas más nuevas que excedan el cupo.'
              : 'Los planes los asigna un administrador. Escríbenos para cambiar de plan.',
          style: AppTypography.caption.copyWith(color: palette.muted),
        ),
        AppButton(
          label: 'Comparar planes',
          icon: Icons.compare_arrows_rounded,
          variant: AppButtonVariant.secondary,
          onPressed: () => context.push(AppRoutes.plans),
        ),
      ],
    );
  }
}
