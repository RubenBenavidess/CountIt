import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../app/session/session_cubit.dart';
import '../../../app/theme/app_theme.dart';
import '../../../app/theme/tokens.dart';
import '../../../data/dtos/profile.dart';
import '../../../data/dtos/projection.dart';
import '../../../data/dtos/wallet.dart';
import '../../../data/repositories/analysis_repository.dart';
import '../../../shared/state/load_state.dart';
import '../../../shared/utils/dates.dart';
import '../../../shared/utils/money.dart';
import '../../../shared/widgets/app_button.dart';
import '../../../shared/widgets/app_card.dart';
import '../../../shared/widgets/app_feedback.dart';
import '../../../shared/widgets/app_fields.dart';
import '../../../shared/widgets/app_layout.dart';
import '../../../shared/widgets/detail_rows.dart';
import '../../../shared/widgets/section_header.dart';
import '../../plans/view/plan_upsell_sheet.dart';
import '../cubit/projection_cubit.dart';
import 'charts/trend_line_chart.dart';

/// Title and message of the plans sheet without the projection (COU-172).
const projectionNotInPlanTitle = 'Tu plan no incluye la proyección de saldo';
const projectionNotInPlanMessage =
    'La proyección del saldo con tus movimientos programados está disponible en el plan Contador Profesional.';

/// Opens the plans sheet that explains the projection is not in the plan.
Future<void> showProjectionUpsell(BuildContext context) =>
    showPlanUpsell(context, title: projectionNotInPlanTitle, message: projectionNotInPlanMessage);

/// «Proyección de saldo» of a wallet (HU-25 · COU-99): the balance day by
/// day from the running scheduled rules, up to a chosen date or the
/// automatic horizon of the API.
class ProjectionPage extends StatelessWidget {
  const ProjectionPage({super.key, required this.wallet});

  /// The wallet the detail screen loaded (name).
  final Wallet wallet;

  @override
  Widget build(BuildContext context) {
    final profile = context.read<SessionCubit>().state.profile;
    return BlocProvider(
      create: (context) => ProjectionCubit(
        context.read<AnalysisRepository>(),
        walletId: wallet.walletId,
        allowed: profile?.allows(PlanFeatures.walletProjection) ?? true,
      )..load(),
      child: _ProjectionView(wallet: wallet, today: Dates.userToday(profile?.timezone)),
    );
  }
}

class _ProjectionView extends StatelessWidget {
  const _ProjectionView({required this.wallet, required this.today});

  final Wallet wallet;

  /// The user's calendar day: the API projects from it.
  final DateTime today;

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<ProjectionCubit>();
    const padding = EdgeInsets.symmetric(horizontal: AppSpacing.screen);
    return Scaffold(
      appBar: const AppTopBar(title: 'Proyección de saldo'),
      body: BlocBuilder<ProjectionCubit, ProjectionState>(
        builder: (context, state) {
          if (state.locked) {
            return EmptyState(
              key: const ValueKey('projection-locked'),
              icon: Icons.lock_outline_rounded,
              title: 'Proyección de saldo',
              message: projectionNotInPlanMessage,
              actionLabel: 'Ver planes',
              onAction: () => unawaited(showProjectionUpsell(context)),
            );
          }
          return RefreshIndicator(
            onRefresh: cubit.refresh,
            child: CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                SliverPadding(
                  padding: padding.copyWith(top: AppSpacing.sm),
                  sliver: SliverList.list(
                    children: [
                      Text(
                        'Saldo de «${wallet.name}» con sus movimientos programados activos.',
                        style: AppTypography.body.copyWith(color: context.palette.muted),
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      _UntilField(until: state.until, today: today),
                      const SizedBox(height: AppSpacing.xl),
                    ],
                  ),
                ),
                SliverPadding(
                  padding: padding.copyWith(bottom: AppSpacing.xxl * 2),
                  sliver: _content(context, state.projection),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _content(BuildContext context, LoadState<WalletProjection> state) {
    final cubit = context.read<ProjectionCubit>();
    final projection = state.data;
    if (projection == null) {
      return SliverToBoxAdapter(
        child: state.status == LoadStatus.failure
            ? NoteCard(
                icon: Icons.cloud_off_outlined,
                message: state.failure!.message,
                action: AppButton(
                  label: 'Reintentar',
                  variant: AppButtonVariant.ghost,
                  small: true,
                  expand: false,
                  onPressed: () => unawaited(cubit.refresh()),
                ),
              )
            : const SectionLoading(label: 'Cargando proyección'),
      );
    }
    final movements = projection.movements;
    return SliverMainAxisGroup(
      slivers: [
        SliverList.list(
          children: [
            if (state.status == LoadStatus.failure) ...[
              NoteCard(icon: Icons.cloud_off_outlined, message: state.failure!.message),
              const SizedBox(height: AppSpacing.lg),
            ],
            if (state.status == LoadStatus.loading) ...[
              const LinearProgressIndicator(minHeight: 2),
              const SizedBox(height: AppSpacing.md),
            ],
            _Summary(projection: projection),
            const SizedBox(height: AppSpacing.xxl),
            const SectionHeader(title: 'Saldo día a día'),
            AppCard(child: ProjectionChart(projection: projection)),
            const SizedBox(height: AppSpacing.xxl),
            const SectionHeader(title: 'Próximos movimientos'),
            if (movements.isEmpty)
              NoteCard(
                icon: Icons.event_busy_outlined,
                message:
                    'No hay movimientos programados activos hasta el ${Dates.date(projection.until)}: '
                    'el saldo se mantiene en ${Money.format(projection.currentBalanceCents / 100)}.',
              ),
          ],
        ),
        SliverList.builder(
          itemCount: movements.length,
          itemBuilder: (context, index) => ProjectionMovementRow(point: movements[index]),
        ),
      ],
    );
  }
}

/// «Proyectar hasta»: a date after today, at most a year ahead (API rule:
/// 400 `invalid_date_range` otherwise), or the automatic horizon.
class _UntilField extends StatelessWidget {
  const _UntilField({required this.until, required this.today});

  final DateTime? until;
  final DateTime today;

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<ProjectionCubit>();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: AppSpacing.xs,
      children: [
        AppDateField(
          label: 'Proyectar hasta',
          value: until,
          placeholder: 'Automático',
          firstDate: DateTime(today.year, today.month, today.day + 1),
          lastDate: DateTime(today.year + 1, today.month, today.day),
          onChanged: (day) => unawaited(cubit.selectUntil(day)),
        ),
        if (until == null)
          Text(
            'Hasta la última ejecución programada (máximo un año) o 30 días si no hay programados.',
            style: AppTypography.caption.copyWith(color: context.palette.muted),
          )
        else
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: () => unawaited(cubit.selectUntil(null)),
              child: const Text('Volver a automático'),
            ),
          ),
      ],
    );
  }
}

class _Summary extends StatelessWidget {
  const _Summary({required this.projection});

  final WalletProjection projection;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final change = projection.changeCents;
    return DetailRows(
      rows: [
        DetailRow('Saldo actual', Money.format(projection.currentBalanceCents / 100), money: true),
        DetailRow(
          'Saldo al ${Dates.date(projection.until)}',
          Money.format(projection.projectedBalanceCents / 100),
          money: true,
        ),
        DetailRow(
          'Variación',
          Money.signed(change.abs() / 100, income: change >= 0),
          color: change == 0 ? null : (change > 0 ? palette.income : palette.expense),
          money: true,
        ),
      ],
    );
  }
}

/// Balance day by day (stepped: it only changes on the days with movements).
class ProjectionChart extends StatefulWidget {
  const ProjectionChart({super.key, required this.projection});

