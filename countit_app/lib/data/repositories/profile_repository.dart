import '../dtos/profile.dart';
import '../remote/api_client.dart';

abstract interface class ProfileRepository {
  /// `api.get_my_profile()`: profile, role, plan and limits.
  Future<Profile> fetchMyProfile();
}

class SupabaseProfileRepository implements ProfileRepository {
  SupabaseProfileRepository(this._api);

  final ApiClient _api;

  @override
  Future<Profile> fetchMyProfile() async {
    final json = await _api.rpc<Map<String, dynamic>>('get_my_profile');
    return Profile.fromJson(json);
  }
}
