import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router/app_router.dart';
import '../../../app/session/session_cubit.dart';
import '../../../app/theme/app_theme.dart';
import '../../../app/theme/tokens.dart';
import '../../../data/dtos/profile.dart';
import '../../../shared/widgets/app_card.dart';
import '../../../shared/widgets/app_layout.dart';
import 'widgets/role_guard.dart';

/// One entry of the admin area and who may see it.
class AdminSection {
  const AdminSection({
    required this.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.route,
    this.superadminOnly = false,
  });

  final String key;
  final IconData icon;
  final String title;
  final String subtitle;
  final String route;
  final bool superadminOnly;

  bool visibleTo(UserRole role) => superadminOnly ? role.isSuperadmin : role.canAdminister;
}

/// The sections of the admin area (COU-127), in display order.
const adminSections = <AdminSection>[
  AdminSection(
    key: 'admin-users',
    icon: Icons.people_alt_outlined,
    title: 'Usuarios',
    subtitle: 'Buscar usuarios, ver su rol y su plan',
    route: AppRoutes.adminUsers,
  ),
  AdminSection(
    key: 'admin-banks',
    icon: Icons.account_balance_outlined,
    title: 'Bancos',
    subtitle: 'Crear, editar, colores y activación',
    route: AppRoutes.adminBanks,
  ),
  AdminSection(
    key: 'admin-audit',
    icon: Icons.fact_check_outlined,
    title: 'Auditoría',
    subtitle: 'Acciones registradas, por entidad',
    route: AppRoutes.auditLog,
    superadminOnly: true,
  ),
];

/// Administration hub (HU-27, HU-28 · COU-127): reachable by admin and
/// superadmin only (router redirect + [RoleGuard]); each section is shown to
/// the roles that can use it. The API checks the role on every call.
class AdminPage extends StatelessWidget {
  const AdminPage({super.key});

  @override
  Widget build(BuildContext context) => RoleGuard(allows: RoleGuard.admin, builder: (context) => const _AdminView());
}

class _AdminView extends StatelessWidget {
  const _AdminView();

  @override
  Widget build(BuildContext context) {
    final role = context.select((SessionCubit c) => c.state.profile?.role ?? UserRole.user);
    final sections = adminSections.where((s) => s.visibleTo(role)).toList(growable: false);
    final muted = context.palette.muted;
    return Scaffold(
      appBar: const AppTopBar(title: 'Administración'),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(AppSpacing.screen, AppSpacing.md, AppSpacing.screen, AppSpacing.xxl),
        children: [
          Text(
            'Conectado como ${role.label.toLowerCase()}. Por privacidad, la administración no muestra '
            'las finanzas de los usuarios.',
            style: AppTypography.caption.copyWith(color: muted),
          ),
          const SizedBox(height: AppSpacing.lg),
          for (final section in sections) ...[
            AppCard(
              key: ValueKey(section.key),
              onTap: () => context.push(section.route),
              semanticLabel: '${section.title}. ${section.subtitle}',
              child: Row(
                spacing: AppSpacing.md,
                children: [
                  IconTile(section.icon),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      spacing: 2,
                      children: [
                        Text(section.title, style: AppTypography.label.copyWith(fontSize: 15)),
                        Text(section.subtitle, style: AppTypography.caption.copyWith(color: muted)),
                      ],
                    ),
                  ),
                  Icon(Icons.chevron_right_rounded, color: muted),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.md),
          ],
        ],
      ),
    );
  }
}
