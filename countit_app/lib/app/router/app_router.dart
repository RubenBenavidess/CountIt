import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import '../../data/dtos/scheduled_transaction.dart';
import '../../data/dtos/transaction.dart';
import '../../data/dtos/wallet.dart';
import '../../presentation/account/view/change_password_page.dart';
import '../../presentation/account/view/delete_account_page.dart';
import '../../presentation/admin/view/admin_page.dart';
import '../../presentation/auth/view/check_email_page.dart';
import '../../presentation/auth/view/email_confirmed_page.dart';
import '../../presentation/auth/view/forgot_password_page.dart';
import '../../presentation/auth/view/login_page.dart';
import '../../presentation/auth/view/register_page.dart';
import '../../presentation/auth/view/reset_password_page.dart';
import '../../presentation/auth/view/welcome_page.dart';
import '../../presentation/budgets/view/budget_form_page.dart';
import '../../presentation/families/view/family_members_page.dart';
import '../../presentation/families/view/invitations_page.dart';
import '../../presentation/families/view/invite_member_page.dart';
import '../../presentation/home/view/home_page.dart';
import '../../presentation/profile/view/edit_profile_page.dart';
import '../../presentation/profile/view/profile_page.dart';
import '../../presentation/scheduled/view/scheduled_form_page.dart';
import '../../presentation/scheduled/view/scheduled_list_page.dart';
import '../../presentation/shell/view/app_shell.dart';
import '../../presentation/splash/view/splash_page.dart';
import '../../presentation/statistics/view/projection_page.dart';
import '../../presentation/statistics/view/statistics_page.dart';
import '../../presentation/transactions/view/transaction_detail_page.dart';
import '../../presentation/transactions/view/transaction_form_page.dart';
import '../../presentation/wallets/view/wallet_detail_page.dart';
import '../../presentation/wallets/view/wallet_form_page.dart';
import '../config/app_config.dart';
import '../links/auth_links.dart';
import '../session/session_cubit.dart';
import '../session/session_state.dart';

abstract final class AppRoutes {
  static const splash = '/splash';
  static const welcome = '/welcome';
  static const login = '/login';
  static const register = '/register';
  static const checkEmail = '/check-email';
  static const forgotPassword = '/forgot-password';
  static const emailConfirmed = '/email-confirmed';
  static const resetPassword = '/reset-password';
  static const root = '/';
  static const home = '/home';
  static const wallets = '/wallets';
  static const newWallet = '/wallets/new';
  static const admin = '/admin';
  static const profile = '/profile';
  static const editProfile = '/profile/edit';
  static const changePassword = '/profile/password';
  static const deleteAccount = '/profile/delete';
  static const invitations = '/invitations';

  static String wallet(int walletId) => '$wallets/$walletId';
  static String editWallet(int walletId) => '$wallets/$walletId/edit';
  static String newBudget(int walletId) => '$wallets/$walletId/budgets/new';
  static String editBudget(int walletId, int budgetId) => '$wallets/$walletId/budgets/$budgetId/edit';
  static String newTransaction(int walletId) => '$wallets/$walletId/transactions/new';
  static String transaction(int walletId, int transactionId) => '$wallets/$walletId/transactions/$transactionId';
  static String editTransaction(int walletId, int transactionId) =>
      '$wallets/$walletId/transactions/$transactionId/edit';
  static String scheduled(int walletId) => '$wallets/$walletId/scheduled';
  static String newScheduled(int walletId) => '$wallets/$walletId/scheduled/new';
  static String editScheduled(int walletId, int ruleId) => '$wallets/$walletId/scheduled/$ruleId/edit';
  static String statistics(int walletId) => '$wallets/$walletId/statistics';
  static String projection(int walletId) => '$wallets/$walletId/projection';
  static String members(int walletId) => '$wallets/$walletId/members';
  static String inviteMember(int walletId) => '$wallets/$walletId/members/invite';

  /// Reachable without a session.
  static const public = {welcome, login, register, checkEmail, forgotPassword, emailConfirmed};

  /// Query flag for a link that expired or was already used.
  static const expired = 'expired';
}

/// Pure redirect rules (unit-tested): session first, then role (COU-46).
String? redirectFor(SessionState session, String location) {
  switch (session.status) {
    case SessionStatus.unknown:
      return location == AppRoutes.splash ? null : AppRoutes.splash;
    case SessionStatus.passwordRecovery:
      // The recovery session only opens the new-password screen.
      return location == AppRoutes.resetPassword ? null : AppRoutes.resetPassword;
    case SessionStatus.unauthenticated:
      if (AppRoutes.public.contains(location)) return null;
      // An involuntary sign-out explains itself on the login screen (COU-81);
      // a fresh start shows the welcome screen.
      return session.message != null ? AppRoutes.login : AppRoutes.welcome;
    case SessionStatus.authenticated:
      if (location == AppRoutes.root ||
          location == AppRoutes.splash ||
          location == AppRoutes.resetPassword ||
          AppRoutes.public.contains(location)) {
        return AppRoutes.home;
      }
      if (location.startsWith(AppRoutes.admin) && !(session.profile?.role.canAdminister ?? false)) {
        return AppRoutes.home;
      }
      return null;
  }
}

