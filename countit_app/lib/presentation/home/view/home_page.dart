import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router/app_router.dart';
import '../../../app/session/session_cubit.dart';
import '../../../app/theme/app_theme.dart';
import '../../../app/theme/tokens.dart';
import '../../../data/dtos/wallet.dart';
import '../../../data/repositories/wallet_repository.dart';
import '../../../shared/state/load_state.dart';
import '../../../shared/utils/dates.dart';
import '../../../shared/utils/money.dart';
import '../../../shared/widgets/app_button.dart';
import '../../../shared/widgets/app_card.dart';
import '../../../shared/widgets/app_feedback.dart';
import '../../../shared/widgets/app_layout.dart';
import '../../../shared/widgets/motion.dart';
import '../../../shared/widgets/wordmark.dart';
import '../../families/cubit/invitations_cubit.dart';
import '../../plans/view/widgets/plan_widgets.dart';
import '../../wallets/view/widgets/wallet_card.dart';
import '../cubit/wallets_cubit.dart';

/// Home (HU-08): own and shared wallets (COU-187, COU-188, COU-189).
class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) => WalletsCubit(context.read<WalletRepository>())..load(),
      child: const _HomeView(),
    );
  }
}

class _HomeView extends StatefulWidget {
  const _HomeView();

  @override
  State<_HomeView> createState() => _HomeViewState();
}

class _HomeViewState extends State<_HomeView> {
  // Balances may change elsewhere (shared wallets, scheduled rules): reload
  // when the app comes back to the foreground.
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(onResume: () => unawaited(context.read<WalletsCubit>().load()));
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  /// Opens a wallet screen and reloads on the way back: creating, editing,
  /// deleting or adding movements there changes this list.
  Future<void> _open(String location, {Object? extra}) async {
    final cubit = context.read<WalletsCubit>();
    await context.push<Object?>(location, extra: extra);
    if (!cubit.isClosed) unawaited(cubit.load());
  }

  void _create() => unawaited(_open(AppRoutes.newWallet));

  void _openWallet(Wallet wallet) => unawaited(_open(AppRoutes.wallet(wallet.walletId), extra: wallet));

  void _openInvitations() => unawaited(_open(AppRoutes.invitations));

