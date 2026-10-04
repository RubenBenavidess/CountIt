import 'package:flutter/material.dart';

import '../../../../app/theme/app_theme.dart';
import '../../../../app/theme/tokens.dart';
import '../../../../data/dtos/family.dart';
import '../../../../shared/utils/dates.dart';
import '../../../../shared/widgets/app_card.dart';

/// «Vence el 11 oct 2026» in the user's timezone; null without a date.
String? expiryLabel(DateTime? expiresAt, String? timezone) =>
    expiresAt == null ? null : 'Vence el ${Dates.date(Dates.inUserZone(expiresAt, timezone))}';

/// One person of a shared wallet (HU-24 · COU-92): initials, name,
/// `@username`, their role and, for a pending invitation, when it expires.
/// [trailing] holds the owner's or the member's action (quitar, cancelar…).
class MemberTile extends StatelessWidget {
  const MemberTile({super.key, required this.member, required this.isMe, this.timezone, this.trailing});

  final FamilyMember member;

  /// The signed-in user's own row («Tú»).
  final bool isMe;
  final String? timezone;
  final Widget? trailing;

  static String initials(String name) {
    final words = name.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    if (words.isEmpty) return '?';
    final first = words.first.characters.first;
    final second = words.length > 1 ? words[1].characters.first : '';
    return (first + second).toUpperCase();
  }

  (String, BadgeTone) get _badge => switch (member.status) {
    FamilyStatus.owner => ('Dueño', BadgeTone.pro),
    FamilyStatus.accepted => ('Miembro', BadgeTone.ok),
    FamilyStatus.pending => ('Pendiente', BadgeTone.warn),
    _ => (member.status.label, BadgeTone.neutral),
  };

  @override
  Widget build(BuildContext context) {
    final muted = context.palette.muted;
    final (badge, tone) = _badge;
    final expiry = member.isPending ? expiryLabel(member.expiresAt, timezone) : null;
    final name = isMe ? '${member.name} (tú)' : member.name;
    final subtitle = ['@${member.username}', ?expiry].join(' · ');
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 64),
      child: Row(
        spacing: AppSpacing.md,
        children: [
          Expanded(
            child: Semantics(
              label: [name, badge, '@${member.username}', ?expiry].join(', '),
              excludeSemantics: true,
              child: Row(
                spacing: AppSpacing.md,
                children: [
                  CircleAvatar(
                    radius: 20,
                    backgroundColor: context.palette.surface2,
                    child: Text(initials(member.name), style: AppTypography.label.copyWith(color: AppColors.lavender)),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      spacing: 2,
                      children: [
                        Text(name, style: AppTypography.label, maxLines: 1, overflow: TextOverflow.ellipsis),
                        Text(
                          subtitle,
                          style: AppTypography.caption.copyWith(color: muted),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  AppBadge(badge, tone: tone),
                ],
              ),
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}
