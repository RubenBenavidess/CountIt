import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../app/errors/app_failure.dart';
import '../../../app/router/app_router.dart';
import '../../../app/theme/app_theme.dart';
import '../../../app/theme/tokens.dart';
import '../../../data/dtos/wallet.dart';
import '../../../data/repositories/family_repository.dart';
import '../../../shared/state/submit_cubit.dart';
import '../../../shared/utils/validators.dart';
import '../../../shared/widgets/app_banner.dart';
import '../../../shared/widgets/app_button.dart';
import '../../../shared/widgets/app_card.dart';
import '../../../shared/widgets/app_feedback.dart';
import '../../../shared/widgets/app_fields.dart';
import '../../../shared/widgets/app_layout.dart';
import '../../plans/view/plan_upsell_sheet.dart';
import '../cubit/invite_member_cubit.dart';

/// Shown when the plan has no shared wallets (local check or 403).
const familiesNotInPlanTitle = 'Tu plan no incluye familias';

/// «Invitar a la familia» (HU-21 · COU-90, COU-157): the owner invites a user
/// by username; the invitation is pending for 7 days. Pops with `true`.
class InviteMemberPage extends StatelessWidget {
  const InviteMemberPage({super.key, required this.wallet});

  final Wallet wallet;

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) => InviteMemberCubit(context.read<FamilyRepository>(), walletId: wallet.walletId),
      child: _InviteMemberView(wallet: wallet),
    );
  }
}

class _InviteMemberView extends StatefulWidget {
  const _InviteMemberView({required this.wallet});

  final Wallet wallet;

  @override
  State<_InviteMemberView> createState() => _InviteMemberViewState();
}

class _InviteMemberViewState extends State<_InviteMemberView> {
  /// Backend keys answered next to the username field.
  static const fieldKeys = {
    'required_field',
    'user_not_found',
    'self_invitation',
    'already_member',
    'invitation_pending',
  };

  final _formKey = GlobalKey<FormState>();
  final _username = TextEditingController();

  @override
  void dispose() {
    _username.dispose();
    super.dispose();
  }

  Future<void> _invite() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    await context.read<InviteMemberCubit>().invite(_username.text);
  }

  void _onState(BuildContext context, SubmitState state) {
    switch (state.status) {
      case SubmitStatus.success:
        showAppSnackBar(
          context,
          'Invitamos a @${_username.text.trim()}. Tiene 7 días para aceptar.',
          kind: SnackKind.success,
        );
        context.pop(true);
      case SubmitStatus.failure:
        final failure = state.failure!;
        if (failure.kind == FailureKind.featureNotInPlan) {
          unawaited(showPlanUpsell(context, title: familiesNotInPlanTitle, message: failure.message));
        } else if (failure.isQuota) {
          unawaited(showPlanUpsell(context, message: failure.message));
        } else if (failure.key == 'wallet_not_found') {
          // Deleted, or no longer ours: nothing left to share.
          showAppSnackBar(context, failure.message, kind: SnackKind.error);
          context.go(AppRoutes.home);
        }
      case SubmitStatus.idle || SubmitStatus.submitting:
        break;
    }
  }

  /// Field errors stay next to the field; plan and quota open the sheet.
  static String? _bannerError(AppFailure? failure) {
    if (failure == null || fieldKeys.contains(failure.key)) return null;
    if (failure.kind == FailureKind.featureNotInPlan || failure.isQuota || failure.key == 'wallet_not_found') {
      return null;
    }
    return failure.message;
  }

  @override
  Widget build(BuildContext context) {
    final muted = context.palette.muted;
    return Scaffold(
      appBar: const AppTopBar(title: 'Invitar a la familia'),
      body: BlocConsumer<InviteMemberCubit, SubmitState>(
        listenWhen: (previous, current) => previous.status != current.status,
        listener: _onState,
        builder: (context, state) {
          final failure = state.failure;
          final banner = _bannerError(failure);
          final busy = state.submitting || state.status == SubmitStatus.success;
          return Form(
            key: _formKey,
            child: FormScreenBody(
              content: [
                Row(
                  spacing: 14,
                  children: [
                    const IconTile(Icons.group_add_outlined, size: 48),
                    Expanded(
                      child: Text(
                        'Comparte «${widget.wallet.name}» con alguien que ya use Count It!',
                        style: AppTypography.body,
                      ),
                    ),
                  ],
                ),
                Text(
                  'Podrá ver sus movimientos y presupuestos y registrar los suyos. '
                  'No podrá editar ni eliminar la billetera.',
                  style: AppTypography.caption.copyWith(color: muted),
                ),
                if (banner != null) AppBanner(tone: BannerTone.error, message: banner),
                AppTextField(
                  label: 'Nombre de usuario',
                  controller: _username,
                  hint: 'usuario',
                  helper: 'La invitación vence en 7 días.',
                  prefix: const Padding(
                    padding: EdgeInsetsDirectional.only(start: 16, end: 4),
                    child: Text('@', style: AppTypography.body),
                  ),
                  maxLength: 12,
                  enabled: !busy,
                  textInputAction: TextInputAction.done,
                  // Usernames: letters, digits, «-» and «_» (no spaces or «@»).
                  inputFormatters: [FilteringTextInputFormatter.allow(RegExp('[A-Za-z0-9_-]'))],
                  validator: Validators.username,
                  errorText: fieldKeys.contains(failure?.key) ? failure!.message : null,
                  onChanged: (_) => context.read<InviteMemberCubit>().clearFailure(),
                  onSubmitted: (_) => _invite(),
                ),
              ],
              footer: [AppButton(label: 'Enviar invitación', loading: busy, onPressed: _invite)],
            ),
          );
        },
      ),
    );
  }
}
