import 'package:flutter/material.dart';

import '../../../../app/theme/app_theme.dart';
import '../../../../app/theme/tokens.dart';
import '../../../../data/dtos/notification.dart';
import '../../../../shared/utils/dates.dart';
import '../../../../shared/widgets/app_card.dart';

/// Icon of each kind; unknown kinds get a neutral bell.
IconData notificationIcon(NotificationKind? kind) => switch (kind) {
  NotificationKind.familyInvitation => Icons.group_add_outlined,
  NotificationKind.budgetWarning => Icons.warning_amber_rounded,
  NotificationKind.budgetExceeded => Icons.error_outline_rounded,
  NotificationKind.scheduledExecuted => Icons.event_repeat_rounded,
  NotificationKind.planExpiring || NotificationKind.planExpired => Icons.workspace_premium_outlined,
  NotificationKind.passwordChanged => Icons.lock_outline_rounded,
  null => Icons.notifications_none_rounded,
};

/// «Hoy, 21:05», «Ayer, 08:10», «30 sept, 12:00» in the user's zone.
String notificationTime(DateTime createdAt, {required String? timezone, required DateTime today}) {
  final local = Dates.inUserZone(createdAt, timezone);
  return '${Dates.relative(local, today: today)}, ${Dates.time(local)}';
}

/// A row of the inbox: unread ones stand out (bold title, dot) and say so to
/// screen readers. Tapping opens it (and marks it as read).
class NotificationTile extends StatelessWidget {
  const NotificationTile({
    super.key,
    required this.notification,
    required this.time,
    required this.onTap,
    this.opensScreen = false,
  });

  final AppNotification notification;

  /// Already formatted ([notificationTime]).
  final String time;
  final VoidCallback onTap;

  /// Tapping leads to a screen (only for known kinds with valid ids).
  final bool opensScreen;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final unread = !notification.isRead;
    final hint = opensScreen ? 'Abrir' : (unread ? 'Marcar como leída' : null);
    return Semantics(
      button: opensScreen || unread,
      label: [unread ? 'No leída' : 'Leída', notification.title, notification.body, time].join('. '),
      onTap: onTap,
      onTapHint: hint,
      excludeSemantics: true,
      child: AppCard(
        outlined: !unread,
        padding: const EdgeInsets.all(AppSpacing.lg),
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: AppSizes.iconButton),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: AppSpacing.md,
            children: [
              IconTile(
                notificationIcon(notification.kind),
                color:
                    notification.kind == NotificationKind.budgetExceeded ||
                        notification.kind == NotificationKind.passwordChanged
                    ? palette.expense
                    : AppColors.lavender,
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  spacing: 2,
                  children: [
                    Text(
                      notification.title,
                      style: unread ? AppTypography.label.copyWith(fontWeight: FontWeight.w800) : AppTypography.label,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      notification.body,
                      style: AppTypography.caption.copyWith(color: palette.muted),
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(time, style: AppTypography.caption.copyWith(color: palette.muted, fontSize: 12)),
                  ],
                ),
              ),
              if (unread)
                Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.xs),
                  child: Container(
                    key: const ValueKey('notification-unread-dot'),
                    width: 10,
                    height: 10,
                    decoration: const BoxDecoration(color: AppColors.lavender, shape: BoxShape.circle),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
