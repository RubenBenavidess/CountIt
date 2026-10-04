import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'app/app.dart';
import 'app/config/app_config.dart';
import 'app/links/auth_links.dart';
import 'app/router/app_router.dart';
import 'app/session/session_cubit.dart';
import 'data/remote/api_client.dart';
import 'data/remote/install_id.dart';
import 'data/remote/supabase_setup.dart';
import 'data/repositories/auth_repository.dart';
import 'data/repositories/bank_repository.dart';
import 'data/repositories/profile_repository.dart';
import 'data/repositories/wallet_repository.dart';
import 'shared/utils/dates.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final config = AppConfig.fromEnvironment();
  await Dates.init();

  final client = await initSupabase(config);
  final api = ApiClient(
    client,
    functionsUrl: Uri.parse('${config.supabaseUrl}/functions/v1'),
    deviceId: await InstallId.load(),
  );
  final AuthRepository auth = SupabaseAuthRepository(api);
  final ProfileRepository profiles = SupabaseProfileRepository(api);
  final WalletRepository wallets = SupabaseWalletRepository(api);
  final BankRepository banks = SupabaseBankRepository(api);

  final session = SessionCubit(auth: auth, profiles: profiles);
  api.onSessionEnded = (failure) => unawaited(session.sessionEnded(failure));
  final router = buildRouter(session: session, config: config);
  final links = AppLinks();
  final linkHandler = AuthLinkHandler(auth: auth, navigate: (destination) => navigateForAuthLink(router, destination));
  // Links wait for the restored session: otherwise the splash redirect would
  // swallow a cold-start link.
  unawaited(
    session.restore().whenComplete(
      () => linkHandler.listen(initial: links.getInitialLink(), links: links.uriLinkStream),
    ),
  );

  runApp(
    MultiRepositoryProvider(
      providers: [
        RepositoryProvider.value(value: config),
        RepositoryProvider.value(value: api),
        RepositoryProvider.value(value: auth),
        RepositoryProvider.value(value: profiles),
        RepositoryProvider.value(value: wallets),
        RepositoryProvider.value(value: banks),
      ],
      child: BlocProvider.value(
        value: session,
        child: CountItApp(router: router),
      ),
    ),
  );
}
