import 'package:countit_app/app/app.dart';
import 'package:countit_app/app/config/app_config.dart';
import 'package:countit_app/app/session/session_cubit.dart';
import 'package:countit_app/app/theme/app_theme.dart';
import 'package:countit_app/data/dtos/transaction.dart';
import 'package:countit_app/data/repositories/auth_repository.dart';
import 'package:countit_app/data/repositories/bank_repository.dart';
import 'package:countit_app/data/repositories/budget_repository.dart';
import 'package:countit_app/data/repositories/profile_repository.dart';
import 'package:countit_app/data/repositories/scheduled_transaction_repository.dart';
import 'package:countit_app/data/repositories/transaction_repository.dart';
import 'package:countit_app/data/repositories/wallet_repository.dart';
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
    SessionCubit? session,
    GoRouter? router,
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
        : CountItApp(router: router);

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
        ],
        child: BlocProvider<SessionCubit>.value(value: sessionCubit, child: app),
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
