import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router/app_router.dart';
import '../../../app/theme/app_theme.dart';
import '../../../app/theme/tokens.dart';
import '../../../data/dtos/admin.dart';
import '../../../data/repositories/admin_repository.dart';
import '../../../shared/utils/dates.dart';
import '../../../shared/widgets/app_button.dart';
import '../../../shared/widgets/app_card.dart';
import '../../../shared/widgets/app_feedback.dart';
import '../../../shared/widgets/app_fields.dart';
import '../../../shared/widgets/app_layout.dart';
import '../../../shared/widgets/load_more_listener.dart';
import '../cubit/admin_failures.dart';
import '../cubit/admin_users_cubit.dart';
import 'widgets/role_guard.dart';

/// Users for administration (HU-28 · COU-201): search by username or e-mail
/// (debounced), lazy pages and a detail per user.
class AdminUsersPage extends StatelessWidget {
  const AdminUsersPage({super.key});

  @override
  Widget build(BuildContext context) => RoleGuard(
    allows: RoleGuard.admin,
    builder: (context) => BlocProvider(
      create: (context) => AdminUsersCubit(context.read<AdminRepository>())..load(),
      child: const _AdminUsersView(),
    ),
  );
}

class _AdminUsersView extends StatelessWidget {
  const _AdminUsersView();

  Future<void> _open(BuildContext context, AdminUser user) async {
    final cubit = context.read<AdminUsersCubit>();
    final updated = await context.push<AdminUser>(AppRoutes.adminUser(user.userId), extra: user);
    if (updated != null && !cubit.isClosed) cubit.replace(updated);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const AppTopBar(title: 'Usuarios'),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(AppSpacing.screen, AppSpacing.sm, AppSpacing.screen, AppSpacing.md),
            child: AppTextField(
              key: const ValueKey('admin-users-search'),
              label: 'Buscar',
              hint: 'Usuario o correo',
              prefix: const Icon(Icons.search_rounded),
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.search,
              maxLength: 100,
              onChanged: context.read<AdminUsersCubit>().search,
            ),
          ),
          Expanded(
            child: BlocBuilder<AdminUsersCubit, AdminUsersState>(
              builder: (context, state) {
                final cubit = context.read<AdminUsersCubit>();
                if (state.isFirstLoad) {
                  if (state.status == AdminListStatus.failure) {
                    return ErrorView.failure(adminFailure(state.failure!), onRetry: cubit.load);
                  }
                  return const LoadingView(message: 'Cargando usuarios');
                }
                if (state.items.isEmpty) {
                  return EmptyState(
                    icon: Icons.person_search_outlined,
                    title: 'Sin resultados',
                    message: state.search.isEmpty
                        ? 'Todavía no hay usuarios.'
                        : 'Ningún usuario o correo contiene «${state.search}».',
                  );
                }
                final extra = state.hasMore || state.moreFailure != null ? 1 : 0;
                return RefreshIndicator(
                  onRefresh: cubit.load,
                  child: LoadMoreListener(
                    onLoadMore: cubit.loadMore,
                    child: ListView.separated(
                      key: const PageStorageKey('admin-users'),
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.fromLTRB(AppSpacing.screen, 0, AppSpacing.screen, AppSpacing.xxl),
                      itemCount: state.items.length + extra,
                      separatorBuilder: (context, index) => const SizedBox(height: AppSpacing.sm),
                      itemBuilder: (context, index) {
                        if (index == state.items.length) return _MoreRow(state: state);
                        final user = state.items[index];
                        return AdminUserTile(
                          key: ValueKey('admin-user-${user.userId}'),
                          user: user,
                          onTap: () => unawaited(_open(context, user)),
                        );
                      },
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// End of the list: spinner while the next page loads, or retry after a failure.
class _MoreRow extends StatelessWidget {
  const _MoreRow({required this.state});

  final AdminUsersState state;

  @override
  Widget build(BuildContext context) {
    final failure = state.moreFailure;
    if (failure != null) {
      return NoteCard(
        icon: Icons.cloud_off_outlined,
        message: adminFailure(failure).message,
        action: AppButton(
          label: 'Reintentar',
          small: true,
          variant: AppButtonVariant.ghost,
          onPressed: () => context.read<AdminUsersCubit>().loadMore(retry: true),
        ),
      );
    }
    return const Padding(
      padding: EdgeInsets.all(AppSpacing.lg),
      child: Center(
        child: SizedBox.square(
          dimension: 24,
          child: CircularProgressIndicator(strokeWidth: 2.5, semanticsLabel: 'Cargando más usuarios'),
        ),
      ),
    );
  }
}

/// A user row: name, @username · e-mail, role and plan.
class AdminUserTile extends StatelessWidget {
  const AdminUserTile({super.key, required this.user, required this.onTap});

  final AdminUser user;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final muted = context.palette.muted;
    final plan = user.planName ?? 'Sin plan';
    final until = user.planValidUntil;
    return AppCard(
      onTap: onTap,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.md),
      semanticLabel:
          '${user.displayName}, @${user.username}, ${user.email}. ${user.role.label}. Plan $plan'
          '${until == null ? '' : ', vence el ${Dates.date(until)}'}',
      child: ExcludeSemantics(
        child: Row(
          spacing: AppSpacing.md,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: 2,
                children: [
                  Text(user.displayName, style: AppTypography.label, maxLines: 1, overflow: TextOverflow.ellipsis),
                  Text(
                    '@${user.username} · ${user.email}',
                    style: AppTypography.caption.copyWith(color: muted),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(plan, style: AppTypography.caption.copyWith(color: muted)),
                ],
              ),
            ),
            if (user.role.canAdminister)
              AppBadge(user.role.label, tone: user.role.isSuperadmin ? BadgeTone.pro : BadgeTone.neutral),
            Icon(Icons.chevron_right_rounded, color: muted),
          ],
        ),
      ),
    );
  }
}
