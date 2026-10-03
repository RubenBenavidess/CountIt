import 'package:supabase_flutter/supabase_flutter.dart';

import '../../app/config/app_config.dart';
import 'secure_session_storage.dart';

/// Initializes Supabase for the app.
///
/// The backend exposes only the `api` schema: without `schema: 'api'` every
/// view and RPC answers `406 PGRST106` (CountIt-Backend-Dev `docs/API.md`).
Future<SupabaseClient> initSupabase(AppConfig config) async {
  final supabase = await Supabase.initialize(
    url: config.supabaseUrl,
    // The legacy anon JWT is accepted as a publishable key.
    publishableKey: config.supabaseAnonKey,
    postgrestOptions: const PostgrestClientOptions(schema: 'api'),
    authOptions: FlutterAuthClientOptions(localStorage: SecureSessionStorage()),
    debug: false,
  );
  return supabase.client;
}
