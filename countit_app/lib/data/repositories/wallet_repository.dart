import '../../app/errors/app_failure.dart';
import '../dtos/wallet.dart';
import '../remote/api_client.dart';

/// Wallets (HU-07..HU-10). Reads come from `api.v_wallets`, writes are RPCs.
abstract interface class WalletRepository {
  /// Own and shared wallets, ordered by name (stable order for the home list).
  Future<List<Wallet>> list();

  /// One wallet; throws an [AppFailure] `wallet_not_found` (404) when it does
  /// not exist, is someone else's or was deleted (the API does not tell them apart).
  Future<Wallet> getById(int walletId);

  /// `create_wallet`: returns the new wallet id.
  Future<int> create(WalletInput input);

  /// `update_wallet` (replacement: every field of [input] is sent).
  Future<void> update(int walletId, WalletInput input);

  /// `delete_wallet` 🔒: [onReauth] asks for the password on `403 reauth_required`.
  Future<void> delete(int walletId, {ReauthPrompt? onReauth});
}

class SupabaseWalletRepository implements WalletRepository {
  SupabaseWalletRepository(this._api);

  final ApiClient _api;

  static const view = 'v_wallets';

  /// Same message and key as the API's 404 so the UI handles both alike.
  static const notFound = AppFailure(
    kind: FailureKind.notFound,
    message: 'Billetera no encontrada',
    key: 'wallet_not_found',
    status: 404,
  );

  @override
  Future<List<Wallet>> list() async {
    final rows = await _api.select(view, query: (q) => q.order('name', ascending: true).order('wallet_id'));
    return rows.map(Wallet.fromJson).toList(growable: false);
  }

  @override
  Future<Wallet> getById(int walletId) async {
    final rows = await _api.select(view, query: (q) => q.eq('wallet_id', walletId).limit(1));
    if (rows.isEmpty) throw notFound;
    return Wallet.fromJson(rows.first);
  }

  @override
  Future<int> create(WalletInput input) async {
    final json = await _api.rpc<dynamic>('create_wallet', params: input.toParams());
    return json is Map ? ((json['wallet_id'] as num?)?.toInt() ?? 0) : 0;
  }

  @override
  Future<void> update(int walletId, WalletInput input) =>
      _api.rpc<dynamic>('update_wallet', params: {'p_wallet_id': walletId, ...input.toParams()});

  @override
  Future<void> delete(int walletId, {ReauthPrompt? onReauth}) =>
      _api.rpc<dynamic>('delete_wallet', params: {'p_wallet_id': walletId}, onReauth: onReauth);
}
