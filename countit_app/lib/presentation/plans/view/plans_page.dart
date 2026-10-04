import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../app/session/session_cubit.dart';
import '../../../app/theme/app_theme.dart';
import '../../../app/theme/tokens.dart';
import '../../../data/dtos/plan_offer.dart';
import '../../../data/repositories/plan_repository.dart';
import '../../../shared/state/load_state.dart';
import '../../../shared/widgets/app_card.dart';
import '../../../shared/widgets/app_feedback.dart';
import '../../../shared/widgets/app_layout.dart';
import '../cubit/plan_catalog_cubit.dart';
import 'plan_details.dart';
import 'widgets/plan_widgets.dart';

/// Informative plans screen (COU-124): what each plan includes, the current
/// one marked. There is no self-service upgrade (plans are assigned by a
/// superadmin), so it only explains how to get one.
class PlansPage extends StatelessWidget {
  const PlansPage({super.key});

  @override
  Widget build(BuildContext context) => BlocProvider(
    create: (context) => PlanCatalogCubit(context.read<PlanRepository>())..load(),
    child: const _PlansView(),
  );
}

class _PlansView extends StatelessWidget {
  const _PlansView();

  @override
  Widget build(BuildContext context) {
    final currentId = context.select((SessionCubit c) => c.state.profile?.plan?.planId);
    final cubit = context.read<PlanCatalogCubit>();
    return Scaffold(
      appBar: const AppTopBar(title: 'Planes'),
      body: BlocBuilder<PlanCatalogCubit, LoadState<List<PlanOffer>>>(
        builder: (context, state) => LoadStateView<List<PlanOffer>>(
          state: state,
          onRetry: () => cubit.load(refresh: true),
          builder: (context, offers) => RefreshIndicator(
            onRefresh: () => cubit.load(refresh: true),
            child: ListView.separated(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(AppSpacing.screen, AppSpacing.md, AppSpacing.screen, AppSpacing.xxl),
              itemCount: offers.length + 1,
              separatorBuilder: (context, index) => const SizedBox(height: AppSpacing.lg),
              itemBuilder: (context, index) {
                if (index == offers.length) {
                  return Text(
                    'Por ahora no hay pagos en la app: los planes los asigna un administrador. '
                    'Escríbenos para cambiar de plan. Los límites los aplica siempre el servidor.',
                    style: AppTypography.caption.copyWith(color: context.palette.muted),
                  );
                }
                final offer = offers[index];
                return _PlanOfferCard(
                  key: ValueKey('plan-offer-${offer.planId}'),
                  offer: offer,
                  current: offer.planId == currentId,
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _PlanOfferCard extends StatelessWidget {
  const _PlanOfferCard({super.key, required this.offer, required this.current});

  final PlanOffer offer;
  final bool current;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final price = planPrice(offer.plan);
    return AppCard(
      outlined: !current,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            spacing: AppSpacing.md,
            children: [
              Expanded(
                child: Semantics(
                  container: true,
                  header: true,
                  label: current ? '${offer.name}, tu plan actual' : offer.name,
                  excludeSemantics: true,
                  child: Text(offer.name, style: AppTypography.title),
                ),
              ),
              if (current) const AppBadge('Tu plan', tone: BadgeTone.pro),
            ],
          ),
          if (price != null) Text(price, style: AppTypography.label),
          const SizedBox(height: AppSpacing.xs),
          if (offer.description.isNotEmpty)
            Text(offer.description, style: AppTypography.caption.copyWith(color: palette.muted)),
          const SizedBox(height: AppSpacing.md),
          Divider(height: 1, color: palette.line),
          const SizedBox(height: AppSpacing.md),
          PlanLimits(plan: offer.plan),
        ],
      ),
    );
  }
}
