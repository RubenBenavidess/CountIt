import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router/app_router.dart';
import '../../../app/session/session_cubit.dart';
import '../../../app/theme/app_theme.dart';
import '../../../app/theme/tokens.dart';
import '../../../data/dtos/transaction.dart';
import '../../../data/repositories/transaction_repository.dart';
import '../../../shared/state/delete_cubit.dart';
import '../../../shared/utils/dates.dart';
import '../../../shared/utils/money.dart';
import '../../../shared/widgets/app_button.dart';
import '../../../shared/widgets/app_card.dart';
import '../../../shared/widgets/app_dialogs.dart';
import '../../../shared/widgets/app_feedback.dart';
import '../../../shared/widgets/app_layout.dart';
import '../../../shared/widgets/detail_rows.dart';
import '../../account/view/reauth_sheet.dart';
import '../cubit/transaction_detail_cubit.dart';
import 'widgets/transaction_tile.dart';

/// What the wallet passes to the detail route: the listed transaction and
/// whether the caller may edit or delete it ([Transaction.canBeManagedBy]).
class TransactionDetailArgs {
  const TransactionDetailArgs(this.transaction, {this.canManage = false});

  final Transaction transaction;
  final bool canManage;
}

/// One transaction with its budget and author (HU-17..HU-19 · COU-240,
/// COU-241). Pops with `true` when it was edited or deleted, so the wallet
/// reloads its balance, budgets and movements.
class TransactionDetailPage extends StatelessWidget {
  const TransactionDetailPage({super.key, required this.walletId, required this.args});

  final int walletId;
  final TransactionDetailArgs args;

  @override
  Widget build(BuildContext context) {
    final transactions = context.read<TransactionRepository>();
    return MultiBlocProvider(
      providers: [
        BlocProvider(create: (_) => TransactionDetailCubit(transactions, initial: args.transaction)),
        BlocProvider(
          create: (_) => TransactionDeleteCubit(transactions, transactionId: args.transaction.transactionId),
        ),
      ],
      child: _TransactionDetailView(walletId: walletId, canManage: args.canManage),
    );
  }
}

class _TransactionDetailView extends StatelessWidget {
  const _TransactionDetailView({required this.walletId, required this.canManage});

  final int walletId;
  final bool canManage;

  void _leave(BuildContext context) => context.pop(context.read<TransactionDetailCubit>().state.changed);

  Future<void> _edit(BuildContext context, Transaction transaction) async {
    final cubit = context.read<TransactionDetailCubit>();
    final saved = await context.push<bool>(
      AppRoutes.editTransaction(walletId, transaction.transactionId),
      extra: transaction,
    );
    if (saved == true && !cubit.isClosed) unawaited(cubit.edited());
  }

  Future<void> _delete(BuildContext context, Transaction transaction) async {
    final cubit = context.read<TransactionDeleteCubit>();
    final confirmed = await showConfirmDialog(
      context,
      title: '¿Eliminar «${transaction.name}»?',
      message: 'Dejará de contar en el saldo de la billetera y en sus presupuestos.',
      confirmLabel: 'Eliminar',
      destructive: true,
    );
    if (!confirmed || !context.mounted) return;
    await cubit.delete(
      onReauth: reauthPrompt(context, action: 'eliminar «${transaction.name}»', confirmLabel: 'Eliminar movimiento'),
    );
  }

