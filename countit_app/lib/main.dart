import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'app/app.dart';
import 'app/config/app_config.dart';
import 'app/router/app_router.dart';
import 'app/session/session_cubit.dart';
import 'data/remote/api_client.dart';
import 'data/remote/install_id.dart';
import 'data/remote/supabase_setup.dart';
import 'data/repositories/auth_repository.dart';
import 'data/repositories/profile_repository.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final config = AppConfig.fromEnvironment();

  final client = await initSupabase(config);
  final api = ApiClient(client, deviceId: await InstallId.load());
  final AuthRepository auth = SupabaseAuthRepository(api);
  final ProfileRepository profiles = SupabaseProfileRepository(api);

  final session = SessionCubit(auth: auth, profiles: profiles);
  api.onSessionEnded = (failure) => unawaited(session.sessionEnded(failure));
  unawaited(session.restore());

  runApp(
    MultiRepositoryProvider(
      providers: [
        RepositoryProvider.value(value: config),
        RepositoryProvider.value(value: api),
        RepositoryProvider.value(value: auth),
        RepositoryProvider.value(value: profiles),
      ],
      child: BlocProvider.value(
        value: session,
        child: CountItApp(
          router: buildRouter(session: session, config: config),
        ),
      ),
    ),
  );
}
