import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../app/errors/app_failure.dart';
import '../../../app/session/session_cubit.dart';
import '../../../app/theme/app_theme.dart';
import '../../../app/theme/tokens.dart';
import '../../../data/repositories/auth_repository.dart';
import '../../../data/repositories/profile_repository.dart';
import '../../../shared/platform/file_sharer.dart';
import '../../../shared/state/submit_cubit.dart';
import '../../../shared/utils/validators.dart';
import '../../../shared/widgets/app_banner.dart';
import '../../../shared/widgets/app_button.dart';
import '../../../shared/widgets/app_card.dart';
import '../../../shared/widgets/app_feedback.dart';
import '../../../shared/widgets/app_fields.dart';
import '../../../shared/widgets/app_layout.dart';
import '../../../shared/widgets/cooldown_button.dart';
import '../../../shared/widgets/secure_screen.dart';
import '../../profile/cubit/profile_cubits.dart';
import '../cubit/account_cubits.dart';

/// HU-30, LOPDP (design EliminarCuenta · COU-149, COU-150).
class DeleteAccountPage extends StatelessWidget {
  const DeleteAccountPage({super.key, this.sharer = const SystemFileSharer()});

  final FileSharer sharer;

  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      providers: [
        BlocProvider(
          create: (context) =>
              DeleteAccountCubit(auth: context.read<AuthRepository>(), session: context.read<SessionCubit>()),
        ),
        BlocProvider(
          create: (context) => ExportDataCubit(profiles: context.read<ProfileRepository>(), sharer: sharer),
        ),
      ],
      child: const SecureScreen(child: _DeleteAccountView()),
    );
  }
}

class _DeleteAccountView extends StatefulWidget {
  const _DeleteAccountView();

  @override
  State<_DeleteAccountView> createState() => _DeleteAccountViewState();
}

class _DeleteAccountViewState extends State<_DeleteAccountView> {
  final _formKey = GlobalKey<FormState>();
  final _password = TextEditingController();
  final _word = TextEditingController();

  static const _consequences = [
    'Tus billeteras se cierran junto con sus presupuestos, pagos programados y familias.',
    'Sales de las billeteras que otros comparten contigo; tus movimientos allí se conservan sin tu nombre.',
    'Anonimizamos tus datos personales (LOPDP) y cerramos todas tus sesiones.',
  ];

  @override
  void dispose() {
    _password.dispose();
    _word.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    await context.read<DeleteAccountCubit>().delete(_password.text);
  }

  @override
  Widget build(BuildContext context) {
    final expense = context.palette.expense;
    return Scaffold(
      appBar: const AppTopBar(title: 'Eliminar mi cuenta'),
      body: BlocListener<ExportDataCubit, SubmitState>(
        listenWhen: (previous, current) => current.status == SubmitStatus.failure,
        listener: (context, state) => showFailureSnackBar(context, state.failure!),
        child: BlocConsumer<DeleteAccountCubit, SubmitState>(
          listenWhen: (previous, current) => current.status == SubmitStatus.failure,
          listener: (context, state) => _password.clear(),
          builder: (context, state) {
            final failure = state.failure;
            final wrongPassword = failure?.kind == FailureKind.invalidCredentials;
            final busy = state.submitting || state.status == SubmitStatus.success;
            return Form(
              key: _formKey,
              child: FormScreenBody(
                content: [
                  Row(
                    spacing: 14,
                    children: [
                      IconTile(Icons.warning_amber_rounded, size: 52, color: expense),
                      Expanded(
                        child: Semantics(
                          header: true,
                          child: Text(
                            'Esta acción no se puede deshacer',
                            style: AppTypography.h1.copyWith(fontSize: 22),
                          ),
                        ),
                      ),
                    ],
                  ),
                  for (final line in _consequences)
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      spacing: 10,
                      children: [
                        const Padding(
                          padding: EdgeInsets.only(top: 3),
                          child: Icon(Icons.circle_outlined, size: 14, color: AppColors.muted),
                        ),
                        Expanded(child: Text(line, style: AppTypography.body.copyWith(fontSize: 14))),
                      ],
                    ),
                  const _ExportFirst(),
                  if (failure != null && !wrongPassword) AppBanner(tone: BannerTone.error, message: failure.message),
                  AppPasswordField(
                    controller: _password,
                    errorText: wrongPassword ? failure!.message : null,
                    validator: Validators.existingPassword,
                    enabled: !busy,
                    textInputAction: TextInputAction.next,
                  ),
                  AppTextField(
                    label: 'Escribe $accountDeletionWord para confirmar',
                    controller: _word,
                    textCapitalization: TextCapitalization.characters,
                    enabled: !busy,
                    textInputAction: TextInputAction.done,
                  ),
                ],
                footer: [
                  // Enabled only with the exact word (COU-149); rebuilds alone as it is typed.
                  ValueListenableBuilder<TextEditingValue>(
                    valueListenable: _word,
                    builder: (context, word, _) => CooldownButton(
                      label: 'Eliminar mi cuenta',
                      variant: AppButtonVariant.dangerSolid,
                      loading: busy,
                      until: state.blockedUntil,
                      onPressed: word.text == accountDeletionWord && failure?.kind != FailureKind.locked
                          ? _submit
                          : null,
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

/// «Antes, descarga tus datos» (design): exports right here.
class _ExportFirst extends StatelessWidget {
  const _ExportFirst();

  @override
  Widget build(BuildContext context) {
    final exporting = context.select((ExportDataCubit c) => c.state.submitting);
    return AppCard(
      outlined: true,
      onTap: exporting ? null : () => context.read<ExportDataCubit>().export(),
      semanticLabel: 'Antes, descarga tus datos',
      child: Row(
        spacing: AppSpacing.md,
        children: [
          const Icon(Icons.download_rounded, size: 20),
          Expanded(child: Text('Antes, descarga tus datos', style: AppTypography.label.copyWith(fontSize: 15))),
          if (exporting)
            const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
          else
            const Icon(Icons.chevron_right_rounded, color: AppColors.muted),
        ],
      ),
    );
  }
}