  @override
  Widget build(BuildContext context) {
    final profile = context.select((SessionCubit c) => c.state.profile);
    final name = profile?.firstName?.trim().isNotEmpty ?? false ? profile!.firstName! : profile?.displayName ?? '';
    return Scaffold(
      appBar: AppBar(
        title: const Wordmark(size: 22),
        titleSpacing: AppSpacing.screen,
        actions: [
          _InvitationsButton(onPressed: _openInvitations),
          const SizedBox(width: AppSpacing.sm),
        ],
      ),
      // Accepting an invitation, being removed or leaving changes the shared
      // wallets: Realtime bumps the revision and the list reloads.
      body: BlocListener<InvitationsCubit, InvitationsState>(
        listenWhen: (previous, current) => previous.revision != current.revision,
        listener: (context, state) => unawaited(context.read<WalletsCubit>().load()),
        child: BlocConsumer<WalletsCubit, LoadState<List<Wallet>>>(
          // A failed reload keeps the list on screen and explains itself here.
          listenWhen: (previous, current) => current.status == LoadStatus.failure && current.data != null,
          listener: (context, state) => showFailureSnackBar(context, state.failure!),
          builder: (context, state) {
            final wallets = state.data;
            return RefreshIndicator(
              onRefresh: context.read<WalletsCubit>().load,
              child: CustomScrollView(
                key: const PageStorageKey('home-wallets'),
                physics: const AlwaysScrollableScrollPhysics(),
                slivers: [
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(AppSpacing.screen, AppSpacing.sm, AppSpacing.screen, 0),
                    sliver: SliverToBoxAdapter(
                      child: _Header(
                        name: name,
                        wallets: wallets,
                        onCreate: wallets == null || wallets.isEmpty ? null : _create,
                      ),
                    ),
                  ),
                  const SliverPadding(
                    padding: EdgeInsets.fromLTRB(AppSpacing.screen, 0, AppSpacing.screen, 0),
                    sliver: SliverToBoxAdapter(child: _PlanExpiryNotice()),
                  ),
                  ..._body(context, state),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  List<Widget> _body(BuildContext context, LoadState<List<Wallet>> state) {
    final wallets = state.data;
    if (wallets == null) {
      return [
        SliverFillRemaining(
          hasScrollBody: false,
          child: state.status == LoadStatus.failure
              ? ErrorView.failure(state.failure!, onRetry: context.read<WalletsCubit>().load)
              : const LoadingView(),
        ),
      ];
    }
    if (wallets.isEmpty) {
      return [
        SliverFillRemaining(
          hasScrollBody: false,
          child: EmptyState(
            icon: Icons.account_balance_wallet_outlined,
            title: 'Crea tu primera billetera',
            message: 'Registra tu efectivo, cuentas y tarjetas para ver tu saldo en un solo lugar.',
            actionLabel: 'Nueva billetera',
            onAction: _create,
          ),
        ),
      ];
    }
    final own = wallets.own;
    final shared = wallets.sharedWithMe;
    return [
      const _SectionTitle('Mis billeteras'),
      if (own.isEmpty)
        _SliverNote(child: _NoOwnWallets(onCreate: _create))
      else
        _WalletList(wallets: own, onOpen: _openWallet),
      const _SectionTitle('Compartidas conmigo'),
      _PendingInvitations(onOpen: _openInvitations),
      if (shared.isEmpty)
        const _SliverNote(child: _NoSharedWallets())
      else
        _WalletList(wallets: shared, onOpen: _openWallet),
      const SliverToBoxAdapter(child: SizedBox(height: AppSpacing.xxl)),
    ];
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.name, required this.wallets, required this.onCreate});

  final String name;
  final List<Wallet>? wallets;
  final VoidCallback? onCreate;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final wallets = this.wallets;
    final ownCount = wallets?.own.length ?? 0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: AppSpacing.lg,
      children: [
        Text(
          name.isEmpty ? 'Hola' : 'Hola, $name',
          style: AppTypography.h1,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        if (wallets != null && wallets.isNotEmpty)
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: AppSpacing.xs,
              children: [
                Text('SALDO TOTAL', style: AppTypography.overline.copyWith(color: palette.muted)),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: CountUpText(
                    value: wallets.ownBalanceCents / 100,
                    format: Money.format,
                    style: AppTypography.money.copyWith(fontSize: 30),
                  ),
                ),
                Text(switch (ownCount) {
                  0 => 'Aún no tienes billeteras propias',
                  1 => 'En tu billetera',
                  _ => 'En tus $ownCount billeteras',
                }, style: AppTypography.caption.copyWith(color: palette.muted)),
              ],
            ),
          ),
        if (onCreate != null)
          AppButton(
            label: 'Nueva billetera',
            icon: Icons.add_rounded,
            variant: AppButtonVariant.secondary,
            onPressed: onCreate,
          ),
      ],
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(AppSpacing.screen, AppSpacing.xxl, AppSpacing.screen, AppSpacing.md),
      sliver: SliverToBoxAdapter(
        child: Semantics(header: true, child: Text(title, style: AppTypography.h2)),
      ),
    );
  }
}

class _SliverNote extends StatelessWidget {
  const _SliverNote({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => SliverPadding(
    padding: const EdgeInsets.symmetric(horizontal: AppSpacing.screen),
    sliver: SliverToBoxAdapter(child: child),
  );
}

/// Lazy list: only the visible cards are built, so 50+ wallets scroll smoothly.
/// Each card is the Hero of the wallet screen it opens.
class _WalletList extends StatelessWidget {
  const _WalletList({required this.wallets, required this.onOpen});

  final List<Wallet> wallets;
  final ValueChanged<Wallet> onOpen;

  @override
  Widget build(BuildContext context) {
    // The cards shown with the first data enter one after another.
    return StaggerScope(
      child: SliverPadding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.screen),
        sliver: SliverList.separated(
          itemCount: wallets.length,
          separatorBuilder: (context, index) => const SizedBox(height: AppSpacing.md),
          itemBuilder: (context, index) {
            final wallet = wallets[index];
            return StaggeredEntrance(
              key: ValueKey(wallet.walletId),
              index: index,
              child: WalletCard(wallet: wallet, onTap: () => onOpen(wallet), hero: true),
            );
          },
        ),
      ),
    );
  }
}

class _NoOwnWallets extends StatelessWidget {
  const _NoOwnWallets({required this.onCreate});

  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      outlined: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: AppSpacing.md,
        children: [
          Text(
            'Crea tu primera billetera para registrar tus propios movimientos.',
            style: AppTypography.caption.copyWith(color: context.palette.muted),
          ),
          AppButton(label: 'Crear billetera', small: true, onPressed: onCreate),
        ],
      ),
    );
  }
}

