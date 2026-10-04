import 'package:flutter/material.dart';

import '../../../../app/theme/tokens.dart';
import '../../../../data/dtos/wallet.dart';
import '../../../../shared/utils/money.dart';
import '../../../../shared/widgets/motion.dart';
import 'wallet_colors.dart';
import 'wallet_fragments_painter.dart';
import 'wallet_type_icon.dart';

/// Wallet card of the design (HU-08 · COU-170, COU-171, COU-174): bank colour
/// with «fragmentos», name, bank, type, balance and either the balance
/// projected to the end of the month (plan Contador Profesional) or this
/// month's incomes and expenses.
///
/// The block is chosen from the data (`projected_balance` is null outside the
/// plan), so a plan change shows the right block on the next load.
class WalletCard extends StatelessWidget {
  const WalletCard({super.key, required this.wallet, this.onTap, this.hero = false, this.countUp = true});

  final Wallet wallet;
  final VoidCallback? onTap;

  /// Flies between the home list and the wallet screen ([heroTag]).
  final bool hero;

  /// The balance counts up when the card first shows. The wallet screen
  /// turns it off: its card lands from the list already showing the balance.
  final bool countUp;

  /// Tag shared by the card of the list and the one of the wallet screen.
  static Object heroTag(int walletId) => 'wallet-card-$walletId';

  /// The card in flight keeps the theme's text style and ink (no Scaffold above it).
  static Widget _flight(
    BuildContext flightContext,
    Animation<double> animation,
    HeroFlightDirection direction,
    BuildContext fromContext,
    BuildContext toContext,
  ) {
    final hero = (direction == HeroFlightDirection.push ? toContext : fromContext).widget as Hero;
    return Material(type: MaterialType.transparency, child: hero.child);
  }

  String get _semanticLabel {
    final parts = [
      wallet.name,
      wallet.bankName ?? 'Sin banco',
      wallet.type.displayLabel,
      if (!wallet.isOwner)
        'compartida contigo por ${wallet.ownerName ?? 'otro usuario'}'
      else if (wallet.memberCount > 0)
        wallet.memberCount == 1 ? 'compartida con 1 miembro' : 'compartida con ${wallet.memberCount} miembros',
      'saldo ${Money.format(wallet.balance)}',
      if (wallet.projectedBalance != null)
        'saldo proyectado a fin de mes ${Money.format(wallet.projectedBalance!)}'
      else ...[
        'ingresos del mes ${Money.format(wallet.monthIncome)}',
        'gastos del mes ${Money.format(wallet.monthExpenses)}',
      ],
    ];
    return parts.join(', ');
  }

  @override
  Widget build(BuildContext context) {
    final colors = WalletColors.of(wallet.bankColor);
    final radius = BorderRadius.circular(AppRadii.wallet);
    final card = Semantics(
      button: onTap != null,
      label: _semanticLabel,
      excludeSemantics: true,
      // Repaints of the list (scroll, other cards) never repaint the fragments.
      child: RepaintBoundary(
        child: Material(
          color: colors.base,
          shape: RoundedRectangleBorder(borderRadius: radius),
          clipBehavior: Clip.antiAlias,
          child: CustomPaint(
            painter: WalletFragmentsPainter(colors),
            child: InkWell(
              onTap: onTap,
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: _CardContent(wallet: wallet, colors: colors, countUp: countUp),
              ),
            ),
          ),
        ),
      ),
    );
    final pressable = onTap == null ? card : PressScale(child: card);
    return hero ? Hero(tag: heroTag(wallet.walletId), flightShuttleBuilder: _flight, child: pressable) : pressable;
  }
}

class _CardContent extends StatelessWidget {
  const _CardContent({required this.wallet, required this.colors, required this.countUp});

  final Wallet wallet;
  final WalletColors colors;
  final bool countUp;

