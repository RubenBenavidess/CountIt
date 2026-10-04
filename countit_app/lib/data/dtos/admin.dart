import 'package:equatable/equatable.dart';

import 'json_parsing.dart';
import 'profile.dart';

/// One page of an offset-paginated admin list.
class Paged<T> extends Equatable {
  const Paged(this.items, {required this.hasMore});

  final List<T> items;

  /// The server had at least one more row after this page.
  final bool hasMore;

  @override
  List<Object?> get props => [items, hasMore];
}

/// A row of `api.admin_list_users` (HU-28): identity, role and active plan.
/// No financial data: admins never see other users' finances (S-12).
class AdminUser extends Equatable {
  const AdminUser({
    required this.userId,
    required this.username,
    required this.email,
    required this.role,
    this.firstName,
    this.lastName,
    this.planName,
    this.planValidUntil,
    this.createdAt,
  });

  factory AdminUser.fromJson(Map<String, dynamic> json) => AdminUser(
    userId: json['user_id'] as String,
    username: (json['username'] as String?) ?? '',
    email: (json['email'] as String?) ?? '',
    firstName: json['first_name'] as String?,
    lastName: json['last_name'] as String?,
    role: UserRole.parse(json['role'] as String?),
    planName: json['plan'] as String?,
    planValidUntil: _day(json['plan_valid_until']),
    createdAt: parseTimestamp(json['created_at']),
  );

  static DateTime? _day(Object? value) {
    if (value is! String) return null;
    final parsed = DateTime.tryParse(value);
    return parsed == null ? null : DateTime(parsed.year, parsed.month, parsed.day);
  }

  final String userId;
  final String username;
  final String email;
  final String? firstName;
  final String? lastName;
  final UserRole role;

  /// Name of the active plan; null when the user has none.
  final String? planName;
  final DateTime? planValidUntil;
  final DateTime? createdAt;

  String get displayName {
    final full = [firstName, lastName].whereType<String>().where((s) => s.trim().isNotEmpty).join(' ');
    return full.isEmpty ? '@$username' : full;
  }

  AdminUser copyWith({UserRole? role, String? planName, DateTime? planValidUntil}) => AdminUser(
    userId: userId,
    username: username,
    email: email,
    firstName: firstName,
    lastName: lastName,
    role: role ?? this.role,
    planName: planName ?? this.planName,
    planValidUntil: planValidUntil ?? this.planValidUntil,
    createdAt: createdAt,
  );

  @override
  List<Object?> get props => [userId, username, email, firstName, lastName, role, planName, planValidUntil, createdAt];
}

/// Result of `api.admin_set_user_plan`: the new plan and what the downgrade
/// enforced right away (`private.enforce_plan_quotas`).
class PlanAssignment extends Equatable {
  const PlanAssignment({
    required this.planId,
    required this.planName,
    required this.validUntil,
    this.membershipsEnded = 0,
    this.memberRulesEnded = 0,
    this.rulesPaused = 0,
  });

  factory PlanAssignment.fromJson(Map<String, dynamic> json) {
    final enforced = json['enforced'] is Map
        ? Map<String, dynamic>.from(json['enforced'] as Map)
        : const <String, dynamic>{};
    int count(String key) => (enforced[key] as num?)?.toInt() ?? 0;
    final until = DateTime.parse(json['valid_until'] as String);
    return PlanAssignment(
      planId: (json['plan_id'] as num).toInt(),
      planName: json['plan'] as String,
      validUntil: DateTime(until.year, until.month, until.day),
      membershipsEnded: count('memberships_ended'),
      memberRulesEnded: count('member_rules_ended'),
      rulesPaused: count('rules_paused'),
    );
  }

  final int planId;
  final String planName;
  final DateTime validUntil;
  final int membershipsEnded;
  final int memberRulesEnded;
  final int rulesPaused;

  bool get enforcedAnything => membershipsEnded + memberRulesEnded + rulesPaused > 0;

  @override
  List<Object?> get props => [planId, planName, validUntil, membershipsEnded, memberRulesEnded, rulesPaused];
}
