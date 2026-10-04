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
import '../../../shared/utils/money.dart';
import '../../../shared/widgets/app_button.dart';
import '../../../shared/widgets/app_card.dart';
import '../../../shared/widgets/app_feedback.dart';
import '../../../shared/widgets/wordmark.dart';
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

  @override
  Widget build(BuildContext context) {
    final profile = context.select((SessionCubit c) => c.state.profile);
    final name = profile?.firstName?.trim().isNotEmpty ?? false ? profile!.firstName! : profile?.displayName ?? '';
    return Scaffold(
      appBar: AppBar(title: const Wordmark(size: 22), titleSpacing: AppSpacing.screen),
      body: BlocConsumer<WalletsCubit, LoadState<List<Wallet>>>(
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
                ..._body(context, state),
              ],
            ),
          );
        },
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
                  child: Text(
                    Money.format(wallets.ownBalanceCents / 100),
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
class _WalletList extends StatelessWidget {
  const _WalletList({required this.wallets, required this.onOpen});

  final List<Wallet> wallets;
  final ValueChanged<Wallet> onOpen;

  @override
  Widget build(BuildContext context) {
    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.screen),
      sliver: SliverList.separated(
        itemCount: wallets.length,
        separatorBuilder: (context, index) => const SizedBox(height: AppSpacing.md),
        itemBuilder: (context, index) {
          final wallet = wallets[index];
          return _FadeIn(
            key: ValueKey(wallet.walletId),
            child: WalletCard(wallet: wallet, onTap: () => onOpen(wallet)),
          );
        },
      ),
    );
  }
}

/// Light entrance: fade and a short slide the first time a card is built.
class _FadeIn extends StatelessWidget {
  const _FadeIn({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
      child: child,
      builder: (context, t, child) => Opacity(
        opacity: t,
        child: Transform.translate(offset: Offset(0, (1 - t) * 12), child: child),
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
