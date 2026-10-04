import 'package:countit_app/app/app.dart';
import 'package:countit_app/app/config/app_config.dart';
import 'package:countit_app/app/errors/app_failure.dart';
import 'package:countit_app/app/session/session_cubit.dart';
import 'package:countit_app/app/theme/app_theme.dart';
import 'package:countit_app/data/dtos/notification.dart';
import 'package:countit_app/data/dtos/paged.dart';
import 'package:countit_app/data/dtos/transaction.dart';
import 'package:countit_app/data/repositories/admin_repository.dart';
import 'package:countit_app/data/repositories/analysis_repository.dart';
import 'package:countit_app/data/repositories/auth_repository.dart';
import 'package:countit_app/data/repositories/bank_repository.dart';
import 'package:countit_app/data/repositories/budget_repository.dart';
import 'package:countit_app/data/repositories/family_repository.dart';
import 'package:countit_app/data/repositories/notification_repository.dart';
import 'package:countit_app/data/repositories/profile_repository.dart';
import 'package:countit_app/data/repositories/scheduled_transaction_repository.dart';
import 'package:countit_app/data/repositories/transaction_repository.dart';
import 'package:countit_app/data/repositories/wallet_repository.dart';
import 'package:countit_app/presentation/families/cubit/invitations_cubit.dart';
import 'package:countit_app/presentation/notifications/cubit/notifications_cubit.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';

import 'mocks.dart';

/// Local config without captcha (the Turnstile webview cannot run in widget tests).
const testConfig = AppConfig(
  environment: AppEnvironment.local,
  supabaseUrl: 'http://localhost:54321',
  supabaseAnonKey: 'anon',
);

extension PumpApp on WidgetTester {
  /// Pumps [widget] the way the app runs it: dark theme of the design,
  /// es-EC locale and the root providers, each replaceable by a fake.
  ///
  /// Pass [router] to test navigation; otherwise [widget] is the home.
  Future<void> pumpApp(
    Widget widget, {
    AuthRepository? auth,
    ProfileRepository? profiles,
    WalletRepository? wallets,
    BankRepository? banks,
    BudgetRepository? budgets,
    TransactionRepository? transactions,
    ScheduledTransactionRepository? scheduled,
    FamilyRepository? families,
    AnalysisRepository? analysis,
    AdminRepository? admin,
    SessionCubit? session,
    InvitationsCubit? invitations,
    NotificationRepository? notifications,
    NotificationsCubit? notificationsCubit,
    GoRouter? router,
    Stream<AppFailure>? planNotices,
    AppConfig config = testConfig,
    ThemeMode themeMode = ThemeMode.dark,
  }) async {
    final authRepository = auth ?? MockAuthRepository();
    final profileRepository = profiles ?? MockProfileRepository();
    if (auth == null) {
      when(() => (authRepository as MockAuthRepository).sessionChanges).thenAnswer((_) => const Stream.empty());
    }
    final sessionCubit = session ?? SessionCubit(auth: authRepository, profiles: profileRepository);
    if (session == null) addTearDown(sessionCubit.close);
    final familyRepository = families ?? noFamilies();
    // Not following anyone unless the test starts it: no invitations, no badge.
    final invitationsCubit = invitations ?? InvitationsCubit(familyRepository);
    if (invitations == null) addTearDown(invitationsCubit.close);
    final notificationRepository = notifications ?? noNotifications();
    // Not following anyone unless the test starts it: an empty inbox, no badge.
    final inbox = notificationsCubit ?? NotificationsCubit(notificationRepository);
    if (notificationsCubit == null) addTearDown(inbox.close);

    final app = router == null
        ? MaterialApp(
            theme: AppTheme.light,
            darkTheme: AppTheme.dark,
            themeMode: themeMode,
            locale: CountItApp.locale,
            supportedLocales: const [CountItApp.locale],
            localizationsDelegates: GlobalMaterialLocalizations.delegates,
            home: Scaffold(body: widget),
          )
        : CountItApp(router: router, planNotices: planNotices);

    await pumpWidget(
      MultiRepositoryProvider(
        providers: [
          RepositoryProvider<AppConfig>.value(value: config),
          RepositoryProvider<AuthRepository>.value(value: authRepository),
          RepositoryProvider<ProfileRepository>.value(value: profileRepository),
          RepositoryProvider<WalletRepository>.value(value: wallets ?? MockWalletRepository()),
          RepositoryProvider<BankRepository>.value(value: banks ?? MockBankRepository()),
          RepositoryProvider<BudgetRepository>.value(value: budgets ?? MockBudgetRepository()),
          RepositoryProvider<TransactionRepository>.value(value: transactions ?? _emptyTransactions()),
          RepositoryProvider<ScheduledTransactionRepository>.value(
            value: scheduled ?? MockScheduledTransactionRepository(),
          ),
          RepositoryProvider<FamilyRepository>.value(value: familyRepository),
          RepositoryProvider<NotificationRepository>.value(value: notificationRepository),
          RepositoryProvider<AnalysisRepository>.value(value: analysis ?? MockAnalysisRepository()),
          RepositoryProvider<AdminRepository>.value(value: admin ?? MockAdminRepository()),
        ],
        child: MultiBlocProvider(
          providers: [
            BlocProvider<SessionCubit>.value(value: sessionCubit),
            BlocProvider<InvitationsCubit>.value(value: invitationsCubit),
            BlocProvider<NotificationsCubit>.value(value: inbox),
          ],
          child: app,
        ),
      ),
    );
    await pump();
  }
}

/// Default transactions double: every wallet has no movements, so screens
/// that embed the list (wallet detail) work without extra stubbing.
MockTransactionRepository _emptyTransactions() {
  final repository = MockTransactionRepository();
  when(
    () => repository.list(
      any(),
      after: any(named: 'after'),
      limit: any(named: 'limit'),
    ),
  ).thenAnswer((_) async => const TransactionPage([]));
  return repository;
}

/// Default families double: no members, no invitations and no live changes.
MockFamilyRepository noFamilies() {
  final repository = MockFamilyRepository();
  when(() => repository.membersOf(any())).thenAnswer((_) async => const []);
  when(repository.myInvitations).thenAnswer((_) async => const []);
  when(() => repository.myMembershipChanges(any())).thenAnswer((_) => const Stream.empty());
  when(() => repository.walletMembershipChanges(any())).thenAnswer((_) => const Stream.empty());
  return repository;
}

/// Default notifications double: an empty inbox, nothing unread.
MockNotificationRepository noNotifications() {
  final repository = MockNotificationRepository();
  when(
    () => repository.inbox(
      before: any(named: 'before'),
      limit: any(named: 'limit'),
    ),
  ).thenAnswer((_) async => const Paged(<AppNotification>[], hasMore: false));
  when(repository.unreadCount).thenAnswer((_) async => 0);
  when(() => repository.markRead(any())).thenAnswer((_) async {});
  when(repository.markAllRead).thenAnswer((_) async {});
  return repository;
}
