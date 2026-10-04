import '../../app/errors/app_failure.dart';
import '../../app/errors/error_mapper.dart';
import '../../shared/utils/dates.dart';
import '../dtos/projection.dart';
import '../dtos/statistics.dart';
import '../remote/api_client.dart';

/// «Análisis» of the API (HU-25/HU-26 · COU-22, COU-24): figures the database computes for
/// one readable wallet. The app never sums movements itself for these.
abstract interface class AnalysisRepository {
  /// `get_wallet_statistics(p_wallet_id, p_range)`: series, totals, growth
  /// and, with `advanced_statistics`, the distribution by budget. Throws an
  /// [AppFailure] `wallet_not_found` (404) for a wallet the caller cannot read.
  Future<WalletStatistics> walletStatistics(int walletId, StatisticsRange range);

  /// `get_wallet_projection(p_wallet_id, p_until?)` (plan feature
  /// `wallet_projection`): 403 `feature_not_in_plan` without it, 400
  /// `invalid_date_range` for a date not after today, 404 `wallet_not_found`.
  /// Without [until] the API picks the horizon.
  Future<WalletProjection> walletProjection(int walletId, {DateTime? until});
}

class SupabaseAnalysisRepository implements AnalysisRepository {
  SupabaseAnalysisRepository(this._api);

  final ApiClient _api;

  @override
  Future<WalletStatistics> walletStatistics(int walletId, StatisticsRange range) async {
    final json = await _api.rpc<dynamic>(
      'get_wallet_statistics',
      params: {'p_wallet_id': walletId, 'p_range': range.apiValue},
    );
    return _parse(json, WalletStatistics.fromJson);
  }

  @override
  Future<WalletProjection> walletProjection(int walletId, {DateTime? until}) async {
    final json = await _api.rpc<dynamic>(
      'get_wallet_projection',
      params: {'p_wallet_id': walletId, if (until != null) 'p_until': Dates.toApi(until)},
    );
    return _parse(json, WalletProjection.fromJson);
  }

  static const _unexpected = AppFailure(kind: FailureKind.server, message: ErrorMapper.genericMessage);

  /// An answer that is not the documented object is a server failure, never a crash.
  static T _parse<T>(Object? json, T Function(Map<String, dynamic>) fromJson) {
    if (json is! Map) throw _unexpected;
    try {
      return fromJson(Map<String, dynamic>.from(json));
    } on TypeError {
      throw _unexpected;
    } on FormatException {
      throw _unexpected;
    }
  }
}