/// App bar entry to «Invitaciones» with the pending count (COU-91, COU-159).
class _InvitationsButton extends StatelessWidget {
  const _InvitationsButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final count = context.select((InvitationsCubit c) => c.state.pendingCount);
    return IconButton(
      key: const ValueKey('home-invitations'),
      tooltip: switch (count) {
        0 => 'Invitaciones',
        1 => 'Invitaciones: 1 pendiente',
        _ => 'Invitaciones: $count pendientes',
      },
      constraints: const BoxConstraints.tightFor(width: 48, height: 48),
      onPressed: onPressed,
      // The tooltip already says how many: the number is not read twice.
      icon: ExcludeSemantics(
        child: Badge(
          isLabelVisible: count > 0,
          label: Text('$count'),
          backgroundColor: AppColors.lavender,
          textColor: AppColors.ink,
          child: const Icon(Icons.mail_outline_rounded),
        ),
      ),
    );
  }
}

/// «Tienes N invitaciones» above the shared wallets while any is pending.
class _PendingInvitations extends StatelessWidget {
  const _PendingInvitations({required this.onOpen});

  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final count = context.select((InvitationsCubit c) => c.state.pendingCount);
    if (count == 0) return const SliverToBoxAdapter(child: SizedBox.shrink());
    return _SliverNote(
      child: Padding(
        padding: const EdgeInsets.only(bottom: AppSpacing.md),
        child: AppCard(
          key: const ValueKey('home-pending-invitations'),
          outlined: true,
          onTap: onOpen,
          semanticLabel: count == 1
              ? 'Tienes 1 invitación para compartir una billetera. Ver invitaciones'
              : 'Tienes $count invitaciones para compartir billeteras. Ver invitaciones',
          child: ExcludeSemantics(
            child: Row(
              spacing: AppSpacing.md,
              children: [
                const IconTile(Icons.mail_outline_rounded),
                Expanded(
                  child: Text(
                    count == 1 ? 'Tienes 1 invitación pendiente' : 'Tienes $count invitaciones pendientes',
                    style: AppTypography.label,
                  ),
                ),
                const Icon(Icons.chevron_right_rounded),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _NoSharedWallets extends StatelessWidget {
  const _NoSharedWallets();

  @override
  Widget build(BuildContext context) {
    return AppCard(
      outlined: true,
      child: Row(
        spacing: AppSpacing.md,
        children: [
          Icon(Icons.group_outlined, color: context.palette.muted),
          Expanded(
            child: Text(
              'Nadie ha compartido una billetera contigo todavía.',
              style: AppTypography.caption.copyWith(color: context.palette.muted),
            ),
          ),
        ],
      ),
    );
  }
}

/// Plan about to expire or expired (COU-117), with a link to «Mi plan».
class _PlanExpiryNotice extends StatelessWidget {
  const _PlanExpiryNotice();

  @override
  Widget build(BuildContext context) {
    final plan = context.select((SessionCubit c) => c.state.profile?.plan);
    final timezone = context.select((SessionCubit c) => c.state.profile?.timezone);
    final today = Dates.userToday(timezone);
    if (plan == null || !plan.expiryOn(today).needsNotice) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.md),
      child: PlanExpiryBanner(
        plan: plan,
        today: today,
        action: AppLink(label: 'Ver mi plan', onPressed: () => context.push(AppRoutes.myPlan)),
      ),
    );
  }
}