/// `/wallets/<id>` → id; null for a malformed path (the router sends it home).
int? _walletId(GoRouterState state) => int.tryParse(state.pathParameters['id'] ?? '');

GoRouter buildRouter({required SessionCubit session, required AppConfig config}) => GoRouter(
  navigatorKey: GlobalKey<NavigatorState>(debugLabel: 'root'),
  initialLocation: AppRoutes.splash,
  refreshListenable: _StreamListenable(session.stream),
  redirect: (context, state) => redirectFor(session.state, state.matchedLocation),
  routes: [
    GoRoute(
      path: AppRoutes.splash,
      builder: (context, state) => SplashPage(environment: config.environment),
    ),
    GoRoute(path: AppRoutes.welcome, builder: (context, state) => const WelcomePage()),
    GoRoute(path: AppRoutes.login, builder: (context, state) => const LoginPage()),
    GoRoute(path: AppRoutes.register, builder: (context, state) => const RegisterPage()),
    GoRoute(
      path: AppRoutes.checkEmail,
      builder: (context, state) => CheckEmailPage(email: state.extra is String ? state.extra! as String : null),
    ),
    GoRoute(
      path: AppRoutes.forgotPassword,
      builder: (context, state) =>
          ForgotPasswordPage(linkExpired: state.uri.queryParameters.containsKey(AppRoutes.expired)),
    ),
    GoRoute(
      path: AppRoutes.emailConfirmed,
      builder: (context, state) =>
          EmailConfirmedPage(expired: state.uri.queryParameters.containsKey(AppRoutes.expired)),
    ),
    GoRoute(path: AppRoutes.resetPassword, builder: (context, state) => const ResetPasswordPage()),
    GoRoute(path: AppRoutes.root, redirect: (context, state) => AppRoutes.home),
    // Tabs of the signed-in shell (COU-168); screens pushed from them cover
    // the bottom bar (root navigator).
    StatefulShellRoute.indexedStack(
      builder: (context, state, shell) => AppShell(shell: shell),
      branches: [
        StatefulShellBranch(
          routes: [GoRoute(path: AppRoutes.home, builder: (context, state) => const HomePage())],
        ),
        StatefulShellBranch(
          routes: [GoRoute(path: AppRoutes.profile, builder: (context, state) => const ProfilePage())],
        ),
      ],
    ),
    GoRoute(path: AppRoutes.editProfile, builder: (context, state) => const EditProfilePage()),
    GoRoute(path: AppRoutes.changePassword, builder: (context, state) => const ChangePasswordPage()),
    GoRoute(path: AppRoutes.deleteAccount, builder: (context, state) => const DeleteAccountPage()),
    GoRoute(path: AppRoutes.admin, builder: (context, state) => const AdminPage()),
    GoRoute(path: AppRoutes.invitations, builder: (context, state) => const InvitationsPage()),
    GoRoute(path: AppRoutes.newWallet, builder: (context, state) => const WalletFormPage()),
    GoRoute(
      path: '${AppRoutes.wallets}/:id',
      redirect: (context, state) => _walletId(state) == null ? AppRoutes.home : null,
      builder: (context, state) =>
          WalletDetailPage(walletId: _walletId(state)!, initial: state.extra is Wallet ? state.extra! as Wallet : null),
      routes: [
        GoRoute(
          path: 'edit',
          // The form edits the wallet the detail screen loaded; without it
          // (deep link, restored route) the detail loads it first.
          redirect: (context, state) => state.extra is Wallet ? null : AppRoutes.wallet(_walletId(state) ?? 0),
          builder: (context, state) => WalletFormPage(initial: state.extra! as Wallet),
        ),
        GoRoute(
          path: 'budgets/new',
          builder: (context, state) => BudgetFormPage(walletId: _walletId(state)!),
        ),
        GoRoute(
          path: 'budgets/:budgetId/edit',
          // Like the wallet form: it edits the budget the detail screen listed.
          redirect: (context, state) => state.extra is BudgetEditArgs ? null : AppRoutes.wallet(_walletId(state) ?? 0),
          builder: (context, state) {
            final args = state.extra! as BudgetEditArgs;
            return BudgetFormPage(walletId: _walletId(state)!, initial: args.budget, canDelete: args.canDelete);
          },
        ),
        GoRoute(
          path: 'transactions/new',
          builder: (context, state) => TransactionFormPage(walletId: _walletId(state)!),
        ),
        GoRoute(
          path: 'transactions/:transactionId',
          // Shows the transaction the wallet listed; without it, back to the wallet.
          redirect: (context, state) =>
              state.extra is TransactionDetailArgs ? null : AppRoutes.wallet(_walletId(state) ?? 0),
          builder: (context, state) =>
              TransactionDetailPage(walletId: _walletId(state)!, args: state.extra! as TransactionDetailArgs),
        ),
        GoRoute(
          path: 'transactions/:transactionId/edit',
          // Edits the transaction the wallet listed; without it, back to the wallet.
          redirect: (context, state) => state.extra is Transaction ? null : AppRoutes.wallet(_walletId(state) ?? 0),
          builder: (context, state) =>
              TransactionFormPage(walletId: _walletId(state)!, initial: state.extra! as Transaction),
        ),
        GoRoute(
          path: 'scheduled',
          // Lists the rules of the wallet the detail screen loaded (ownership, shared).
          redirect: (context, state) => state.extra is Wallet ? null : AppRoutes.wallet(_walletId(state) ?? 0),
          builder: (context, state) => ScheduledListPage(wallet: state.extra! as Wallet),
        ),
        GoRoute(
          path: 'scheduled/new',
          // Optional draft: the fields of a transaction form with a future date.
          builder: (context, state) => ScheduledFormPage(
            walletId: _walletId(state)!,
            draft: state.extra is ScheduledTransactionInput ? state.extra! as ScheduledTransactionInput : null,
          ),
        ),
        GoRoute(
          path: 'scheduled/:ruleId/edit',
          // Edits the rule the list showed; without it, back to the wallet.
          redirect: (context, state) =>
              state.extra is ScheduledEditArgs ? null : AppRoutes.wallet(_walletId(state) ?? 0),
          builder: (context, state) {
            final args = state.extra! as ScheduledEditArgs;
            return ScheduledFormPage(walletId: _walletId(state)!, initial: args.rule, canDelete: args.canDelete);
          },
        ),
        GoRoute(
          path: 'statistics',
          // The wallet the detail screen passed only names the selector at once.
          builder: (context, state) => StatisticsPage(
            walletId: _walletId(state)!,
            initial: state.extra is Wallet ? state.extra! as Wallet : null,
          ),
        ),
        GoRoute(
          path: 'projection',
          // Projection of the wallet the detail screen loaded (name).
          redirect: (context, state) => state.extra is Wallet ? null : AppRoutes.wallet(_walletId(state) ?? 0),
          builder: (context, state) => ProjectionPage(wallet: state.extra! as Wallet),
        ),
        GoRoute(
          path: 'members',
          // Members of the wallet the detail screen loaded (name, ownership).
          redirect: (context, state) => state.extra is Wallet ? null : AppRoutes.wallet(_walletId(state) ?? 0),
          builder: (context, state) => FamilyMembersPage(wallet: state.extra! as Wallet),
        ),
        GoRoute(
          path: 'members/invite',
          // Invites to the wallet the members screen showed (owner only; the API decides).
          redirect: (context, state) => state.extra is Wallet ? null : AppRoutes.wallet(_walletId(state) ?? 0),
          builder: (context, state) => InviteMemberPage(wallet: state.extra! as Wallet),
        ),
      ],
    ),
  ],
);

/// Where each handled e-mail link lands; the reset screen itself is reached
/// through the recovery state ([redirectFor]).
void navigateForAuthLink(GoRouter router, AuthLinkDestination destination) {
  switch (destination) {
    case AuthLinkDestination.emailConfirmed:
      router.go(AppRoutes.emailConfirmed);
    case AuthLinkDestination.emailLinkExpired:
      router.go('${AppRoutes.emailConfirmed}?${AppRoutes.expired}=1');
    case AuthLinkDestination.resetPassword:
      router.go(AppRoutes.resetPassword);
    case AuthLinkDestination.resetLinkExpired:
      router.go('${AppRoutes.forgotPassword}?${AppRoutes.expired}=1');
  }
}

/// Re-runs the router redirect whenever the session changes.
class _StreamListenable extends ChangeNotifier {
  _StreamListenable(Stream<Object?> stream) {
    _subscription = stream.listen((_) => notifyListeners());
  }

  late final StreamSubscription<Object?> _subscription;

  @override
  void dispose() {
    unawaited(_subscription.cancel());
    super.dispose();
  }
}
