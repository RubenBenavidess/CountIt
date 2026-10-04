import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router/app_router.dart';

import '../../../app/session/session_cubit.dart';
import '../../../app/theme/app_theme.dart';
import '../../../app/theme/tokens.dart';
import '../../../data/dtos/family.dart';
import '../../../data/dtos/profile.dart';
import '../../../data/dtos/wallet.dart';
import '../../../data/repositories/family_repository.dart';
import '../../../shared/state/load_state.dart';
import '../../../shared/widgets/app_button.dart';
import '../../../shared/widgets/app_dialogs.dart';
import '../../../shared/widgets/app_feedback.dart';
import '../../../shared/widgets/app_layout.dart';
import '../../account/view/reauth_sheet.dart';
import '../../plans/view/plan_upsell_sheet.dart';
import '../cubit/family_members_cubit.dart';
import 'invite_member_page.dart';
import 'widgets/member_tile.dart';

/// «Miembros» of a wallet (HU-24 · COU-92): the owner sees accepted members
/// and pending invitations; a member sees the owner and the accepted members.
/// The list follows Realtime while the screen is open.
class FamilyMembersPage extends StatelessWidget {
  const FamilyMembersPage({super.key, required this.wallet});

  /// The wallet the detail screen loaded (name, ownership).
  final Wallet wallet;

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) => FamilyMembersCubit(context.read<FamilyRepository>(), walletId: wallet.walletId)..watch(),
      child: _FamilyMembersView(wallet: wallet),
    );
  }
}

class _FamilyMembersView extends StatelessWidget {
  const _FamilyMembersView({required this.wallet});

  final Wallet wallet;

  /// HU-21 (COU-90): without families in the plan the sheet explains it
  /// before a form the API would reject (403 `feature_not_in_plan`).
  Future<void> _invite(BuildContext context) async {
    final cubit = context.read<FamilyMembersCubit>();
    final plan = context.read<SessionCubit>().state.profile?.plan;
    if (plan != null && !plan.hasFeature(PlanFeatures.families)) {
      return showPlanUpsell(
        context,
        title: familiesNotInPlanTitle,
        message: 'Compartir billeteras con tu familia está disponible en planes superiores.',
      );
    }
    final invited = await context.push<bool>(AppRoutes.inviteMember(wallet.walletId), extra: wallet);
    if (invited == true && !cubit.isClosed) unawaited(cubit.load());
  }

  /// HU-23 (COU-163): cancelling an invitation only asks for confirmation;
  /// removing an accepted member also asks for the password (🔒).
  Future<void> _remove(BuildContext context, FamilyMember member) async {
    final cubit = context.read<FamilyMembersCubit>();
    final pending = member.isPending;
    final confirmed = await showConfirmDialog(
      context,
      title: pending ? '¿Cancelar la invitación a ${member.name}?' : '¿Quitar a ${member.name}?',
      message: pending
          ? 'La invitación dejará de ser válida. Podrás invitar a @${member.username} de nuevo.'
          : 'Perderá el acceso a «${wallet.name}» al instante y sus movimientos programados en ella terminarán. '
                'Los movimientos que registró se conservan.',
      confirmLabel: pending ? 'Cancelar invitación' : 'Quitar',
      cancelLabel: 'Volver',
      destructive: true,
    );
    if (!confirmed || !context.mounted) return;
    await cubit.remove(
      member,
      onReauth: reauthPrompt(context, action: 'quitar a ${member.name}', confirmLabel: 'Quitar miembro'),
    );
  }

  /// HU-23 (COU-165): an accepted member leaves (no password).
  Future<void> _leave(BuildContext context) async {
    final cubit = context.read<FamilyMembersCubit>();
    final confirmed = await showConfirmDialog(
      context,
      title: '¿Salir de «${wallet.name}»?',
      message:
          'Dejarás de verla al instante y tus movimientos programados en ella terminarán. '
          'Los movimientos que registraste se conservan. Para volver necesitarás una nueva invitación.',
      confirmLabel: 'Salir',
      destructive: true,
    );
    if (confirmed && context.mounted) await cubit.leave(walletName: wallet.name);
  }

