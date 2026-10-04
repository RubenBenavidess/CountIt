import 'package:equatable/equatable.dart';

import 'profile.dart';

/// A row of `api.v_plans` (contract 1.2): what the plans screen and the
/// superadmin picker show.
class PlanOffer extends Equatable {
  const PlanOffer({required this.plan, required this.description});

  /// `limits` has the shape of `get_my_profile().plan.limits`, so the row
  /// parses as a [UserPlan] (without `valid_until`).
  factory PlanOffer.fromJson(Map<String, dynamic> json) =>
      PlanOffer(plan: UserPlan.fromJson(json), description: (json['description'] as String?)?.trim() ?? '');

  /// Id, name, monthly price and limits.
  final UserPlan plan;

  /// `ref.plans.description`; empty when the catalogue has none.
  final String description;

  int get planId => plan.planId;
  String get name => plan.name;

  @override
  List<Object?> get props => [plan, description];
}
