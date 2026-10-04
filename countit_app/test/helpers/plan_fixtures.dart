import 'package:countit_app/app/errors/app_failure.dart';
import 'package:countit_app/data/dtos/plan_offer.dart';
import 'package:countit_app/data/repositories/plan_repository.dart';

/// Rows of `api.v_plans` as the backend seed has them.
const planRowsJson = <Map<String, dynamic>>[
  {
    'plan_id': 1,
    'name': 'Regular',
    'description': 'Gestión financiera básica.',
    'monthly_price': 0,
    'limits': {
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
  },
  {
    'plan_id': 2,
    'name': 'Contador',
    'description': 'Gestión financiera extendida con acceso a familias.',
    'monthly_price': 2.99,
    'limits': {
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
  },
  {
    'plan_id': 3,
    'name': 'Contador Profesional',
    'description': 'Gestión ilimitada con vistas analíticas.',
    'monthly_price': 4.99,
    'limits': {
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
  },
];

final List<PlanOffer> planOffers = planRowsJson.map(PlanOffer.fromJson).toList(growable: false);

PlanOffer planOffer(int planId) => planOffers.firstWhere((offer) => offer.planId == planId);

/// In-memory catalogue; [failure] makes every call fail.
class FakePlanRepository implements PlanRepository {
  FakePlanRepository({List<PlanOffer>? offers, this.failure}) : offers = offers ?? planOffers;

  List<PlanOffer> offers;
  AppFailure? failure;
  int calls = 0;

  @override
  Future<List<PlanOffer>> list({bool refresh = false}) async {
    calls++;
    final error = failure;
    if (error != null) throw error;
    return offers;
  }
}
