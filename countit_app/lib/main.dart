import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'app/app.dart';
import 'app/config/app_config.dart';
import 'app/links/auth_links.dart';
import 'app/plans/plan_gate.dart';
import 'app/push/push_messaging.dart';
import 'app/push/push_open_handler.dart';
import 'app/push/push_token_service.dart';
import 'app/router/app_router.dart';
import 'app/session/session_cubit.dart';
import 'app/session/session_state.dart';
import 'data/remote/api_client.dart';
import 'data/remote/fresh_install.dart';
import 'data/remote/install_id.dart';
import 'data/remote/realtime_watcher.dart';
import 'data/remote/supabase_setup.dart';
import 'data/repositories/admin_repository.dart';
import 'data/repositories/analysis_repository.dart';
import 'data/repositories/auth_repository.dart';
import 'data/repositories/bank_repository.dart';
import 'data/repositories/budget_repository.dart';
import 'data/repositories/family_repository.dart';
import 'data/repositories/notification_repository.dart';
import 'data/repositories/plan_repository.dart';
import 'data/repositories/profile_repository.dart';
import 'data/repositories/push_device_repository.dart';
import 'data/repositories/scheduled_transaction_repository.dart';
import 'data/repositories/transaction_repository.dart';
import 'data/repositories/wallet_repository.dart';
import 'presentation/families/cubit/invitations_cubit.dart';
import 'presentation/notifications/cubit/notifications_cubit.dart';
import 'shared/platform/file_sharer.dart';
import 'shared/platform/notification_permission.dart';
import 'shared/utils/dates.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final config = AppConfig.fromEnvironment();
  await Dates.init();
  await FreshInstall.forgetPreviousInstall();

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
  final BudgetRepository budgets = SupabaseBudgetRepository(api);
  final TransactionRepository transactions = SupabaseTransactionRepository(api);
  final ScheduledTransactionRepository scheduled = SupabaseScheduledTransactionRepository(api);
  final AnalysisRepository analysis = SupabaseAnalysisRepository(api);
  final AdminRepository admin = SupabaseAdminRepository(api);
  final PlanRepository plans = SupabasePlanRepository(api);
  final realtime = SupabaseRealtimeWatcher(client);
  final FamilyRepository families = SupabaseFamilyRepository(api, realtime);
  final NotificationRepository notificationRepository = SupabaseNotificationRepository(api, realtime);

  // Push (HU-31): no-op until Firebase is configured (docs/PUSH.md); the
  // token service, permission and open handler are already wired.
  const PushMessaging messaging = NoopPushMessaging();
  const NotificationPermission notificationPermission = PlatformNotificationPermission();
  final pushTokens = PushTokenService(messaging: messaging, devices: SupabasePushDeviceRepository(api));

  final session = SessionCubit(
    auth: auth,
    profiles: profiles,
    // Leaving the account also removes local personal data (MASVS-STORAGE).
    beforeSignOut: () async {
      await pushTokens.signingOut();
      await SystemFileSharer.clearExports();
    },
    onSessionLost: () async {
      await pushTokens.sessionLost();
      await SystemFileSharer.clearExports();
    },
  );
  api.onSessionEnded = (failure) => unawaited(session.sessionEnded(failure));
  // A 403 feature_not_in_plan means the plan we know is stale or lacks the
  // function: offer the plans and reload the profile (COU-183).
  final planNotices = PlanNotices();
  api.onFeatureNotInPlan = (failure) {
    planNotices.report(failure);
    unawaited(session.refreshProfile());
  };
  final router = buildRouter(session: session, config: config);
  // Pending invitations follow the signed-in user (Realtime while signed in;
  // signing out closes the channel and forgets them).
  final invitations = InvitationsCubit(families);
  String? signedInUser(SessionState state) =>
      state.status == SessionStatus.authenticated ? state.profile?.userId : null;
  // The inbox and its badge follow the signed-in user the same way (HU-31).
  final notifications = NotificationsCubit(notificationRepository);
  session.stream.listen((state) {
    final user = signedInUser(state);
    unawaited(invitations.setUser(user));
    unawaited(notifications.setUser(user));
    unawaited(pushTokens.setUser(user));
  });
  final pushes = PushOpenHandler(
    messaging: messaging,
    isSignedIn: () => session.state.status == SessionStatus.authenticated,
    navigate: (location) => navigateForNotification(router, location),
    markRead: notifications.markReadById,
    refreshInbox: () => unawaited(notifications.load()),
  );
  // Back from the background: notifications may have arrived meanwhile.
  AppLifecycleListener(onResume: () => unawaited(notifications.load()));
  final links = AppLinks();
  final linkHandler = AuthLinkHandler(auth: auth, navigate: (destination) => navigateForAuthLink(router, destination));
  // Links wait for the restored session: otherwise the splash redirect would
  // swallow a cold-start link.
  unawaited(
    session.restore().whenComplete(() {
      unawaited(linkHandler.listen(initial: links.getInitialLink(), links: links.uriLinkStream));
      unawaited(pushes.start());
    }),
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
        RepositoryProvider.value(value: budgets),
        RepositoryProvider.value(value: transactions),
        RepositoryProvider.value(value: scheduled),
        RepositoryProvider.value(value: families),
        RepositoryProvider.value(value: notificationRepository),
        RepositoryProvider.value(value: messaging),
        RepositoryProvider.value(value: notificationPermission),
        RepositoryProvider.value(value: analysis),
        RepositoryProvider.value(value: admin),
        RepositoryProvider.value(value: plans),
      ],
      child: MultiBlocProvider(
        providers: [
          BlocProvider.value(value: session),
          BlocProvider.value(value: invitations),
          BlocProvider.value(value: notifications),
        ],
        child: CountItApp(
          router: router,
          session: session,
          planNotices: planNotices.featureNotInPlan,
          pushNotices: pushes.notices,
        ),
      ),
    ),
  );
}
