import '../dtos/profile.dart';
import '../remote/api_client.dart';

abstract interface class ProfileRepository {
  /// `api.get_my_profile()`: profile, role, plan and limits.
  Future<Profile> fetchMyProfile();

  /// `api.update_my_profile`: names are required; [username] and [timezone]
  /// are sent only when they change (a username change is audited).
  Future<void> updateMyProfile({
    required String firstName,
    required String lastName,
    String? username,
    String? timezone,
  });

  /// `api.export_my_data()` (HU-29, LOPDP): everything stored about the user.
  Future<Map<String, dynamic>> exportMyData();
}

class SupabaseProfileRepository implements ProfileRepository {
  SupabaseProfileRepository(this._api);

  final ApiClient _api;

  @override
  Future<Profile> fetchMyProfile() async {
    final json = await _api.rpc<Map<String, dynamic>>('get_my_profile');
    return Profile.fromJson(json);
  }

  @override
  Future<void> updateMyProfile({
    required String firstName,
    required String lastName,
    String? username,
    String? timezone,
  }) => _api.rpc<dynamic>(
    'update_my_profile',
    params: {'p_first_name': firstName, 'p_last_name': lastName, 'p_username': ?username, 'p_timezone': ?timezone},
  );

  @override
  Future<Map<String, dynamic>> exportMyData() async {
    final json = await _api.rpc<dynamic>('export_my_data');
    return json is Map ? Map<String, dynamic>.from(json) : <String, dynamic>{};
  }
}
