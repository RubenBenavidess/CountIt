import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../app/session/session_cubit.dart';
import '../../../app/theme/app_theme.dart';
import '../../../app/theme/tokens.dart';
import '../../../data/dtos/family.dart';
import '../../../data/dtos/wallet.dart';
import '../../../data/repositories/family_repository.dart';
import '../../../shared/state/load_state.dart';
import '../../../shared/widgets/app_button.dart';
import '../../../shared/widgets/app_feedback.dart';
import '../../../shared/widgets/app_layout.dart';
import '../cubit/family_members_cubit.dart';
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

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<FamilyMembersCubit>();
    final muted = context.palette.muted;
    final intro = wallet.isOwner
        ? 'Quienes compartan «${wallet.name}» pueden ver sus movimientos y presupuestos y registrar los suyos. '
              'Solo tú puedes editarla, eliminarla o gestionar a sus miembros.'
        : '«${wallet.name}» es de ${wallet.ownerName ?? 'otro usuario'}. '
              'Puedes ver sus movimientos y presupuestos y registrar los tuyos.';
    return Scaffold(
      appBar: const AppTopBar(title: 'Miembros'),
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
                buildWhen: (previous, current) => previous.members != current.members,
                builder: (context, state) => _members(context, state.members),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _members(BuildContext context, LoadState<List<FamilyMember>> state) {
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
            ? const EmptyState(
                icon: Icons.group_add_outlined,
                title: 'Solo tú usas esta billetera',
                message: 'Invita a alguien por su nombre de usuario para compartirla.',
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
            );
          },
        ),
      ],
    );
  }
}
