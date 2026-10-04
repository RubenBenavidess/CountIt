import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../app/errors/app_failure.dart';
import '../../../app/session/session_cubit.dart';
import '../../../app/theme/app_theme.dart';
import '../../../app/theme/tokens.dart';
import '../../../data/dtos/admin.dart';
import '../../../data/dtos/plan_offer.dart';
import '../../../data/dtos/profile.dart';
import '../../../data/repositories/admin_repository.dart';
import '../../../data/repositories/plan_repository.dart';
import '../../../shared/utils/dates.dart';
import '../../../shared/widgets/app_button.dart';
import '../../../shared/widgets/app_dialogs.dart';
import '../../../shared/widgets/app_feedback.dart';
import '../../../shared/widgets/app_fields.dart';
import '../../../shared/widgets/app_layout.dart';
import '../../../shared/widgets/detail_rows.dart';
import '../../plans/cubit/plan_catalog_cubit.dart';
import '../cubit/admin_user_cubit.dart';
import 'widgets/admin_choice.dart';
import 'widgets/role_guard.dart';

/// Detail of a user for administration (HU-28 · COU-202): identity, role and
/// plan only (never finances, S-12). A superadmin changes the plan (COU-203)
/// or the role (COU-204) of others after confirming a summary; nobody
/// changes their own. Going back returns the updated user to the list.
class AdminUserPage extends StatelessWidget {
  const AdminUserPage({super.key, required this.user});

  final AdminUser user;

  @override
  Widget build(BuildContext context) => RoleGuard(
    allows: RoleGuard.admin,
    builder: (context) => BlocProvider(
      create: (context) {
        final session = context.read<SessionCubit>();
        return AdminUserCubit(
          context.read<AdminRepository>(),
          user: user,
          onForbidden: () => unawaited(session.refreshProfile()),
        );
      },
      child: const _AdminUserView(),
    ),
  );
}

class _AdminUserView extends StatelessWidget {
  const _AdminUserView();

  DateTime _today(BuildContext context) => Dates.userToday(context.read<SessionCubit>().state.profile?.timezone);

