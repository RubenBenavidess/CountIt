import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router/app_router.dart';
import '../../../app/session/session_cubit.dart';
import '../../../app/theme/app_theme.dart';
import '../../../app/theme/tokens.dart';
import '../../../data/dtos/profile.dart';
import '../../../data/repositories/profile_repository.dart';
import '../../../shared/platform/file_sharer.dart';
import '../../../shared/state/submit_cubit.dart';
import '../../../shared/utils/dates.dart';
import '../../../shared/widgets/app_card.dart';
import '../../../shared/widgets/app_dialogs.dart';
import '../../../shared/widgets/app_feedback.dart';
import '../../../shared/widgets/app_layout.dart';
import '../../plans/view/plan_details.dart';
import '../../plans/view/widgets/plan_widgets.dart';
import '../cubit/profile_cubits.dart';

/// Profile and account actions (HU-05, design Perfil · COU-143, COU-128, COU-148).
class ProfilePage extends StatelessWidget {
  const ProfilePage({super.key, this.sharer = const SystemFileSharer()});

  final FileSharer sharer;

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) => ExportDataCubit(profiles: context.read<ProfileRepository>(), sharer: sharer),
      child: const _ProfileView(),
    );
  }
}

class _ProfileView extends StatelessWidget {
  const _ProfileView();

  Future<void> _signOut(BuildContext context) async {
    final session = context.read<SessionCubit>();
    final confirmed = await showConfirmDialog(
      context,
      title: '¿Cerrar sesión?',
      message: 'Tendrás que ingresar tu correo y contraseña para volver.',
      confirmLabel: 'Cerrar sesión',
    );
    if (confirmed) await session.signOut();
  }

  @override
  Widget build(BuildContext context) {
    // Rebuilds only when the profile changes, not on other session updates.
    final profile = context.select((SessionCubit c) => c.state.profile);
    if (profile == null) return const Scaffold(body: LoadingView());
    return Scaffold(
      appBar: const AppTopBar(title: 'Perfil'),
      body: BlocListener<ExportDataCubit, SubmitState>(
        listenWhen: (previous, current) => current.status == SubmitStatus.failure,
        listener: (context, state) => showFailureSnackBar(context, state.failure!),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(AppSpacing.screen, AppSpacing.md, AppSpacing.screen, AppSpacing.xxl),
          children: [
            _Identity(profile: profile),
            const SizedBox(height: AppSpacing.lg),
            if (profile.plan != null) _PlanCard(plan: profile.plan!, today: Dates.userToday(profile.timezone)),
            const SizedBox(height: AppSpacing.lg),
            _ActionList(
              items: [
                _Action(
                  icon: Icons.person_outline_rounded,
                  label: 'Datos personales',
                  onTap: () => context.push(AppRoutes.editProfile),
                ),
                _Action(
                  icon: Icons.lock_outline_rounded,
                  label: 'Cambiar contraseña',
                  onTap: () => context.push(AppRoutes.changePassword),
                ),
                const _ExportAction(),
                _Action(
                  icon: Icons.delete_outline_rounded,
                  label: 'Eliminar mi cuenta',
                  destructive: true,
                  onTap: () => context.push(AppRoutes.deleteAccount),
                ),
                if (profile.role.canAdminister)
                  _Action(
                    icon: Icons.shield_outlined,
                    label: 'Administración',
                    caption: 'Usuarios, planes, bancos y auditoría',
                    onTap: () => context.push(AppRoutes.admin),
                  ),
                _Action(
                  icon: Icons.logout_rounded,
                  label: 'Cerrar sesión',
                  chevron: false,
                  onTap: () => _signOut(context),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Identity extends StatelessWidget {
  const _Identity({required this.profile});

  final Profile profile;

  String get _initials {
    final parts = [profile.firstName, profile.lastName].whereType<String>().where((p) => p.isNotEmpty);
    final letters = parts.map((p) => p.characters.first.toUpperCase()).join();
    return letters.isEmpty ? profile.username.characters.first.toUpperCase() : letters;
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      spacing: AppSpacing.lg,
      children: [
        ExcludeSemantics(
          child: CircleAvatar(
            radius: 32,
            backgroundColor: AppColors.dusk,
            child: Text(_initials, style: AppTypography.title.copyWith(color: AppColors.white)),
          ),
        ),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: 2,
            children: [
              Text(profile.displayName, style: AppTypography.h1.copyWith(fontSize: 22)),
              Text(
                '@${profile.username} · ${profile.timezone}',
                style: AppTypography.caption.copyWith(color: AppColors.muted),
              ),
              Text(profile.email, style: AppTypography.caption.copyWith(color: AppColors.muted)),
            ],
          ),
        ),
      ],
    );
  }
}

/// Summary of the plan (COU-113): name, price and validity; tapping opens «Mi plan».
class _PlanCard extends StatelessWidget {
  const _PlanCard({required this.plan, required this.today});

  final UserPlan plan;
  final DateTime today;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final price = planPrice(plan);
    return AppCard(
      key: const ValueKey('profile-plan-card'),
      onTap: () => context.push(AppRoutes.myPlan),
      semanticLabel: 'Tu plan: ${plan.name}. Ver límites y funciones',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: AppSpacing.xs,
        children: [
          Text('TU PLAN', style: AppTypography.overline.copyWith(color: palette.muted)),
          Row(
            spacing: AppSpacing.md,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  spacing: 2,
                  children: [
                    Text(plan.name, style: AppTypography.title),
                    if (price != null) Text(price, style: AppTypography.caption.copyWith(color: palette.muted)),
                  ],
                ),
              ),
              PlanValidityPill(plan: plan, today: today),
              Icon(Icons.chevron_right_rounded, color: palette.muted),
            ],
          ),
        ],
      ),
    );
  }
}