  final WalletProjection projection;

  @override
  State<ProjectionChart> createState() => _ProjectionChartState();
}

class _ProjectionChartState extends State<ProjectionChart> {
  late List<TrendPoint> _points;
  late Map<DateTime, ProjectionPoint> _byDay;
  late String _summary;

  @override
  void initState() {
    super.initState();
    _prepare();
  }

  @override
  void didUpdateWidget(ProjectionChart oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.projection, widget.projection)) _prepare();
  }

  /// Once per answer. The last day is added when no movement falls on it,
  /// so the line reaches the horizon.
  void _prepare() {
    final projection = widget.projection;
    final points = [for (final p in projection.points) TrendPoint(p.date, p.balanceCents)];
    if (points.isEmpty || points.last.date.isBefore(projection.until)) {
      points.add(TrendPoint(projection.until, projection.projectedBalanceCents));
    }
    _points = List.unmodifiable(points);
    _byDay = {for (final p in projection.points) p.date: p};
    _summary = projectionSummary(projection);
  }

  @override
  Widget build(BuildContext context) {
    return TrendLineChart(
      points: _points,
      summary: _summary,
      stepped: true,
      describe: (point) {
        final day = _byDay[point.date];
        final moves = day == null || !day.hasMovements
            ? ''
            : ' (${[if (day.incomeCents > 0) Money.signed(day.incomeCents / 100, income: true), if (day.expenseCents > 0) Money.signed(day.expenseCents / 100, income: false)].join(' · ')})';
        return '${Dates.date(point.date)}: saldo ${Money.format(point.cents / 100)}$moves';
      },
    );
  }
}

/// Spoken summary of the projection chart.
String projectionSummary(WalletProjection projection) {
  var low = projection.points.isEmpty ? null : projection.points.first;
  for (final point in projection.points) {
    if (point.balanceCents < low!.balanceCents) low = point;
  }
  final buffer = StringBuffer(
    'Gráfico de saldo proyectado hasta el ${Dates.date(projection.until)}. '
    'Hoy ${Money.format(projection.currentBalanceCents / 100)}, '
    'al final ${Money.format(projection.projectedBalanceCents / 100)}.',
  );
  if (low != null && low.balanceCents < projection.currentBalanceCents) {
    buffer.write(' Punto más bajo: ${Money.format(low.balanceCents / 100)} el ${Dates.date(low.date)}.');
  }
  return buffer.toString();
}

/// A day with scheduled movements: date, signed income/expense and the
/// balance after them, read as one sentence.
class ProjectionMovementRow extends StatelessWidget {
  const ProjectionMovementRow({super.key, required this.point});

  final ProjectionPoint point;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final income = point.incomeCents > 0 ? Money.signed(point.incomeCents / 100, income: true) : null;
    final expense = point.expenseCents > 0 ? Money.signed(point.expenseCents / 100, income: false) : null;
    final balance = Money.format(point.balanceCents / 100);
    return Semantics(
      container: true,
      excludeSemantics: true,
      label: '${Dates.date(point.date)}: ${[?income, ?expense].join(', ')}. Saldo después: $balance',
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
        child: Row(
          spacing: AppSpacing.md,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(Dates.date(point.date), style: AppTypography.label),
                  Text('Saldo después: $balance', style: AppTypography.caption.copyWith(color: palette.muted)),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (income != null)
                  Text(income, style: AppTypography.money.copyWith(fontSize: 14, color: palette.income)),
                if (expense != null)
                  Text(expense, style: AppTypography.money.copyWith(fontSize: 14, color: palette.expense)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