  Future<void> _changePlan(BuildContext context) async {
    final cubit = context.read<AdminUserCubit>();
    final user = cubit.state.user;
    final today = _today(context);
    final List<PlanOffer> offers;
    try {
      offers = await context.read<PlanRepository>().list();
    } on AppFailure catch (failure) {
      if (context.mounted) showFailureSnackBar(context, failure);
      return;
    }
    if (!context.mounted) return;
    if (offers.isEmpty) {
      showAppSnackBar(context, 'No hay planes disponibles. Intenta más tarde.', kind: SnackKind.error);
      return;
    }
    final choice = await showPlanChoiceSheet(context, user: user, today: today, offers: offers);
    if (choice == null || !context.mounted) return;
    final (offer, until) = choice;
    final current = offerById(offers, user.planId);
    final downgrade = current != null && (offer.plan.monthlyPriceCents ?? 0) < (current.plan.monthlyPriceCents ?? 0);
    final confirmed = await showConfirmDialog(
      context,
      title: '¿Cambiar el plan de @${user.username}?',
      message:
          '${user.planName ?? 'Sin plan'} → ${offer.name}, vigente hasta el ${Dates.date(until)}.'
          '${downgrade ? '\n\nAl bajar de plan se aplican sus límites de inmediato: terminan las membresías de '
                    'billeteras compartidas que los superen y se pausan las programadas más nuevas. '
                    'No se borra nada.' : ''}',
      confirmLabel: 'Cambiar plan',
    );
    if (confirmed) await cubit.changePlan(offer, until, today: today);
  }

  Future<void> _changeRole(BuildContext context) async {
    final cubit = context.read<AdminUserCubit>();
    final user = cubit.state.user;
    final role = await showRoleChoiceSheet(context, current: user.role);
    if (role == null || role == user.role || !context.mounted) return;
    final confirmed = await showConfirmDialog(
      context,
      title: '¿Cambiar el rol de @${user.username}?',
      message: '${user.role.label} → ${role.label}. ${roleConsequence(role)}',
      confirmLabel: 'Cambiar rol',
    );
    if (confirmed) await cubit.changeRole(role);
  }

  void _onState(BuildContext context, AdminUserState state) {
    if (state.failure != null) {
      showFailureSnackBar(context, state.failure!);
      return;
    }
    switch (state.done) {
      case AdminUserAction.plan:
        final assignment = state.assignment!;
        showAppSnackBar(
          context,
          'Plan actualizado: ${assignment.planName} hasta el ${Dates.date(assignment.validUntil)}.'
          '${assignment.enforcedAnything ? ' ${enforcedSummary(assignment)}' : ''}',
          kind: SnackKind.success,
        );
      case AdminUserAction.role:
        showAppSnackBar(context, 'Rol actualizado: ${state.user.role.label}.', kind: SnackKind.success);
      case null:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final me = context.select((SessionCubit c) => c.state.profile);
    final canChange = me?.role.isSuperadmin ?? false;
    return BlocConsumer<AdminUserCubit, AdminUserState>(
      listenWhen: (previous, current) => current.failure != null || (current.done != null && previous.busy != null),
      listener: _onState,
      builder: (context, state) {
        final user = state.user;
        final self = user.userId == me?.userId;
        final muted = context.palette.muted;
        final until = user.planValidUntil;
        return PopScope<AdminUser>(
          canPop: false,
          // Back (bar or system) returns the possibly updated user to the list.
          onPopInvokedWithResult: (didPop, result) {
            if (!didPop) Navigator.of(context).pop(user);
          },
          child: Scaffold(
            appBar: const AppTopBar(title: 'Usuario'),
            body: ListView(
              padding: const EdgeInsets.fromLTRB(AppSpacing.screen, AppSpacing.md, AppSpacing.screen, AppSpacing.xxl),
              children: [
                Semantics(header: true, child: Text(user.displayName, style: AppTypography.h1.copyWith(fontSize: 22))),
                Text('@${user.username}', style: AppTypography.caption.copyWith(color: muted)),
                const SizedBox(height: AppSpacing.lg),
                DetailRows(
                  rows: [
                    DetailRow('Correo', user.email),
                    DetailRow('Rol', user.role.label),
                    DetailRow('Plan', user.planName ?? 'Sin plan'),
                    if (until != null) DetailRow('Vence', Dates.date(until)),
                    if (user.createdAt != null)
                      DetailRow('Registro', Dates.date(Dates.inUserZone(user.createdAt!, me?.timezone))),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),
                Text(
                  'Por privacidad no se muestran billeteras, movimientos ni saldos del usuario.',
                  style: AppTypography.caption.copyWith(color: muted),
                ),
                const SizedBox(height: AppSpacing.xl),
                if (!canChange)
                  Text(
                    'Solo un superadministrador puede cambiar planes y roles.',
                    style: AppTypography.caption.copyWith(color: muted),
                  )
                else if (self)
                  Text(
                    'No puedes cambiar tu propio plan ni tu rol.',
                    style: AppTypography.caption.copyWith(color: muted),
                  )
                else ...[
                  AppButton(
                    key: const ValueKey('admin-change-plan'),
                    label: 'Cambiar plan',
                    icon: Icons.workspace_premium_outlined,
                    loading: state.busy == AdminUserAction.plan,
                    onPressed: state.busy == null ? () => unawaited(_changePlan(context)) : null,
                  ),
                  const SizedBox(height: AppSpacing.md),
                  AppButton(
                    key: const ValueKey('admin-change-role'),
                    label: 'Cambiar rol',
                    icon: Icons.admin_panel_settings_outlined,
                    variant: AppButtonVariant.secondary,
                    loading: state.busy == AdminUserAction.role,
                    onPressed: state.busy == null ? () => unawaited(_changeRole(context)) : null,
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

/// What a role allows, for the confirmation.
String roleConsequence(UserRole role) => switch (role) {
  UserRole.user => 'Perderá el acceso a la administración.',
  UserRole.admin => 'Podrá gestionar bancos y ver la lista de usuarios.',
  UserRole.superadmin => 'Podrá cambiar planes y roles y ver la auditoría.',
};

/// «Se terminaron 2 membresías y se pausaron 1 programadas.»
String enforcedSummary(PlanAssignment assignment) {
  final parts = [
    if (assignment.membershipsEnded > 0) 'terminaron ${assignment.membershipsEnded} membresías',
    if (assignment.memberRulesEnded > 0) 'terminaron ${assignment.memberRulesEnded} programadas de miembros',
    if (assignment.rulesPaused > 0) 'se pausaron ${assignment.rulesPaused} programadas',
  ];
  return 'Por el nuevo plan ${parts.join(', ')}.';
}

/// Plan among [offers] (`v_plans`, not empty) and «valid until» for a user
/// (superadmin); null when cancelled.
Future<(PlanOffer, DateTime)?> showPlanChoiceSheet(
  BuildContext context, {
  required AdminUser user,
  required DateTime today,
  required List<PlanOffer> offers,
}) {
  final first = AdminUserCubit.firstValidUntil(today);
  final current = offerById(offers, user.planId);
  var selected = current ?? offers.first;
  // Default: a month, or the current end when it is still ahead.
  final currentEnd = user.planValidUntil;
  var until = currentEnd != null && !currentEnd.isBefore(first)
      ? currentEnd
      : DateTime(today.year, today.month + 1, today.day);
  String? error;
  return showAppBottomSheet<(PlanOffer, DateTime)>(
    context,
    title: 'Cambiar plan',
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: AppSpacing.md,
        children: [
          AdminChoiceGroup<PlanOffer>(
            label: 'Plan',
            options: [
              for (final offer in offers)
                AdminChoice(
                  offer,
                  offer.name,
                  key: ValueKey('plan-choice-${offer.planId}'),
                  caption: offer.planId == current?.planId
                      ? 'Plan actual'
                      : (offer.description.isEmpty ? null : offer.description),
                ),
            ],
            selected: selected,
            onSelected: (offer) => setState(() => selected = offer),
          ),
          AppDateField(
            label: 'Vigente hasta',
            value: until,
            firstDate: first,
            lastDate: DateTime(today.year + 5, today.month, today.day),
            errorText: error,
            onChanged: (value) => setState(() {
              until = value;
              error = null;
            }),
          ),
          AppButton(
            label: 'Revisar cambio',
            onPressed: () {
              final invalid = AdminUserCubit.validateValidUntil(until, today);
              if (invalid != null) {
                setState(() => error = invalid);
                return;
              }
              Navigator.of(context).pop((selected, until));
            },
          ),
        ],
      ),
    ),
  );
}

/// New role for a user (superadmin); null when cancelled.
Future<UserRole?> showRoleChoiceSheet(BuildContext context, {required UserRole current}) {
  var selected = current;
  return showAppBottomSheet<UserRole>(
    context,
    title: 'Cambiar rol',
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: AppSpacing.md,
        children: [
          AdminChoiceGroup<UserRole>(
            label: 'Rol',
            options: [
              for (final role in UserRole.values)
                AdminChoice(
                  role,
                  role.label,
                  key: ValueKey('role-choice-${role.name}'),
                  caption: role == current ? 'Rol actual' : roleConsequence(role),
                ),
            ],
            selected: selected,
            onSelected: (role) => setState(() => selected = role),
          ),
          AppButton(
            label: 'Revisar cambio',
            onPressed: selected == current ? null : () => Navigator.of(context).pop(selected),
          ),
        ],
      ),
    ),
  );
}
