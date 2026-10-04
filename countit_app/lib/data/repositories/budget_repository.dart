import '../../app/errors/app_failure.dart';
import '../dtos/budget.dart';
import '../remote/api_client.dart';

/// Budgets of a wallet (HU-11..HU-14). Reads come from `api.v_budgets`, writes are RPCs.
abstract interface class BudgetRepository {
  /// Active budgets of [walletId], ordered by name (stable order for the list).
  Future<List<Budget>> listByWallet(int walletId);

  /// One budget; throws an [AppFailure] `budget_not_found` (404) when it does
  /// not exist, is not visible or was deleted (the API does not tell them apart).
  Future<Budget> getById(int budgetId);

  /// `create_budget` in [walletId]: returns the new budget id.
  Future<int> create(int walletId, BudgetInput input);

  /// `update_budget` (replacement: every field of [input] is sent).
  Future<void> update(int budgetId, BudgetInput input);

  /// `delete_budget` 🔒: [onReauth] asks for the password on `403 reauth_required`.
  Future<void> delete(int budgetId, {ReauthPrompt? onReauth});
}

class SupabaseBudgetRepository implements BudgetRepository {
  SupabaseBudgetRepository(this._api);

  final ApiClient _api;

  static const view = 'v_budgets';

  /// Same message and key as the API's 404 so the UI handles both alike.
  static const notFound = AppFailure(
    kind: FailureKind.notFound,
    message: 'Presupuesto no encontrado',
    key: 'budget_not_found',
    status: 404,
  );

  @override
  Future<List<Budget>> listByWallet(int walletId) async {
    final rows = await _api.select(
      view,
      query: (q) => q.eq('wallet_id', walletId).order('name', ascending: true).order('budget_id'),
    );
    return rows.map(Budget.fromJson).toList(growable: false);
  }

  @override
  Future<Budget> getById(int budgetId) async {
    final rows = await _api.select(view, query: (q) => q.eq('budget_id', budgetId).limit(1));
    if (rows.isEmpty) throw notFound;
    return Budget.fromJson(rows.first);
  }

  @override
  Future<int> create(int walletId, BudgetInput input) async {
    final json = await _api.rpc<dynamic>('create_budget', params: {'p_wallet_id': walletId, ...input.toParams()});
    return json is Map ? ((json['budget_id'] as num?)?.toInt() ?? 0) : 0;
  }

  @override
  Future<void> update(int budgetId, BudgetInput input) =>
      _api.rpc<dynamic>('update_budget', params: {'p_budget_id': budgetId, ...input.toParams()});

  @override
  Future<void> delete(int budgetId, {ReauthPrompt? onReauth}) =>
      _api.rpc<dynamic>('delete_budget', params: {'p_budget_id': budgetId}, onReauth: onReauth);
}