  @override
  Widget build(BuildContext context) {
    final fg = colors.foreground;
    final muted = colors.mutedForeground;
    final subtitle = [
      wallet.bankName ?? 'Sin banco',
      if (!wallet.isOwner && (wallet.ownerName?.isNotEmpty ?? false)) 'de ${wallet.ownerName}',
    ].join(' · ');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: AppSpacing.md,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: 2,
                children: [
                  Text(
                    wallet.name,
                    style: AppTypography.h2.copyWith(color: fg),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    subtitle,
                    style: AppTypography.caption.copyWith(color: muted),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            if (wallet.isShared) _SharedBadge(wallet: wallet, colors: colors),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        Row(
          spacing: 6,
          children: [
            Icon(wallet.type.icon, size: 16, color: muted),
            Flexible(
              child: Text(
                wallet.type.displayLabel,
                style: AppTypography.caption.copyWith(color: muted),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.lg),
        Text('SALDO', style: AppTypography.overline.copyWith(color: muted)),
        _Balance(wallet: wallet, colors: colors, countUp: countUp),
        const SizedBox(height: AppSpacing.md),
        _MonthPanel(wallet: wallet, colors: colors),
      ],
    );
  }
}

class _Balance extends StatelessWidget {
  const _Balance({required this.wallet, required this.colors, required this.countUp});

  final Wallet wallet;
  final WalletColors colors;
  final bool countUp;

  @override
  Widget build(BuildContext context) {
    final negative = wallet.balanceCents < 0;
    final style = AppTypography.money.copyWith(
      fontSize: 28,
      color: colors.foreground,
      decoration: negative ? TextDecoration.underline : null,
      decorationColor: AppColors.expense,
      decorationThickness: 2,
    );
    return Row(
      spacing: AppSpacing.sm,
      children: [
        Flexible(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: countUp
                ? CountUpText(
                    key: const ValueKey('wallet-balance'),
                    value: wallet.balance,
                    format: Money.format,
                    style: style,
                  )
                : Text(Money.format(wallet.balance), key: const ValueKey('wallet-balance'), style: style),
          ),
        ),
        // Colour is never the only signal: a negative balance also says so.
        if (negative)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(color: colors.panel, borderRadius: BorderRadius.circular(AppRadii.pill)),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              spacing: 4,
              children: [
                const Icon(Icons.trending_down_rounded, size: 14, color: AppColors.expense),
                Text(
                  'Saldo negativo',
                  style: AppTypography.overline.copyWith(letterSpacing: 0, color: AppColors.expense),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _SharedBadge extends StatelessWidget {
  const _SharedBadge({required this.wallet, required this.colors});

  final Wallet wallet;
  final WalletColors colors;

  @override
  Widget build(BuildContext context) {
    final members = wallet.memberCount;
    return Container(
      height: 26,
      padding: const EdgeInsets.symmetric(horizontal: 9),
      decoration: BoxDecoration(color: colors.chip, borderRadius: BorderRadius.circular(13)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        spacing: 4,
        children: [
          Icon(Icons.group_outlined, size: 14, color: colors.foreground),
          Text(
            members > 0 ? 'Compartida · $members' : 'Compartida',
            style: AppTypography.overline.copyWith(letterSpacing: 0, color: colors.foreground),
          ),
        ],
      ),
    );
  }
}

/// Projection (plan Contador Profesional) or this month's figures (others).
class _MonthPanel extends StatelessWidget {
  const _MonthPanel({required this.wallet, required this.colors});

  final Wallet wallet;
  final WalletColors colors;

  @override
  Widget build(BuildContext context) {
    final projected = wallet.projectedBalance;
    final label = AppTypography.caption.copyWith(color: AppColors.muted, height: 1.2);
    final value = AppTypography.money.copyWith(fontSize: 15, color: AppColors.alabaster);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(color: colors.panel, borderRadius: BorderRadius.circular(AppRadii.lg)),
      child: projected != null
          ? Row(
              key: const ValueKey('wallet-projection'),
              spacing: AppSpacing.sm,
              children: [
                const Icon(Icons.insights_rounded, size: 18, color: AppColors.lavender),
                Expanded(child: Text('Saldo proyectado a fin de mes', style: label)),
                Text(Money.format(projected), style: value),
              ],
            )
          : Row(
              key: const ValueKey('wallet-month'),
              children: [
                Expanded(
                  child: _MonthFigure(
                    label: 'Ingresos del mes',
                    text: Money.signed(wallet.monthIncome, income: true),
                    color: AppColors.income,
                    labelStyle: label,
                    valueStyle: value,
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: _MonthFigure(
                    label: 'Gastos del mes',
                    text: Money.signed(wallet.monthExpenses, income: false),
                    color: AppColors.expense,
                    labelStyle: label,
                    valueStyle: value,
                  ),
                ),
              ],
            ),
    );
  }
}

class _MonthFigure extends StatelessWidget {
  const _MonthFigure({
    required this.label,
    required this.text,
    required this.color,
    required this.labelStyle,
    required this.valueStyle,
  });

  final String label;
  final String text;
  final Color color;
  final TextStyle labelStyle;
  final TextStyle valueStyle;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: 2,
      children: [
        Text(label, style: labelStyle, maxLines: 1, overflow: TextOverflow.ellipsis),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(text, style: valueStyle.copyWith(color: color)),
        ),
      ],
    );
  }
}
