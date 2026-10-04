import '../../app/errors/app_failure.dart';
import '../dtos/plan_offer.dart';
import '../remote/api_client.dart';

/// Plan catalogue (`api.v_plans`, contract 1.2): the plans screen, the
/// description of «Mi plan» and the superadmin plan picker.
abstract interface class PlanRepository {
  /// Plans ordered by `plan_id`. Served from memory after the first answer;
  /// [refresh] asks the API again. A failed refresh falls back to the last
  /// catalogue; with none cached the [AppFailure] propagates.
  Future<List<PlanOffer>> list({bool refresh = false});
}

class SupabasePlanRepository implements PlanRepository {
  SupabasePlanRepository(this._api);

  final ApiClient _api;
  List<PlanOffer>? _cache;
  Future<List<PlanOffer>>? _inFlight;

  @override
  Future<List<PlanOffer>> list({bool refresh = false}) {
    final cached = _cache;
    if (cached != null && !refresh) return Future.value(cached);
    // Screens opened together share one request.
    return _inFlight ??= _fetch().whenComplete(() => _inFlight = null);
  }

  Future<List<PlanOffer>> _fetch() async {
    try {
      final rows = await _api.select('v_plans', query: (q) => q.order('plan_id', ascending: true));
      return _cache = List.unmodifiable(rows.map(PlanOffer.fromJson));
    } on AppFailure {
      final cached = _cache;
      if (cached != null) return cached;
      rethrow;
    }
  }
}
