import 'package:countit_app/data/dtos/admin.dart';
import 'package:countit_app/data/dtos/profile.dart';

/// A row of `admin_list_users` as the API sends it.
Map<String, dynamic> adminUserJson({
  String id = 'u-carlos',
  String username = 'demo_carlos',
  String role = 'user',
  String? plan = 'Regular',
  String? validUntil = '2028-10-04',
}) => {
  'user_id': id,
  'username': username,
  'email': 'delivered+$username@resend.dev',
  'first_name': 'Carlos',
  'last_name': 'Pérez',
  'role': role,
  'plan': plan,
  'plan_valid_until': validUntil,
  'created_at': '2026-10-02T15:00:00Z',
};

AdminUser adminUser({
  String id = 'u-carlos',
  String username = 'demo_carlos',
  UserRole role = UserRole.user,
  String? plan = 'Regular',
  DateTime? validUntil,
}) => AdminUser(
  userId: id,
  username: username,
  email: 'delivered+$username@resend.dev',
  firstName: 'Carlos',
  lastName: 'Pérez',
  role: role,
  planName: plan,
  planValidUntil: validUntil ?? DateTime(2028, 10, 4),
  createdAt: DateTime.utc(2026, 10, 2, 15),
);

/// [count] users named user01, user02…
List<AdminUser> adminUsers(int count, {int from = 1}) => [
  for (var i = from; i < from + count; i++) adminUser(id: 'u$i', username: 'user${i.toString().padLeft(2, '0')}'),
];

Profile adminProfile(UserRole role, {String id = 'u-me'}) => Profile(
  userId: id,
  username: 'rubendario',
  email: 'admin@correo.ec',
  firstName: 'Rubén',
  role: role,
  timezone: 'America/Guayaquil',
);
