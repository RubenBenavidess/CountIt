import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../shared/widgets/secure_screen.dart';
import 'session_cubit.dart';
import 'session_state.dart';

/// `FLAG_SECURE` for the whole app while there is a session (MASVS-PLATFORM,
/// COU-115): every signed-in screen shows balances, movements, e-mails or
/// plans, so new screens are covered without opting in. The recovery state
/// (new password) is covered too.
class SessionSecureScreen extends StatelessWidget {
  const SessionSecureScreen({super.key, required this.session, required this.child});

  final SessionCubit session;
  final Widget child;

  static bool isSensitive(SessionStatus status) =>
      status == SessionStatus.authenticated || status == SessionStatus.passwordRecovery;

  @override
  Widget build(BuildContext context) => BlocSelector<SessionCubit, SessionState, bool>(
    bloc: session,
    selector: (state) => isSensitive(state.status),
    builder: (context, sensitive) => SecureScreen(enabled: sensitive, child: child),
  );
}
