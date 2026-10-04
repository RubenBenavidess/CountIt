import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../app/session/session_cubit.dart';
import '../../../app/theme/app_theme.dart';
import '../../../app/theme/tokens.dart';
import '../../../data/dtos/admin.dart';
import '../../../data/repositories/admin_repository.dart';
import '../../../shared/utils/dates.dart';
import '../../../shared/widgets/app_button.dart';
import '../../../shared/widgets/app_card.dart';
import '../../../shared/widgets/app_feedback.dart';
import '../../../shared/widgets/app_fields.dart';
import '../../../shared/widgets/app_layout.dart';
import '../../../shared/widgets/load_more_listener.dart';
import '../cubit/admin_users_cubit.dart' show AdminListStatus;
import '../cubit/audit_log_cubit.dart';
import 'widgets/role_guard.dart';

/// Entities the backend audits (`private.audit_log.entity`), in Spanish.
const auditEntities = <String, String>{
  'user': 'Usuarios',
  'bank': 'Bancos',
  'wallet': 'Billeteras',
  'budget': 'Presupuestos',
  'transaction': 'Movimientos',
  'scheduled_transaction': 'Programadas',
  'family_member': 'Familias',
  'job': 'Sistema',
};

/// Spanish names of the audited actions; unknown ones are shown as sent.
const auditActions = <String, String>{
  'account_deleted': 'Cuenta eliminada',
  'account_locked': 'Cuenta bloqueada',
  'bank_activated': 'Banco activado',
  'bank_created': 'Banco creado',
  'bank_deactivated': 'Banco desactivado',
  'bank_updated': 'Banco editado',
  'budget_deleted': 'Presupuesto eliminado',
  'data_exported': 'Datos exportados',
  'family_member_invited': 'Miembro invitado',
  'family_member_left': 'Miembro salió',
  'password_changed': 'Contraseña cambiada',
  'plan_quotas_enforced': 'Cupos del plan aplicados',
  'plan_set_by_admin': 'Plan asignado',
  'plans_expired': 'Planes vencidos',
  'push_device_reassigned': 'Dispositivo reasignado',
  'reauthenticated': 'Identidad confirmada',
  'role_changed': 'Rol cambiado',
  'scheduled_rule_failed': 'Programada fallida',
  'scheduled_run': 'Programadas ejecutadas',
  'scheduled_transaction_deleted': 'Programada eliminada',
  'transaction_deleted': 'Movimiento eliminado',
  'username_changed': 'Usuario cambiado',
  'wallet_deleted': 'Billetera eliminada',
};

String auditActionLabel(String action) => auditActions[action] ?? action;

/// Audit trail (HU-28 · COU-208, COU-209): superadmin only (router redirect,
/// [RoleGuard] and the API). Newest first, filters by entity and id.
class AuditLogPage extends StatelessWidget {
  const AuditLogPage({super.key});

  @override
  Widget build(BuildContext context) => RoleGuard(
    allows: RoleGuard.superadmin,
    builder: (context) => BlocProvider(
      create: (context) => AuditLogCubit(context.read<AdminRepository>())..load(),
      child: const _AuditLogView(),
    ),
  );
}

