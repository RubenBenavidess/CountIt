import '../../app/errors/app_failure.dart';
import '../../app/errors/error_mapper.dart';
import '../dtos/scheduled_transaction.dart';
import '../remote/api_client.dart';

/// Scheduled rules of a wallet (HU-16, HU-20 · COU-20). Reads come from
/// `api.v_scheduled_transactions`, writes are RPCs; every write returns the
/// rule as the API left it (without the names the view joins).
abstract interface class ScheduledTransactionRepository {
  /// Active rules of [walletId] (running and paused), soonest first.
  Future<List<ScheduledTransaction>> listByWallet(int walletId);

  /// The caller's own active rules in every wallet, for the plan quota.
  Future<ScheduledUsage> usageOf(String userId);

  /// One rule; throws an [AppFailure] `scheduled_transaction_not_found` (404)
  /// when it does not exist, is not visible, ended or was deleted.
  Future<ScheduledTransaction> getById(int scheduledTransactionId);

  /// `create_scheduled_transaction` in [walletId] (start after today).
  Future<ScheduledTransaction> create(int walletId, ScheduledTransactionInput input);

  /// `update_scheduled_transaction` (replacement; the start date never changes).
  Future<ScheduledTransaction> update(int scheduledTransactionId, ScheduledTransactionInput input);

  /// `set_scheduled_transaction_paused`: resuming needs a free slot in the
  /// author's plan (409 `scheduled_transaction_limit_exceeded`) and may end a
  /// rule with nothing left to run (`isActive == false`).
  Future<ScheduledTransaction> setPaused(int scheduledTransactionId, {required bool paused});

  /// `delete_scheduled_transaction` 🔒: [onReauth] asks for the password on
  /// `403 reauth_required`. Generated transactions are kept.
  Future<void> delete(int scheduledTransactionId, {ReauthPrompt? onReauth});
}

class SupabaseScheduledTransactionRepository implements ScheduledTransactionRepository {
  SupabaseScheduledTransactionRepository(this._api);

  final ApiClient _api;

  static const view = 'v_scheduled_transactions';

  /// Same message and key as the API's 404 so the UI handles both alike.
  static const notFound = AppFailure(
    kind: FailureKind.notFound,
    message: 'Transacción programada no encontrada',
    key: 'scheduled_transaction_not_found',
    status: 404,
  );

  @override
  Future<List<ScheduledTransaction>> listByWallet(int walletId) async {
    final rows = await _api.select(
      view,
      query: (q) => q
          .eq('wallet_id', walletId)
          .order('next_run_date', ascending: true)
          .order('scheduled_transaction_id', ascending: true),
    );
    return rows.map(ScheduledTransaction.fromJson).toList(growable: false);
  }

  @override
  Future<ScheduledUsage> usageOf(String userId) async {
    // Two narrow columns: only counted, never shown.
    final rows = await _api.select(
      view,
      columns: 'scheduled_transaction_id,is_paused',
      query: (q) => q.eq('user_id', userId),
    );
    final paused = rows.where((row) => row['is_paused'] == true).length;
    return ScheduledUsage(total: rows.length, running: rows.length - paused);
  }

  @override
  Future<ScheduledTransaction> getById(int scheduledTransactionId) async {
    final rows = await _api.select(
      view,
      query: (q) => q.eq('scheduled_transaction_id', scheduledTransactionId).limit(1),
    );
    if (rows.isEmpty) throw notFound;
    return ScheduledTransaction.fromJson(rows.first);
  }

  @override
  Future<ScheduledTransaction> create(int walletId, ScheduledTransactionInput input) =>
      _rule('create_scheduled_transaction', {'p_wallet_id': walletId, ...input.toCreateParams()});

  @override
  Future<ScheduledTransaction> update(int scheduledTransactionId, ScheduledTransactionInput input) =>
      _rule('update_scheduled_transaction', {'p_id': scheduledTransactionId, ...input.toUpdateParams()});

  @override
  Future<ScheduledTransaction> setPaused(int scheduledTransactionId, {required bool paused}) =>
      _rule('set_scheduled_transaction_paused', {'p_id': scheduledTransactionId, 'p_paused': paused});

  @override
  Future<void> delete(int scheduledTransactionId, {ReauthPrompt? onReauth}) =>
      _api.rpc<dynamic>('delete_scheduled_transaction', params: {'p_id': scheduledTransactionId}, onReauth: onReauth);

  Future<ScheduledTransaction> _rule(String function, Map<String, dynamic> params) async {
    final json = await _api.rpc<dynamic>(function, params: params);
    if (json is! Map) {
      throw const AppFailure(kind: FailureKind.server, message: ErrorMapper.genericMessage);
    }
    return ScheduledTransaction.fromJson(Map<String, dynamic>.from(json));
  }
}
