import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router/app_router.dart';
import '../../../app/session/session_cubit.dart';
import '../../../app/theme/app_theme.dart';
import '../../../app/theme/tokens.dart';
import '../../../shared/widgets/app_button.dart';
import '../../../shared/widgets/app_card.dart';
import '../../../shared/widgets/app_dialogs.dart';
import 'plan_details.dart';

/// Upsell after a plan quota error (`<x>_limit_exceeded`, 409): the backend
/// [message] plus what the current plan includes.
///
/// [title] changes the heading for a missing feature (403
/// `feature_not_in_plan`) instead of a full quota.
///
/// There is no self-service upgrade in the API (plans are assigned by a
/// superadmin), so the sheet explains, links to the plans screen and closes.
/// The global `403 feature_not_in_plan` handler opens it too (COU-183).
Future<void> showPlanUpsell(
  BuildContext context, {
  required String message,
  String title = 'Alcanzaste el límite de tu plan',
}) {
  final plan = context.read<SessionCubit>().state.profile?.plan;
  return showAppBottomSheet<void>(
    context,
    title: title,
    builder: (context) {
      final muted = context.palette.muted;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: AppSpacing.lg,
        children: [
          Row(
            spacing: 14,
            children: [
              const IconTile(Icons.workspace_premium_outlined, size: 48),
              Expanded(child: Text(message, style: AppTypography.body)),
            ],
          ),
          if (plan != null)
            AppCard(
              outlined: true,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: AppSpacing.xs,
                children: [
                  Text('TU PLAN: ${plan.name.toUpperCase()}', style: AppTypography.overline.copyWith(color: muted)),
                  for (final quota in planQuotas(plan))
                    Row(
                      children: [
                        Expanded(
                          child: Text(quota.label, style: AppTypography.caption.copyWith(color: muted)),
                        ),
                        Text(quota.value, style: AppTypography.label),
                      ],
                    ),
                ],
              ),
            ),
          Text(
            'Con un plan superior tendrás más espacio. Escríbenos para cambiar de plan.',
            style: AppTypography.caption.copyWith(color: muted),
          ),
          AppButton(
            label: 'Ver planes',
            variant: AppButtonVariant.secondary,
            onPressed: () {
              final router = GoRouter.maybeOf(context);
              Navigator.of(context).pop();
              unawaited(router?.push<void>(AppRoutes.plans));
            },
          ),
          AppButton(label: 'Entendido', onPressed: () => Navigator.of(context).pop()),
        ],
      );
    },
  );
}
