import 'package:equatable/equatable.dart';

/// Roles of `ref.roles` (`get_my_profile().role`).
enum UserRole {
  user,
  admin,
  superadmin;

  static UserRole parse(String? value) =>
      UserRole.values.firstWhere((r) => r.name == value, orElse: () => UserRole.user);

  /// Admin screens (banks, users) are for admin and superadmin (HU-27, HU-28).
  bool get canAdminister => this != UserRole.user;
}

/// Feature flags of `ref.plan_details` (1 = included, 0 = not), as
/// `get_my_profile().plan.limits` sends them.
abstract final class PlanFeatures {
  /// Shared wallets (HU-21…HU-24).
  static const families = 'family_feature';

  /// Distribution by budget in the statistics (HU-26): Contador and Contador Profesional.
  static const advancedStatistics = 'advanced_statistics';

  /// Balance projection (HU-25): Contador Profesional only.
  static const walletProjection = 'wallet_projection';
}

/// Active plan with its limits (`ref.plan_details`, 999 = unlimited).
class UserPlan extends Equatable {
  const UserPlan({required this.planId, required this.name, required this.limits, this.validUntil});

  factory UserPlan.fromJson(Map<String, dynamic> json) => UserPlan(
    planId: (json['plan_id'] as num).toInt(),
    name: json['name'] as String,
    validUntil: json['valid_until'] == null ? null : DateTime.parse(json['valid_until'] as String),
    limits: {
      for (final entry in ((json['limits'] as Map?) ?? const {}).entries)
        entry.key as String: (entry.value as num).toInt(),
    },
  );

  static const unlimited = 999;

  final int planId;
  final String name;
  final DateTime? validUntil;
  final Map<String, int> limits;

  /// Feature flags (`family_feature`, `advanced_statistics`, `wallet_projection`) are 1/0.
  bool hasFeature(String feature) => (limits[feature] ?? 0) > 0;

  /// Quota value or null when unlimited.
  int? quota(String limitation) {
    final value = limits[limitation];
    return value == null || value >= unlimited ? null : value;
  }

  @override
  List<Object?> get props => [planId, name, validUntil, limits];
}

/// Result of `api.get_my_profile()`.
class Profile extends Equatable {
  const Profile({
    required this.userId,
    required this.username,
    required this.email,
    required this.role,
    required this.timezone,
    this.firstName,
    this.lastName,
    this.plan,
  });

  factory Profile.fromJson(Map<String, dynamic> json) => Profile(
    userId: json['user_id'] as String,
    username: json['username'] as String,
    email: (json['email'] as String?) ?? '',
    firstName: json['first_name'] as String?,
    lastName: json['last_name'] as String?,
    timezone: (json['timezone'] as String?) ?? 'America/Guayaquil',
    role: UserRole.parse(json['role'] as String?),
    plan: json['plan'] is Map ? UserPlan.fromJson(Map<String, dynamic>.from(json['plan'] as Map)) : null,
  );

  final String userId;
  final String username;
  final String email;
  final String? firstName;
  final String? lastName;
  final String timezone;
  final UserRole role;
  final UserPlan? plan;

  String get displayName {
    final full = [firstName, lastName].whereType<String>().where((s) => s.isNotEmpty).join(' ');
    return full.isEmpty ? username : full;
  }

  /// Local gating hint (COU-169, COU-172): false only when the known plan
  /// lacks [feature]. Without a plan loaded the screen asks the API, which
  /// always decides (403 `feature_not_in_plan`).
  bool allows(String feature) => plan?.hasFeature(feature) ?? true;

  @override
  List<Object?> get props => [userId, username, email, firstName, lastName, timezone, role, plan];
}
