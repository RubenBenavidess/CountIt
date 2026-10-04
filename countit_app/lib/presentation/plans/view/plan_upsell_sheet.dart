import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../app/session/session_cubit.dart';
import '../../../app/theme/app_theme.dart';
import '../../../app/theme/tokens.dart';
import '../../../shared/widgets/app_button.dart';
import '../../../shared/widgets/app_card.dart';
import '../../../shared/widgets/app_dialogs.dart';
import '../../profile/view/plan_details.dart';

/// Upsell after a plan quota error (`<x>_limit_exceeded`, 409): the backend
/// [message] plus what the current plan includes.
///
/// There is no plan catalogue or self-service upgrade in the API yet (plans
/// are assigned by an administrator), so the sheet explains and closes.
Future<void> showPlanUpsell(BuildContext context, {required String message}) {
  final plan = context.read<SessionCubit>().state.profile?.plan;
  return showAppBottomSheet<void>(
    context,
    title: 'Alcanzaste el límite de tu plan',
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
          AppButton(label: 'Entendido', onPressed: () => Navigator.of(context).pop()),
        ],
      );
    },
  );
}