  void _onDeleteState(BuildContext context, DeleteState state) {
    switch (state.status) {
      case DeleteStatus.deleted:
        final name = context.read<TransactionDetailCubit>().state.transaction.name;
        showAppSnackBar(context, 'Eliminamos «$name»', kind: SnackKind.success);
        context.pop(true);
      case DeleteStatus.failure:
        showFailureSnackBar(context, state.failure!);
      case DeleteStatus.idle || DeleteStatus.deleting:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<TransactionDetailCubit, TransactionDetailState>(
      listenWhen: (previous, current) => current.missing && !previous.missing,
      listener: (context, state) {
        showAppSnackBar(context, 'Transacción no encontrada', kind: SnackKind.error);
        context.pop(true);
      },
      child: PopScope<Object?>(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) _leave(context);
        },
        child: Scaffold(
          appBar: AppTopBar(title: 'Movimiento', onBack: () => _leave(context)),
          body: BlocBuilder<TransactionDetailCubit, TransactionDetailState>(
            builder: (context, state) {
              final transaction = state.transaction;
              return ListView(
                padding: const EdgeInsets.fromLTRB(AppSpacing.screen, AppSpacing.sm, AppSpacing.screen, AppSpacing.xxl),
                children: [
                  if (state.reloading) const LinearProgressIndicator(minHeight: 2),
                  _Summary(transaction: transaction),
                  const SizedBox(height: AppSpacing.lg),
                  _Facts(transaction: transaction),
                  const SizedBox(height: AppSpacing.xxl),
                  if (canManage)
                    BlocConsumer<TransactionDeleteCubit, DeleteState>(
                      listenWhen: (previous, current) => previous.status != current.status,
                      listener: _onDeleteState,
                      builder: (context, delete) => Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        spacing: AppSpacing.md,
                        children: [
                          AppButton(
                            label: 'Editar movimiento',
                            icon: Icons.edit_outlined,
                            variant: AppButtonVariant.ghost,
                            onPressed: delete.deleting ? null : () => _edit(context, transaction),
                          ),
                          AppButton(
                            label: 'Eliminar movimiento',
                            icon: Icons.delete_outline_rounded,
                            variant: AppButtonVariant.danger,
                            loading: delete.deleting,
                            onPressed: () => _delete(context, transaction),
                          ),
                        ],
                      ),
                    )
                  else
                    Text(
                      'Solo quien lo registró o el dueño de la billetera puede editarlo o eliminarlo.',
                      style: AppTypography.caption.copyWith(color: context.palette.muted),
                      textAlign: TextAlign.center,
                    ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

/// Icon, type, name and the signed amount, read as one sentence.
class _Summary extends StatelessWidget {
  const _Summary({required this.transaction});

  final Transaction transaction;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final t = transaction;
    final color = t.isIncome ? palette.income : palette.expense;
    return AppCard(
      semanticLabel: '${t.type.label} ${t.name}, ${t.isIncome ? 'más' : 'menos'} ${Money.format(t.amount)}',
      child: ExcludeSemantics(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: AppSpacing.md,
          children: [
            Row(
              spacing: AppSpacing.md,
              children: [
                IconTile(t.iconData, size: 48, color: t.hasBudget ? AppColors.lavender : color),
                Expanded(
                  child: Text(t.type.label, style: AppTypography.overline.copyWith(color: palette.muted)),
                ),
                if (t.isScheduled) const AppBadge('Programada'),
              ],
            ),
            Text(t.name, style: AppTypography.h1),
            Text(t.signedAmount, style: AppTypography.money.copyWith(fontSize: 32, color: color)),
          ],
        ),
      ),
    );
  }
}

/// Date, budget, author and record times (in the user's zone).
class _Facts extends StatelessWidget {
  const _Facts({required this.transaction});

  final Transaction transaction;

  @override
  Widget build(BuildContext context) {
    final timezone = context.select((SessionCubit c) => c.state.profile?.timezone);
    final t = transaction;
    final created = t.createdAt;
    final updated = t.updatedAt;
    final long = Dates.long(t.date);
    return DetailRows(
      rows: [
        DetailRow('Fecha', '${long[0].toUpperCase()}${long.substring(1)}'),
        DetailRow('Presupuesto', t.budgetLabel),
        DetailRow('Registrado por', t.authorLabel),
        if (created != null) DetailRow('Registrado el', Dates.dateTime(Dates.inUserZone(created, timezone))),
        if (updated != null && created != null && updated.isAfter(created))
          DetailRow('Última edición', Dates.dateTime(Dates.inUserZone(updated, timezone))),
      ],
    );
  }
}
