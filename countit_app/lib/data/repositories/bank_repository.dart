import '../dtos/bank.dart';
import '../remote/api_client.dart';

/// Bank catalogue (`api.v_banks`): users see the active banks only.
abstract interface class BankRepository {
  /// Banks ordered by name; [search] filters by name (`name=ilike.*x*`).
  Future<List<Bank>> list({String? search});
}

class SupabaseBankRepository implements BankRepository {
  SupabaseBankRepository(this._api);

  final ApiClient _api;

  /// PostgREST pattern and filter syntax characters are dropped from the search.
  static final _unsafe = RegExp(r'[%_*,()\\]');

  /// The term as sent inside `ilike` (exposed for tests).
  static String pattern(String search) => '%${search.replaceAll(_unsafe, ' ').trim()}%';

  @override
  Future<List<Bank>> list({String? search}) async {
    final term = search?.trim() ?? '';
    final rows = await _api.select(
      'v_banks',
      query: (q) => (term.isEmpty ? q : q.ilike('name', pattern(term))).order('name', ascending: true),
    );
    return rows.map(Bank.fromJson).where((bank) => bank.isActive).toList(growable: false);
  }
}
