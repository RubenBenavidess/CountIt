import '../../app/errors/app_failure.dart';
import '../../app/errors/error_mapper.dart';
import '../../shared/utils/dates.dart';
import '../dtos/admin.dart';
import '../dtos/profile.dart';
import '../remote/api_client.dart';

/// Administration (HU-27, HU-28) through the `api.admin_*` RPCs.
///
/// The backend is the authority: every call checks the caller's role
/// (403 `forbidden`) and plans and roles are superadmin only. The client
/// only hides what the role cannot use.
abstract interface class AdminRepository {
  /// Users page size (the API accepts 1–100).
  static const usersPageSize = 30;

  /// `admin_list_users`: ordered by username; [search] is a literal,
  /// case-insensitive match on username or e-mail.
  Future<Paged<AdminUser>> listUsers({String? search, int offset = 0, int limit = usersPageSize});

  /// `admin_set_user_plan` 🛡: replaces the active plan until [validUntil]
  /// (after today); a downgrade applies its quotas right away.
  Future<PlanAssignment> setUserPlan(String userId, {required int planId, required DateTime validUntil});

  /// `admin_set_user_role` 🛡.
  Future<UserRole> setUserRole(String userId, UserRole role);
}

class SupabaseAdminRepository implements AdminRepository {
  SupabaseAdminRepository(this._api);

  final ApiClient _api;

  static const _unexpected = AppFailure(kind: FailureKind.server, message: ErrorMapper.genericMessage);

  /// Asks one row more than [limit] to know whether another page exists.
  static Paged<T> _page<T>(Object? rows, int limit, T Function(Map<String, dynamic>) parse) {
    if (rows is! List) throw _unexpected;
    final items = rows.whereType<Map<dynamic, dynamic>>().map((r) => parse(Map<String, dynamic>.from(r))).toList();
    return Paged(items.take(limit).toList(growable: false), hasMore: items.length > limit);
  }

  @override
  Future<Paged<AdminUser>> listUsers({
    String? search,
    int offset = 0,
    int limit = AdminRepository.usersPageSize,
  }) async {
    final term = search?.trim() ?? '';
    final rows = await _api.rpc<dynamic>(
      'admin_list_users',
      params: {'p_search': ?(term.isEmpty ? null : term), 'p_limit': limit + 1, 'p_offset': offset},
    );
    return _page(rows, limit, AdminUser.fromJson);
  }

  @override
  Future<PlanAssignment> setUserPlan(String userId, {required int planId, required DateTime validUntil}) async {
    final json = await _api.rpc<dynamic>(
      'admin_set_user_plan',
      params: {'p_user_id': userId, 'p_plan_id': planId, 'p_valid_until': Dates.toApi(validUntil)},
    );
    if (json is! Map) throw _unexpected;
    return PlanAssignment.fromJson(Map<String, dynamic>.from(json));
  }

  @override
  Future<UserRole> setUserRole(String userId, UserRole role) async {
    final json = await _api.rpc<dynamic>('admin_set_user_role', params: {'p_user_id': userId, 'p_role': role.name});
    if (json is! Map) throw _unexpected;
    return UserRole.parse(json['role'] as String?);
  }
}
