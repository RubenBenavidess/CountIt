import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../app/errors/app_failure.dart';
import '../../../data/dtos/plan_offer.dart';
import '../../../data/repositories/plan_repository.dart';
import '../../../shared/state/load_state.dart';

/// The plan catalogue for a screen (`v_plans`); the repository caches it.
class PlanCatalogCubit extends Cubit<LoadState<List<PlanOffer>>> {
  PlanCatalogCubit(this._plans) : super(const LoadState.initial());

  final PlanRepository _plans;

  /// First load and «Reintentar»; [refresh] bypasses the in-memory catalogue.
  Future<void> load({bool refresh = false}) async {
    emit(state.reloading());
    try {
      final offers = await _plans.list(refresh: refresh);
      if (!isClosed) emit(LoadState.success(offers));
    } on AppFailure catch (failure) {
      if (!isClosed) emit(LoadState.failure(failure, previous: state.data));
    }
  }

  /// The offer with [planId] once loaded, else null.
  PlanOffer? byId(int? planId) => offerById(state.data, planId);
}

/// The offer with [planId] in [offers], or null.
PlanOffer? offerById(List<PlanOffer>? offers, int? planId) {
  if (offers == null || planId == null) return null;
  for (final offer in offers) {
    if (offer.planId == planId) return offer;
  }
  return null;
}
