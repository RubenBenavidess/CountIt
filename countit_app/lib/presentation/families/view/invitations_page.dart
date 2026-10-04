import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../app/session/session_cubit.dart';
import '../../../app/theme/app_theme.dart';
import '../../../app/theme/tokens.dart';
import '../../../data/dtos/family.dart';
import '../../../shared/state/load_state.dart';
import '../../../shared/widgets/app_button.dart';
import '../../../shared/widgets/app_card.dart';
import '../../../shared/widgets/app_dialogs.dart';
import '../../../shared/widgets/app_feedback.dart';
import '../../../shared/widgets/app_layout.dart';
import '../cubit/invitations_cubit.dart';
import 'widgets/member_tile.dart';

/// «Invitaciones» (HU-22/HU-24 · COU-91, COU-161): the caller's pending
/// invitations with wallet, owner and expiry, live with Realtime; each one
/// can be accepted or declined. Uses the app-wide [InvitationsCubit].
class InvitationsPage extends StatelessWidget {
  const InvitationsPage({super.key});

  Future<void> _decline(BuildContext context, FamilyInvitation invitation) async {
    final cubit = context.read<InvitationsCubit>();
    final confirmed = await showConfirmDialog(
      context,
      title: '¿Rechazar la invitación?',
      message:
          'No tendrás acceso a «${invitation.walletName}». '
          '${invitation.owner} podrá invitarte de nuevo si cambias de opinión.',
      confirmLabel: 'Rechazar',
      destructive: true,
    );
    if (confirmed && !cubit.isClosed) unawaited(cubit.respond(invitation, accept: false));
  }

  void _onResponse(BuildContext context, InvitationsState state) {
    final response = state.lastResponse!;
    switch (response.outcome) {
      case InvitationOutcome.accepted:
        showAppSnackBar(
          context,
          'Ahora compartes «${response.walletName}». La verás en «Compartidas conmigo».',
          kind: SnackKind.success,
        );
      case InvitationOutcome.declined:
        showAppSnackBar(context, 'Rechazaste la invitación a «${response.walletName}»');
      case InvitationOutcome.expired || InvitationOutcome.missing || InvitationOutcome.failed:
        showFailureSnackBar(context, response.failure!);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<InvitationsCubit>();
    return BlocListener<InvitationsCubit, InvitationsState>(
      listenWhen: (previous, current) => current.lastResponse != null && previous.lastResponse != current.lastResponse,
      listener: _onResponse,
      child: Scaffold(
        appBar: const AppTopBar(title: 'Invitaciones'),
        body: RefreshIndicator(
          onRefresh: cubit.load,
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(AppSpacing.screen, AppSpacing.sm, AppSpacing.screen, AppSpacing.xxl),
                sliver: BlocBuilder<InvitationsCubit, InvitationsState>(
                  buildWhen: (previous, current) =>
                      previous.invitations != current.invitations || previous.responding != current.responding,
                  builder: (context, state) => _body(context, state),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _body(BuildContext context, InvitationsState state) {
    final cubit = context.read<InvitationsCubit>();
    final invitations = state.invitations.data;
    if (invitations == null) {
      return SliverFillRemaining(
        hasScrollBody: false,
        child: state.invitations.status == LoadStatus.failure
            ? ErrorView(message: state.invitations.failure!.message, onRetry: cubit.load)
            : const LoadingView(message: 'Cargando invitaciones'),
      );
    }
    if (invitations.isEmpty) {
      return const SliverFillRemaining(
        hasScrollBody: false,
        child: EmptyState(
          icon: Icons.mark_email_read_outlined,
          title: 'No tienes invitaciones pendientes',
          message: 'Cuando alguien te invite a compartir una billetera, aparecerá aquí al instante.',
        ),
      );
    }
    final timezone = context.read<SessionCubit>().state.profile?.timezone;
    return SliverMainAxisGroup(
      slivers: [
        if (state.invitations.status == LoadStatus.failure)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.md),
              child: NoteCard(
                icon: Icons.cloud_off_outlined,
                message: state.invitations.failure!.message,
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
          itemCount: invitations.length,
          separatorBuilder: (context, index) => const SizedBox(height: AppSpacing.md),
          itemBuilder: (context, index) {
            final invitation = invitations[index];
            return _InvitationCard(
              key: ValueKey('invitation-${invitation.walletId}'),
              invitation: invitation,
              timezone: timezone,
              busy: state.responding.contains(invitation.walletId),
              onAccept: () => unawaited(cubit.respond(invitation, accept: true)),
              onDecline: () => unawaited(_decline(context, invitation)),
            );
          },
        ),
      ],
    );
  }
}

class _InvitationCard extends StatelessWidget {
  const _InvitationCard({
    super.key,
    required this.invitation,
    required this.timezone,
    required this.busy,
    required this.onAccept,
    required this.onDecline,
  });

  final FamilyInvitation invitation;
  final String? timezone;
  final bool busy;
  final VoidCallback onAccept;
  final VoidCallback onDecline;

  @override
  Widget build(BuildContext context) {
    final muted = context.palette.muted;
    final expiry = expiryLabel(invitation.expiresAt, timezone);
    final from = 'Te invita ${invitation.owner} (@${invitation.ownerUsername})';
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: AppSpacing.md,
        children: [
          Semantics(
            label: ['Invitación a ${invitation.walletName}', from, ?expiry].join(', '),
            excludeSemantics: true,
            child: Row(
              spacing: AppSpacing.md,
              children: [
                const IconTile(Icons.group_outlined),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    spacing: 2,
                    children: [
                      Text(
                        invitation.walletName,
                        style: AppTypography.h2,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(from, style: AppTypography.caption.copyWith(color: muted)),
                      if (expiry != null) Text(expiry, style: AppTypography.caption.copyWith(color: muted)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Row(
            spacing: AppSpacing.md,
            children: [
              Expanded(
                child: AppButton(
                  key: ValueKey('invitation-decline-${invitation.walletId}'),
                  label: 'Rechazar',
                  variant: AppButtonVariant.secondary,
                  onPressed: busy ? null : onDecline,
                ),
              ),
              Expanded(
                child: AppButton(
                  key: ValueKey('invitation-accept-${invitation.walletId}'),
                  label: 'Aceptar',
                  loading: busy,
                  onPressed: busy ? null : onAccept,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
