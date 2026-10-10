import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router/app_router.dart';
import '../../../app/theme/app_theme.dart';
import '../../../app/theme/tokens.dart';
import '../../../data/dtos/bank.dart';
import '../../../data/dtos/json_parsing.dart';
import '../../../data/repositories/admin_repository.dart';
import '../../../shared/widgets/app_button.dart';
import '../../../shared/widgets/app_card.dart';
import '../../../shared/widgets/app_dialogs.dart';
import '../../../shared/widgets/app_feedback.dart';
import '../../../shared/widgets/app_fields.dart';
import '../../../shared/widgets/app_layout.dart';
import '../cubit/admin_banks_cubit.dart';
import 'widgets/role_guard.dart';

/// Banks for admins (HU-27 · COU-205, COU-207): every bank (inactive ones
/// too), filter by name, create, edit and (de)activate.
class AdminBanksPage extends StatelessWidget {
  const AdminBanksPage({super.key});

  @override
  Widget build(BuildContext context) => RoleGuard(
    allows: RoleGuard.admin,
    builder: (context) => BlocProvider(
      create: (context) => AdminBanksCubit(context.read<AdminRepository>())..load(),
      child: const _AdminBanksView(),
    ),
  );
}

class _AdminBanksView extends StatelessWidget {
  const _AdminBanksView();

  Future<void> _open(BuildContext context, {Bank? bank}) async {
    final cubit = context.read<AdminBanksCubit>();
    final saved = await context.push<Bank>(
      bank == null ? AppRoutes.newBank : AppRoutes.editBank(bank.bankId),
      extra: bank,
    );
    if (saved != null && !cubit.isClosed) cubit.upsert(saved);
  }

  /// Deactivating asks first; reactivating does not.
  Future<void> _toggle(BuildContext context, Bank bank, bool active) async {
    final cubit = context.read<AdminBanksCubit>();
    if (!active) {
      final confirmed = await showConfirmDialog(
        context,
        title: '¿Desactivar «${bank.name}»?',
        message:
            'Dejará de ofrecerse al crear o editar billeteras. Las billeteras que ya lo usan lo conservan. '
            'Puedes reactivarlo cuando quieras.',
        confirmLabel: 'Desactivar',
        destructive: true,
      );
      if (!confirmed) return;
    }
    final ok = await cubit.setActive(bank, active: active);
    if (ok && context.mounted) {
      showAppSnackBar(
        context,
        active ? '«${bank.name}» está activo' : '«${bank.name}» quedó desactivado',
        kind: SnackKind.success,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const AppTopBar(title: 'Bancos'),
      body: BlocConsumer<AdminBanksCubit, AdminBanksState>(
        listenWhen: (previous, current) => current.failure != null && previous.revision != current.revision,
        listener: (context, state) => showFailureSnackBar(context, state.failure!),
        builder: (context, state) {
          final cubit = context.read<AdminBanksCubit>();
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(AppSpacing.screen, AppSpacing.sm, AppSpacing.screen, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  spacing: AppSpacing.md,
                  children: [
                    AppButton(
                      key: const ValueKey('bank-new'),
                      label: 'Nuevo banco',
                      icon: Icons.add_rounded,
                      onPressed: () => unawaited(_open(context)),
                    ),
                    AppTextField(
                      key: const ValueKey('admin-banks-search'),
                      label: 'Buscar',
                      hint: 'Nombre del banco',
                      prefix: const Icon(Icons.search_rounded),
                      textInputAction: TextInputAction.search,
                      onChanged: cubit.search,
                    ),
                  ],
                ),
              ),
              Expanded(
                child: LoadStateView<List<Bank>>(
                  state: state.banks,
                  onRetry: cubit.load,
                  isEmpty: (_) => state.visible.isEmpty,
                  empty: EmptyState(
                    icon: Icons.account_balance_outlined,
                    title: 'Sin resultados',
                    message: state.search.isEmpty
                        ? 'Todavía no hay bancos.'
                        : 'Ningún banco contiene «${state.search}».',
                  ),
                  builder: (context, _) {
                    final banks = state.visible;
                    return RefreshIndicator(
                      onRefresh: cubit.load,
                      child: ListView.separated(
                        key: const PageStorageKey('admin-banks'),
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.fromLTRB(
                          AppSpacing.screen,
                          AppSpacing.md,
                          AppSpacing.screen,
                          AppSpacing.xxl,
                        ),
                        itemCount: banks.length,
                        separatorBuilder: (context, index) => const SizedBox(height: AppSpacing.sm),
                        itemBuilder: (context, index) {
                          final bank = banks[index];
                          return BankAdminTile(
                            key: ValueKey('bank-${bank.bankId}'),
                            bank: bank,
                            busy: state.toggling.contains(bank.bankId),
                            onEdit: () => unawaited(_open(context, bank: bank)),
                            onActiveChanged: (active) => unawaited(_toggle(context, bank, active)),
                          );
                        },
                      ),
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// A bank row: colour dot, name, country and colour code, active switch.
class BankAdminTile extends StatelessWidget {
  const BankAdminTile({
    super.key,
    required this.bank,
    required this.busy,
    required this.onEdit,
    required this.onActiveChanged,
  });

  final Bank bank;
  final bool busy;
  final VoidCallback onEdit;
  final ValueChanged<bool> onActiveChanged;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final hex = toHexColor(bank.color);
    // Admins configure the raw accent colour; users only see it muted.
    final dot = bank.color == null ? AppColors.defaultWallet : Color(bank.color!);
    final details = [bank.countryCode ?? '—', hex ?? 'Sin color', if (!bank.isActive) 'Inactivo'].join(' · ');
    return AppCard(
      padding: const EdgeInsets.only(left: AppSpacing.lg, right: AppSpacing.sm),
      child: Row(
        spacing: AppSpacing.md,
        children: [
          Expanded(
            child: Semantics(
              button: true,
              label: 'Editar ${bank.name}. $details',
              excludeSemantics: true,
              child: InkWell(
                onTap: onEdit,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 64),
                  child: Row(
                    spacing: AppSpacing.md,
                    children: [
                      Container(
                        width: 28,
                        height: 28,
                        decoration: BoxDecoration(
                          color: dot,
                          shape: BoxShape.circle,
                          border: Border.all(color: palette.line),
                        ),
                      ),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          spacing: 2,
                          children: [
                            Text(
                              bank.name,
                              style: AppTypography.label.copyWith(color: bank.isActive ? null : palette.muted),
                            ),
                            Text(details, style: AppTypography.caption.copyWith(color: palette.muted)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          if (busy)
            const Padding(
              padding: EdgeInsets.all(AppSpacing.md),
              child: SizedBox.square(dimension: 24, child: CircularProgressIndicator(strokeWidth: 2.5)),
            )
          else
            Semantics(
              label: bank.isActive ? '${bank.name} activo' : '${bank.name} inactivo',
              child: Switch(value: bank.isActive, onChanged: onActiveChanged),
            ),
        ],
      ),
    );
  }
}