class _AuditLogView extends StatelessWidget {
  const _AuditLogView();

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<AuditLogCubit>();
    return Scaffold(
      appBar: const AppTopBar(title: 'Auditoría'),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _EntityFilter(),
          Padding(
            padding: const EdgeInsets.fromLTRB(AppSpacing.screen, AppSpacing.sm, AppSpacing.screen, AppSpacing.sm),
            child: AppTextField(
              key: const ValueKey('audit-entity-id'),
              label: 'Id de la entidad (opcional)',
              hint: 'Ej.: id de usuario o de banco',
              prefix: const Icon(Icons.tag_rounded),
              maxLength: AuditLogCubit.entityIdMax,
              onChanged: cubit.filterByEntityId,
            ),
          ),
          Expanded(
            child: BlocBuilder<AuditLogCubit, AuditLogState>(
              builder: (context, state) {
                if (state.isFirstLoad) {
                  if (state.status == AdminListStatus.failure) {
                    return ErrorView.failure(state.failure!, onRetry: cubit.load);
                  }
                  return const LoadingView(message: 'Cargando auditoría');
                }
                if (state.items.isEmpty) {
                  return EmptyState(
                    icon: Icons.fact_check_outlined,
                    title: 'Sin registros',
                    message: state.filter.isEmpty ? 'Todavía no hay acciones auditadas.' : 'Nada con estos filtros.',
                    actionLabel: state.filter.isEmpty ? null : 'Quitar filtros',
                    onAction: state.filter.isEmpty ? null : cubit.clearFilters,
                  );
                }
                final timezone = context.read<SessionCubit>().state.profile?.timezone;
                final extra = state.hasMore || state.moreFailure != null ? 1 : 0;
                return RefreshIndicator(
                  onRefresh: cubit.load,
                  child: LoadMoreListener(
                    onLoadMore: cubit.loadMore,
                    child: ListView.separated(
                      key: const PageStorageKey('audit-log'),
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.fromLTRB(
                        AppSpacing.screen,
                        AppSpacing.sm,
                        AppSpacing.screen,
                        AppSpacing.xxl,
                      ),
                      itemCount: state.items.length + extra,
                      separatorBuilder: (context, index) => const SizedBox(height: AppSpacing.sm),
                      itemBuilder: (context, index) {
                        if (index == state.items.length) return _MoreRow(state: state);
                        final entry = state.items[index];
                        return AuditEntryTile(
                          key: ValueKey('audit-${entry.auditId}'),
                          entry: entry,
                          timezone: timezone,
                        );
                      },
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// «Todas» plus one chip per audited entity; only this row rebuilds on change.
class _EntityFilter extends StatelessWidget {
  const _EntityFilter();

  @override
  Widget build(BuildContext context) {
    final selected = context.select((AuditLogCubit c) => c.state.filter.entity);
    final cubit = context.read<AuditLogCubit>();
    Widget chip(String? value, String label) => Padding(
      padding: const EdgeInsets.only(right: AppSpacing.sm),
      child: ChoiceChip(
        key: ValueKey('audit-entity-${value ?? 'all'}'),
        label: Text(label),
        selected: selected == value,
        materialTapTargetSize: MaterialTapTargetSize.padded,
        onSelected: (_) => cubit.filterByEntity(value),
      ),
    );
    return Semantics(
      container: true,
      label: 'Filtrar por entidad',
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(AppSpacing.screen, AppSpacing.sm, AppSpacing.screen, 0),
        child: Row(
          children: [chip(null, 'Todas'), for (final entry in auditEntities.entries) chip(entry.key, entry.value)],
        ),
      ),
    );
  }
}

class _MoreRow extends StatelessWidget {
  const _MoreRow({required this.state});

  final AuditLogState state;

  @override
  Widget build(BuildContext context) {
    final failure = state.moreFailure;
    if (failure != null) {
      return NoteCard(
        icon: Icons.cloud_off_outlined,
        message: failure.message,
        action: AppButton(
          label: 'Reintentar',
          small: true,
          variant: AppButtonVariant.ghost,
          onPressed: () => context.read<AuditLogCubit>().loadMore(retry: true),
        ),
      );
    }
    return const Padding(
      padding: EdgeInsets.all(AppSpacing.lg),
      child: Center(
        child: SizedBox.square(
          dimension: 24,
          child: CircularProgressIndicator(strokeWidth: 2.5, semanticsLabel: 'Cargando más registros'),
        ),
      ),
    );
  }
}

/// One audited action: what, who, when and on what; details on demand.
class AuditEntryTile extends StatelessWidget {
  const AuditEntryTile({super.key, required this.entry, this.timezone});

  final AuditEntry entry;
  final String? timezone;

  static String _value(Object? value) => switch (value) {
    null => '—',
    String() => value,
    num() || bool() => '$value',
    _ => jsonEncode(value),
  };

  @override
  Widget build(BuildContext context) {
    final muted = context.palette.muted;
    final who = entry.bySystem ? 'Sistema' : '@${entry.actorUsername ?? 'usuario eliminado'}';
    final when = Dates.dateTime(Dates.inUserZone(entry.occurredAt, timezone));
    final what = [auditEntities[entry.entity] ?? entry.entity, ?entry.entityId].join(' · ');
    return AppCard(
      padding: EdgeInsets.zero,
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          minTileHeight: 64,
          tilePadding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
          childrenPadding: const EdgeInsets.fromLTRB(AppSpacing.lg, 0, AppSpacing.lg, AppSpacing.md),
          expandedCrossAxisAlignment: CrossAxisAlignment.start,
          title: Text(auditActionLabel(entry.action), style: AppTypography.label),
          subtitle: Text('$who · $when\n$what', style: AppTypography.caption.copyWith(color: muted)),
          children: entry.details.isEmpty
              ? [Text('Sin detalles.', style: AppTypography.caption.copyWith(color: muted))]
              : [
                  for (final detail in entry.details.entries)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Text.rich(
                        TextSpan(
                          children: [
                            TextSpan(
                              text: '${detail.key}: ',
                              style: AppTypography.caption.copyWith(color: muted),
                            ),
                            TextSpan(text: _value(detail.value), style: AppTypography.caption),
                          ],
                        ),
                      ),
                    ),
                ],
        ),
      ),
    );
  }
}