class _Action {
  const _Action({
    required this.icon,
    required this.label,
    required this.onTap,
    this.caption,
    this.destructive = false,
    this.chevron = true,
  });

  final IconData icon;
  final String label;
  final String? caption;
  final VoidCallback? onTap;
  final bool destructive;
  final bool chevron;
}

/// Grouped list of the design (`.list`): one card, rows split by hairlines.
class _ActionList extends StatelessWidget {
  const _ActionList({required this.items});

  final List<Object> items;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          for (final (index, item) in items.indexed) ...[
            if (index > 0) Divider(height: 1, color: context.palette.line),
            if (item is _Action) _ActionTile(action: item) else item as Widget,
          ],
        ],
      ),
    );
  }
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({required this.action, this.trailing});

  final _Action action;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final color = action.destructive ? context.palette.expense : Theme.of(context).colorScheme.onSurface;
    return ListTile(
      minTileHeight: 56,
      contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
      leading: Icon(action.icon, color: color, size: 22),
      title: Text(action.label, style: AppTypography.label.copyWith(fontSize: 15, color: color)),
      subtitle: action.caption == null
          ? null
          : Text(action.caption!, style: AppTypography.caption.copyWith(color: AppColors.muted)),
      trailing: trailing ?? (action.chevron ? const Icon(Icons.chevron_right_rounded, color: AppColors.muted) : null),
      onTap: action.onTap,
    );
  }
}

/// Only this row rebuilds while the export runs.
class _ExportAction extends StatelessWidget {
  const _ExportAction();

  @override
  Widget build(BuildContext context) {
    final exporting = context.select((ExportDataCubit c) => c.state.submitting);
    return _ActionTile(
      action: _Action(
        icon: Icons.download_rounded,
        label: 'Exportar mis datos',
        caption: 'Archivo JSON con todo lo que guardamos',
        onTap: exporting ? null : () => context.read<ExportDataCubit>().export(),
      ),
      trailing: exporting
          ? const SizedBox.square(
              dimension: 20,
              child: CircularProgressIndicator(strokeWidth: 2, semanticsLabel: 'Preparando tus datos'),
            )
          : null,
    );
  }
}
