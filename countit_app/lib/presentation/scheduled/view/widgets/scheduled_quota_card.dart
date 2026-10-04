import 'package:equatable/equatable.dart';
import 'package:flutter/material.dart';

import '../../../../app/theme/app_theme.dart';
import '../../../../app/theme/tokens.dart';
import '../../../../data/dtos/profile.dart';
import '../../../../data/dtos/scheduled_transaction.dart';
import '../../../../shared/widgets/app_card.dart';

/// The plan quota of scheduled rules (HU-16: Regular 3, Contador 10,
/// Profesional 50) against what the caller uses. Only a hint for the UI:
/// the backend decides (409 `scheduled_transaction_limit_exceeded`).
class ScheduledQuota extends Equatable {
  const ScheduledQuota({this.limit, this.usage, this.planName});

  factory ScheduledQuota.of(UserPlan? plan, ScheduledUsage? usage) =>
      ScheduledQuota(limit: plan?.quota(key), usage: usage, planName: plan?.name);

  static const key = 'max_scheduled_transactions';

  /// Null = unlimited (or no plan information).
  final int? limit;
  final ScheduledUsage? usage;
  final String? planName;

  /// False only when the usage is known to fill the quota.
  bool get canCreate => limit == null || usage == null || usage!.total < limit!;

  /// Resuming counts only the running rules.
  bool get canResume => limit == null || usage == null || usage!.running < limit!;

  /// The backend's own wording for the 409, for the upsell sheet.
  String get limitMessage => 'Alcanzaste el límite de ${limit ?? 0} transacciones programadas de tu plan';

  /// Why a paused rule cannot run again yet.
  String get resumeMessage =>
      'Tienes ${usage?.running ?? 0} de ${limit ?? 0} programadas en ejecución, el máximo de tu plan. '
      'Pausa o elimina otra para reanudar esta.';

  @override
  List<Object?> get props => [limit, usage, planName];
}

/// «Usas 2 de 3 programadas de tu plan» with a bar; explains that paused
/// rules still count and that resuming needs a free slot (COU-156).
class ScheduledQuotaCard extends StatelessWidget {
  const ScheduledQuotaCard({super.key, required this.quota});

  final ScheduledQuota quota;

  @override
  Widget build(BuildContext context) {
    final limit = quota.limit;
    final usage = quota.usage;
    if (limit == null || usage == null) return const SizedBox.shrink();
    final muted = context.palette.muted;
    final full = !quota.canCreate;
    final plan = quota.planName == null ? 'tu plan' : 'tu plan ${quota.planName}';
    final summary = 'Usas ${usage.total} de $limit programadas de $plan';
    final note = full
        ? 'Llegaste al límite: pausar no libera cupo; elimina una regla o cambia de plan para programar otra.'
        : usage.paused > 0
        ? 'Las pausadas también cuentan. Reanudar una exige cupo libre entre las que están en ejecución.'
        : 'Cuentan las reglas que programaste en todas tus billeteras.';
    return AppCard(
      outlined: true,
      semanticLabel: '$summary. $note',
      child: ExcludeSemantics(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: AppSpacing.sm,
          children: [
            Row(
              spacing: AppSpacing.sm,
              children: [
                Expanded(child: Text(summary, style: AppTypography.label)),
                if (full) const AppBadge('Límite', tone: BadgeTone.warn),
              ],
            ),
            AppProgressBar(
              value: limit == 0 ? 1 : usage.total / limit,
              tone: full ? ProgressTone.over : ProgressTone.normal,
            ),
            Text(note, style: AppTypography.caption.copyWith(color: muted)),
          ],
        ),
      ),
    );
  }
}
