import 'package:equatable/equatable.dart';

import 'profile.dart';

/// A plan as the informative plans screen and the superadmin picker show it.
class PlanOffer extends Equatable {
  const PlanOffer({required this.plan, required this.description});

  /// Id, name, monthly price and limits, in the shape of `get_my_profile().plan`.
  final UserPlan plan;

  /// `ref.plans.description`.
  final String description;

  int get planId => plan.planId;
  String get name => plan.name;

  @override
  List<Object?> get props => [plan, description];
}

/// The plan catalogue (COU-34, COU-124, COU-203).
///
/// The API exposes no catalogue: `ref.plans` and `ref.plan_details` are not
/// in the `api` schema, and `get_my_profile` only returns the caller's own
/// plan. This copy mirrors the backend seed (baseline migration of
/// CountIt-Backend-Dev) and is used for display and for the `p_plan_id` of
/// `admin_set_user_plan`; the backend still validates the id and applies the
/// real limits. Replace it with an API view when one exists.
abstract final class PlanCatalog {
  static const regularId = 1;

  static const all = <PlanOffer>[
    PlanOffer(
      description: 'Gestión financiera básica.',
      plan: UserPlan(
        planId: regularId,
        name: 'Regular',
        monthlyPriceCents: 0,
        limits: {
          'max_wallets': 3,
          'max_budgets_per_wallet': 4,
          'max_daily_transactions': 15,
          'max_scheduled_transactions': 3,
          'max_families': 0,
          'max_family_users': 0,
          'family_feature': 0,
          'advanced_statistics': 0,
          'wallet_projection': 0,
        },
      ),
    ),
    PlanOffer(
      description: 'Gestión financiera extendida con acceso a familias.',
      plan: UserPlan(
        planId: 2,
        name: 'Contador',
        monthlyPriceCents: 299,
        limits: {
          'max_wallets': 10,
          'max_budgets_per_wallet': 14,
          'max_daily_transactions': 40,
          'max_scheduled_transactions': 10,
          'max_families': 2,
          'max_family_users': 3,
          'family_feature': 1,
          'advanced_statistics': 1,
          'wallet_projection': 0,
        },
      ),
    ),
    PlanOffer(
      description: 'Gestión ilimitada con vistas analíticas.',
      plan: UserPlan(
        planId: 3,
        name: 'Contador Profesional',
        monthlyPriceCents: 499,
        limits: {
          'max_wallets': 999,
          'max_budgets_per_wallet': 999,
          'max_daily_transactions': 999,
          'max_scheduled_transactions': 50,
          'max_families': 10,
          'max_family_users': 999,
          'family_feature': 1,
          'advanced_statistics': 1,
          'wallet_projection': 1,
        },
      ),
    ),
  ];

  static PlanOffer? byId(int planId) {
    for (final offer in all) {
      if (offer.planId == planId) return offer;
    }
    return null;
  }

  /// `admin_list_users` returns the plan by name only.
  static PlanOffer? byName(String? name) {
    for (final offer in all) {
      if (offer.name == name) return offer;
    }
    return null;
  }
}
