import 'package:flutter/material.dart';

import '../../../../app/theme/app_theme.dart';
import '../../../../app/theme/tokens.dart';
import '../../../../data/dtos/profile.dart';
import '../../../../shared/widgets/app_banner.dart';
import '../plan_details.dart';

/// «LÍMITES» and «FUNCIONES» of a plan: quota rows and feature chips.
class PlanLimits extends StatelessWidget {
  const PlanLimits({super.key, required this.plan});

  final UserPlan plan;

  @override
  Widget build(BuildContext context) {
    final muted = context.palette.muted;
    final quotas = planQuotas(plan);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (quotas.isNotEmpty) ...[
          Text('LÍMITES', style: AppTypography.overline.copyWith(color: muted)),
          const SizedBox(height: AppSpacing.xs),
          for (final quota in quotas) PlanQuotaRow(quota: quota),
          const SizedBox(height: AppSpacing.md),
        ],
        Text('FUNCIONES', style: AppTypography.overline.copyWith(color: muted)),
        const SizedBox(height: AppSpacing.sm),
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: [for (final feature in planFeatures(plan)) PlanFeatureChip(feature: feature)],
        ),
      ],
    );
  }
}

/// «Billeteras ··· 10»: icon tile, label on the left, value on the right.
class PlanQuotaRow extends StatelessWidget {
  const PlanQuotaRow({super.key, required this.quota});

  final PlanQuota quota;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return MergeSemantics(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs + 2),
        child: Row(
          spacing: AppSpacing.md,
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(color: palette.surface2, borderRadius: BorderRadius.circular(AppRadii.sm)),
              child: Icon(quota.icon, size: 18, color: AppColors.lavender),
            ),
            Expanded(child: Text(quota.label, style: AppTypography.caption.copyWith(fontSize: 14))),
            Text(quota.value, style: AppTypography.label),
          ],
        ),
      ),
    );
  }
}

/// Feature badge: check when included, lock (muted) when it needs another plan.
class PlanFeatureChip extends StatelessWidget {
  const PlanFeatureChip({super.key, required this.feature});

  final PlanFeature feature;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final color = feature.included ? Theme.of(context).colorScheme.onSurface : palette.muted;
    return Semantics(
      container: true,
      label: '${feature.label}: ${feature.included ? 'incluida' : 'no incluida'}',
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.xs + 2),
        decoration: BoxDecoration(
          color: feature.included ? palette.surface2 : null,
          border: Border.all(color: palette.line),
          borderRadius: BorderRadius.circular(AppRadii.pill),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          spacing: AppSpacing.xs + 2,
          children: [
            Icon(
              feature.included ? Icons.check_circle_rounded : Icons.lock_outline_rounded,
              size: 16,
              color: feature.included ? AppColors.lavender : palette.muted,
            ),
            Flexible(
              child: Text(feature.label, style: AppTypography.caption.copyWith(color: color)),
            ),
          ],
        ),
      ),
    );
  }
}

/// Small rounded label with an icon («Vence el 4 oct 2027»); [warn] for an expiring plan.
class PlanPill extends StatelessWidget {
  const PlanPill({super.key, required this.icon, required this.text, this.warn = false});

  final IconData icon;
  final String text;
  final bool warn;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final foreground = warn ? palette.expense : palette.muted;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm + 2, vertical: AppSpacing.xs),
      decoration: BoxDecoration(
        color: warn ? AppColors.warnBackground : palette.surface2,
        borderRadius: BorderRadius.circular(AppRadii.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        spacing: AppSpacing.xs,
        children: [
          Icon(icon, size: 14, color: foreground),
          Flexible(
            child: Text(text, style: AppTypography.caption.copyWith(fontSize: 12, color: foreground)),
          ),
        ],
      ),
    );
  }
}

/// Validity pill of a paid plan (nothing for the free plan).
class PlanValidityPill extends StatelessWidget {
  const PlanValidityPill({super.key, required this.plan, required this.today});

  final UserPlan plan;
  final DateTime today;

  @override
  Widget build(BuildContext context) {
    final label = planValidityLabel(plan, today);
    if (label == null) return const SizedBox.shrink();
    return PlanPill(icon: Icons.event_outlined, text: label, warn: plan.expiryOn(today).needsNotice);
  }
}

/// Notice of a plan about to expire or already expired (COU-117); nothing
/// otherwise. [action] links to «Mi plan» from other screens.
class PlanExpiryBanner extends StatelessWidget {
  const PlanExpiryBanner({super.key, required this.plan, required this.today, this.action});

  final UserPlan plan;
  final DateTime today;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final message = planExpiryMessage(plan, today);
    if (message == null) return const SizedBox.shrink();
    final expired = plan.expiryOn(today).status == PlanExpiryStatus.expired;
    return AppBanner(
      key: const ValueKey('plan-expiry-banner'),
      message: message,
      tone: expired ? BannerTone.error : BannerTone.info,
      action: action,
    );
  }
}
