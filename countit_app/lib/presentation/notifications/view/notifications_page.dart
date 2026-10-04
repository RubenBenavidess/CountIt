import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router/notification_routes.dart';
import '../../../app/session/session_cubit.dart';
import '../../../app/theme/tokens.dart';
import '../../../data/dtos/notification.dart';
import '../../../shared/utils/dates.dart';
import '../../../shared/widgets/app_button.dart';
import '../../../shared/widgets/app_feedback.dart';
import '../../../shared/widgets/app_layout.dart';
import '../../../shared/widgets/load_more_listener.dart';
import '../cubit/notifications_cubit.dart';
import 'widgets/notification_tile.dart';
import 'widgets/push_permission_card.dart';

/// «Notificaciones» (HU-31 · COU-108, COU-181, COU-180): the inbox, newest
/// first, paged while scrolling and live with Realtime. Opening one marks it
/// as read and, when its kind and ids are valid, opens its screen
/// ([NotificationRoutes]); «Marcar todas» reads every unread one. Uses the
/// app-wide [NotificationsCubit].
class NotificationsPage extends StatelessWidget {
  const NotificationsPage({super.key});

  void _open(BuildContext context, AppNotification notification) {
    unawaited(context.read<NotificationsCubit>().markRead(notification));
    final location = NotificationRoutes.locationFor(notification.kind, notification.data);
    if (location != null) unawaited(context.push(location));
  }

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<NotificationsCubit>();
    return BlocListener<NotificationsCubit, NotificationsState>(
      listenWhen: (previous, current) =>
          current.actionFailure != null && previous.actionFailure != current.actionFailure,
      listener: (context, state) => showFailureSnackBar(context, state.actionFailure!.failure),
      child: Scaffold(
        appBar: const AppTopBar(title: 'Notificaciones', showBack: false, actions: [_MarkAllButton()]),
        body: RefreshIndicator(
          onRefresh: cubit.load,
          child: LoadMoreListener(
            onLoadMore: () => unawaited(cubit.loadMore()),
            child: CustomScrollView(
              key: const PageStorageKey('notifications'),
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                const SliverPadding(
                  padding: EdgeInsets.fromLTRB(AppSpacing.screen, AppSpacing.sm, AppSpacing.screen, 0),
                  sliver: SliverToBoxAdapter(child: PushPermissionCard()),
                ),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.screen,
                    AppSpacing.sm,
                    AppSpacing.screen,
                    AppSpacing.xxl,
                  ),
                  sliver: BlocBuilder<NotificationsCubit, NotificationsState>(
                    // The badge count alone does not rebuild the list.
                    buildWhen: (previous, current) =>
                        previous.items != current.items ||
                        previous.status != current.status ||
                        previous.hasMore != current.hasMore ||
                        previous.loadingMore != current.loadingMore ||
                        previous.moreFailure != current.moreFailure,
                    builder: (context, state) => _body(context, state),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _body(BuildContext context, NotificationsState state) {
    final cubit = context.read<NotificationsCubit>();
    if (state.isFirstLoad) {
      return SliverFillRemaining(
        hasScrollBody: false,
        child: state.status == InboxStatus.failure
            ? ErrorView(message: state.failure!.message, onRetry: cubit.load)
            : const LoadingView(message: 'Cargando notificaciones'),
      );
    }
    if (state.items.isEmpty) {
      return const SliverFillRemaining(
        hasScrollBody: false,
        child: EmptyState(
          icon: Icons.notifications_none_rounded,
          title: 'No tienes notificaciones',
          message:
              'Aquí verás invitaciones, avisos de tus presupuestos, pagos programados registrados y '
              'novedades de tu plan y de tu cuenta.',
        ),
      );
    }
    final profile = context.read<SessionCubit>().state.profile;
    final timezone = profile?.timezone;
    final today = Dates.userToday(timezone);
    final items = state.items;
    final footer = state.hasMore || state.moreFailure != null;
    return SliverMainAxisGroup(
      slivers: [
        if (state.status == InboxStatus.failure)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.md),
              child: NoteCard(
                icon: Icons.cloud_off_outlined,
                message: state.failure!.message,
                action: AppButton(
                  label: 'Reintentar',
                  variant: AppButtonVariant.ghost,
                  expand: false,
                  onPressed: cubit.load,
                ),
              ),
            ),
          ),
        SliverList.separated(
          itemCount: items.length + (footer ? 1 : 0),
          separatorBuilder: (context, index) => const SizedBox(height: AppSpacing.md),
          itemBuilder: (context, index) {
            if (index == items.length) {
              return _Footer(failed: state.moreFailure != null, onRetry: () => cubit.loadMore(retry: true));
            }
            final notification = items[index];
            return NotificationTile(
              opensScreen: NotificationRoutes.locationFor(notification.kind, notification.data) != null,
              key: ValueKey('notification-${notification.id}'),
              notification: notification,
              time: notificationTime(notification.createdAt, timezone: timezone, today: today),
              onTap: () => _open(context, notification),
            );
          },
        ),
      ],
    );
  }
}

/// «Marcar todas como leídas»: only while something is unread.
class _MarkAllButton extends StatelessWidget {
  const _MarkAllButton();

  @override
  Widget build(BuildContext context) {
    final (unread, busy) = context.select(
      (NotificationsCubit c) => (c.state.unread > 0 || c.state.items.any((n) => !n.isRead), c.state.markingAll),
    );
    if (!unread) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(right: AppSpacing.sm),
      child: IconButton(
        key: const ValueKey('notifications-mark-all'),
        tooltip: 'Marcar todas como leídas',
        constraints: const BoxConstraints.tightFor(width: 48, height: 48),
        onPressed: busy ? null : () => unawaited(context.read<NotificationsCubit>().markAllRead()),
        icon: const Icon(Icons.done_all_rounded),
      ),
    );
  }
}

/// End of the loaded pages: a spinner while the next one loads, or a retry.
class _Footer extends StatelessWidget {
  const _Footer({required this.failed, required this.onRetry});

  final bool failed;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Padding(
      key: const ValueKey('notifications-footer'),
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
      child: Center(
        child: failed
            ? Column(
                spacing: AppSpacing.sm,
                children: [
                  const Text('No pudimos cargar más notificaciones.', style: AppTypography.caption),
                  AppButton(label: 'Reintentar', variant: AppButtonVariant.ghost, expand: false, onPressed: onRetry),
                ],
              )
            : Semantics(
                label: 'Cargando más notificaciones',
                child: const SizedBox.square(dimension: 24, child: CircularProgressIndicator(strokeWidth: 2.5)),
              ),
      ),
    );
  }
}
