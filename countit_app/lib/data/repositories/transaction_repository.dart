import '../../app/errors/app_failure.dart';
import '../../shared/utils/dates.dart';
import '../dtos/transaction.dart';
import '../remote/api_client.dart';

/// Transactions of a wallet (HU-15, HU-17..HU-19). Reads come from
/// `api.v_transactions`, writes are RPCs.
abstract interface class TransactionRepository {
  /// Rows per page of the wallet list.
  static const pageSize = 30;

  /// One page of [walletId]'s transactions, newest first
  /// (`date.desc, transaction_id.desc`), starting [after] the previous page.
  Future<TransactionPage> list(int walletId, {TransactionCursor? after, int limit = pageSize});

  /// One transaction; throws an [AppFailure] `transaction_not_found` (404)
  /// when it does not exist, is not visible or was deleted.
  Future<Transaction> getById(int transactionId);

  /// `create_transaction` in [walletId]: returns the new transaction id.
  Future<int> create(int walletId, TransactionInput input);

  /// `update_transaction` (replacement: every field of [input] is sent).
  Future<void> update(int transactionId, TransactionInput input);

  /// `delete_transaction` 🔒: [onReauth] asks for the password on `403 reauth_required`.
  Future<void> delete(int transactionId, {ReauthPrompt? onReauth});
}

class SupabaseTransactionRepository implements TransactionRepository {
  SupabaseTransactionRepository(this._api);

  final ApiClient _api;

  static const view = 'v_transactions';

  /// Same message and key as the API's 404 so the UI handles both alike.
  static const notFound = AppFailure(
    kind: FailureKind.notFound,
    message: 'Transacción no encontrada',
    key: 'transaction_not_found',
    status: 404,
  );

  /// PostgREST `or` filter for the rows strictly after [cursor] in the list
  /// order: an earlier day, or the same day with a smaller id.
  static String keysetFilter(TransactionCursor cursor) {
    final day = Dates.toApi(cursor.date);
    return 'date.lt.$day,and(date.eq.$day,transaction_id.lt.${cursor.transactionId})';
  }

  @override
  Future<TransactionPage> list(
    int walletId, {
    TransactionCursor? after,
    int limit = TransactionRepository.pageSize,
  }) async {
    final rows = await _api.select(
      view,
      query: (q) {
        var filtered = q.eq('wallet_id', walletId);
        if (after != null) filtered = filtered.or(keysetFilter(after));
        // One extra row tells whether another page exists without a count query.
        return filtered.order('date', ascending: false).order('transaction_id', ascending: false).limit(limit + 1);
      },
    );
    final items = rows.take(limit).map(Transaction.fromJson).toList(growable: false);
    final hasMore = rows.length > limit && items.isNotEmpty;
    return TransactionPage(items, next: hasMore ? TransactionCursor.after(items.last) : null);
  }

  @override
  Future<Transaction> getById(int transactionId) async {
    final rows = await _api.select(view, query: (q) => q.eq('transaction_id', transactionId).limit(1));
    if (rows.isEmpty) throw notFound;
    return Transaction.fromJson(rows.first);
  }

  @override
  Future<int> create(int walletId, TransactionInput input) async {
    final json = await _api.rpc<dynamic>('create_transaction', params: {'p_wallet_id': walletId, ...input.toParams()});
    return json is Map ? ((json['transaction_id'] as num?)?.toInt() ?? 0) : 0;
  }

  @override
  Future<void> update(int transactionId, TransactionInput input) =>
      _api.rpc<dynamic>('update_transaction', params: {'p_transaction_id': transactionId, ...input.toParams()});

  @override
  Future<void> delete(int transactionId, {ReauthPrompt? onReauth}) =>
      _api.rpc<dynamic>('delete_transaction', params: {'p_transaction_id': transactionId}, onReauth: onReauth);
}
