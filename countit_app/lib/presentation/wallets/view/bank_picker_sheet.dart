import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../app/theme/app_theme.dart';
import '../../../app/theme/tokens.dart';
import '../../../data/dtos/bank.dart';
import '../../../data/repositories/bank_repository.dart';
import '../../../shared/state/load_state.dart';
import '../../../shared/widgets/app_feedback.dart';
import '../../../shared/widgets/app_fields.dart';
import '../cubit/bank_picker_cubit.dart';
import 'widgets/bank_disclaimer.dart';
import 'widgets/wallet_colors.dart';

/// What the user picked in the bank sheet: a bank or «Sin banco» ([bank] null).
class BankSelection {
  const BankSelection(this.bank);

  final Bank? bank;
}

/// Bank picker of the catalogue (COU-190). Returns null when dismissed.
Future<BankSelection?> pickBank(BuildContext context, {int? selectedId}) {
  final banks = context.read<BankRepository>();
  return showModalBottomSheet<BankSelection>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => BlocProvider(
      create: (_) => BankPickerCubit(banks)..load(),
      child: _BankPickerSheet(selectedId: selectedId),
    ),
  );
}

class _BankPickerSheet extends StatelessWidget {
  const _BankPickerSheet({this.selectedId});

  final int? selectedId;

  @override
  Widget build(BuildContext context) {
    final height = MediaQuery.sizeOf(context).height * 0.75;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SizedBox(
        height: height,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(AppSpacing.screen, 0, AppSpacing.screen, AppSpacing.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                spacing: AppSpacing.md,
                children: [
                  Semantics(header: true, child: const Text('Elige un banco', style: AppTypography.h2)),
                  AppTextField(
                    label: 'Buscar',
                    hint: 'Nombre del banco',
                    prefix: const Icon(Icons.search_rounded),
                    textInputAction: TextInputAction.search,
                    onChanged: context.read<BankPickerCubit>().search,
                  ),
                ],
              ),
            ),
            Expanded(
              child: BlocBuilder<BankPickerCubit, LoadState<List<Bank>>>(
                builder: (context, state) {
                  final banks = state.data;
                  if (banks == null) {
                    return state.status == LoadStatus.failure
                        ? ErrorView.failure(
                            state.failure!,
                            onRetry: () => unawaited(context.read<BankPickerCubit>().load()),
                          )
                        : const LoadingView();
                  }
                  return ListView(
                    padding: const EdgeInsets.only(bottom: AppSpacing.md),
                    children: [
                      _BankTile(
                        name: 'Sin banco',
                        color: AppColors.defaultWallet,
                        selected: selectedId == null,
                        onTap: () => Navigator.of(context).pop(const BankSelection(null)),
                      ),
                      if (banks.isEmpty)
                        Padding(
                          padding: const EdgeInsets.all(AppSpacing.xl),
                          child: Text(
                            'No encontramos bancos con ese nombre.',
                            textAlign: TextAlign.center,
                            style: AppTypography.caption.copyWith(color: context.palette.muted),
                          ),
                        ),
                      for (final bank in banks)
                        _BankTile(
                          name: bank.name,
                          color: bankAccentOf(bank.color),
                          selected: bank.bankId == selectedId,
                          onTap: () => Navigator.of(context).pop(BankSelection(bank)),
                        ),
                    ],
                  );
                },
              ),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(AppSpacing.screen, AppSpacing.sm, AppSpacing.screen, AppSpacing.lg),
              child: BankDisclaimer(),
            ),
          ],
        ),
      ),
    );
  }
}

class _BankTile extends StatelessWidget {
  const _BankTile({required this.name, required this.color, required this.selected, required this.onTap});

  final String name;
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      minTileHeight: 56,
      contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.screen),
      selected: selected,
      leading: Container(
        width: 28,
        height: 28,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(color: context.palette.line, width: AppSizes.borderWidth),
        ),
      ),
      title: Text(name, style: AppTypography.body, maxLines: 2, overflow: TextOverflow.ellipsis),
      trailing: selected ? const Icon(Icons.check_rounded, color: AppColors.lavender) : null,
      onTap: onTap,
    );
  }
}