  void _onAction(BuildContext context, FamilyMembersState state) {
    final result = state.lastAction!;
    switch (result.outcome) {
      case MemberActionOutcome.removed:
        showAppSnackBar(context, 'Quitaste a ${result.name} de la familia', kind: SnackKind.success);
      case MemberActionOutcome.cancelled:
        showAppSnackBar(context, 'Cancelaste la invitación a ${result.name}', kind: SnackKind.success);
      case MemberActionOutcome.missing:
        showAppSnackBar(context, '${result.name} ya no era parte de la familia');
      case MemberActionOutcome.left:
        showAppSnackBar(context, 'Saliste de «${result.name}»', kind: SnackKind.success);
        // The wallet is no longer readable: back to the home list.
        context.go(AppRoutes.home);
      case MemberActionOutcome.failed:
        showFailureSnackBar(context, result.failure!);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<FamilyMembersCubit>();
    final muted = context.palette.muted;
    final intro = wallet.isOwner
        ? 'Quienes compartan «${wallet.name}» pueden ver sus movimientos y presupuestos y registrar los suyos. '
              'Solo tú puedes editarla, eliminarla o gestionar a sus miembros.'
        : '«${wallet.name}» es de ${wallet.ownerName ?? 'otro usuario'}. '
              'Puedes ver sus movimientos y presupuestos y registrar los tuyos.';
    return BlocListener<FamilyMembersCubit, FamilyMembersState>(
      listenWhen: (previous, current) => current.lastAction != null && previous.lastAction != current.lastAction,
      listener: _onAction,
      child: Scaffold(
        appBar: const AppTopBar(title: 'Miembros'),
        // COU-167: only the owner manages the family (the API decides anyway).
        floatingActionButton: wallet.isOwner
            ? FloatingActionButton.extended(
                key: const ValueKey('member-invite'),
                tooltip: 'Invitar a alguien a «${wallet.name}»',
                onPressed: () => _invite(context),
                icon: const Icon(Icons.person_add_alt_rounded),
                label: const Text('Invitar'),
              )
            : null,
        body: RefreshIndicator(
          onRefresh: cubit.load,
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(AppSpacing.screen, AppSpacing.sm, AppSpacing.screen, AppSpacing.lg),
                sliver: SliverToBoxAdapter(
                  child: Text(intro, style: AppTypography.body.copyWith(color: muted)),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(AppSpacing.screen, 0, AppSpacing.screen, 96),
                sliver: BlocBuilder<FamilyMembersCubit, FamilyMembersState>(
                  buildWhen: (previous, current) =>
                      previous.members != current.members ||
                      previous.busy != current.busy ||
                      previous.leaving != current.leaving,
                  builder: (context, state) => _members(context, state),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _members(BuildContext context, FamilyMembersState full) {
    final state = full.members;
    final members = state.data;
    final profile = context.read<SessionCubit>().state.profile;
    final cubit = context.read<FamilyMembersCubit>();
    if (members == null) {
      return SliverFillRemaining(
        hasScrollBody: false,
        child: state.status == LoadStatus.failure
            ? ErrorView(message: state.failure!.message, onRetry: cubit.load)
            : const LoadingView(message: 'Cargando miembros'),
      );
    }
    final userId = profile?.userId;
    if (members.isEmpty || (!wallet.isOwner && !members.any((m) => m.userId == userId))) {
      return SliverFillRemaining(
        hasScrollBody: false,
        child: wallet.isOwner
            ? EmptyState(
                icon: Icons.group_add_outlined,
                title: 'Solo tú usas esta billetera',
                message: 'Invita a alguien por su nombre de usuario para compartirla.',
                actionLabel: 'Invitar a alguien',
                onAction: () => _invite(context),
              )
            : const EmptyState(
                icon: Icons.group_off_outlined,
                title: 'Ya no compartes esta billetera',
                message: 'Tu acceso terminó. Vuelve al inicio para ver tus billeteras.',
              ),
      );
    }
    return SliverMainAxisGroup(
      slivers: [
        if (state.status == LoadStatus.failure)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.md),
              child: NoteCard(
                icon: Icons.cloud_off_outlined,
                message: state.failure!.message,
                action: AppButton(
                  label: 'Reintentar',
                  variant: AppButtonVariant.ghost,
                  expand: false,
                  onPressed: cubit.load,
                ),
              ),
            ),
          ),
        SliverList.separated(
          itemCount: members.length,
          separatorBuilder: (context, index) => Divider(height: 1, color: context.palette.line),
          itemBuilder: (context, index) {
            final member = members[index];
            return MemberTile(
              key: ValueKey('member-${member.userId}'),
              member: member,
              isMe: member.userId == userId,
              timezone: profile?.timezone,
              // COU-167: only the owner removes members or cancels invitations.
              trailing: wallet.isOwner && !member.isOwner
                  ? _RemoveButton(
                      member: member,
                      busy: full.busy.contains(member.userId),
                      onPressed: () => unawaited(_remove(context, member)),
                    )
                  : null,
            );
          },
        ),
        // A member may leave; the owner deletes the wallet instead.
        if (!wallet.isOwner)
          SliverPadding(
            padding: const EdgeInsets.only(top: AppSpacing.xxl),
            sliver: SliverToBoxAdapter(
              child: AppButton(
                key: const ValueKey('member-leave'),
                label: 'Salir de esta billetera',
                icon: Icons.logout_rounded,
                variant: AppButtonVariant.danger,
                loading: full.leaving,
                onPressed: full.leaving ? null : () => unawaited(_leave(context)),
              ),
            ),
          ),
      ],
    );
  }
}

/// «Quitar» an accepted member or «Cancelar» a pending invitation (48 px).
class _RemoveButton extends StatelessWidget {
  const _RemoveButton({required this.member, required this.busy, required this.onPressed});

  final FamilyMember member;
  final bool busy;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      key: ValueKey('member-remove-${member.userId}'),
      tooltip: member.isPending ? 'Cancelar la invitación a ${member.name}' : 'Quitar a ${member.name}',
      constraints: const BoxConstraints.tightFor(width: 48, height: 48),
      onPressed: busy ? null : onPressed,
      icon: busy
          ? const SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2))
          : Icon(member.isPending ? Icons.close_rounded : Icons.person_remove_outlined),
    );
  }
}
