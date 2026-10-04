import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../app/session/session_cubit.dart';
import '../../../app/theme/tokens.dart';
import '../../../data/repositories/auth_repository.dart';
import '../../../shared/widgets/app_button.dart';
import '../../../shared/widgets/app_fields.dart';
import '../../../shared/widgets/secure_screen.dart';
import '../../../shared/widgets/wordmark.dart';
import '../cubit/login_cubit.dart';

/// Minimal working login to exercise the session flow end to end.
/// The designed screen, validations and captcha arrive in F02 (COU-84, COU-118).
class LoginPage extends StatelessWidget {
  const LoginPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) => LoginCubit(context.read<AuthRepository>()),
      child: const SecureScreen(child: _LoginView()),
    );
  }
}

class _LoginView extends StatefulWidget {
  const _LoginView();

  @override
  State<_LoginView> createState() => _LoginViewState();
}

class _LoginViewState extends State<_LoginView> {
  final _email = TextEditingController();
  final _password = TextEditingController();

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  void _submit() => context.read<LoginCubit>().submit(email: _email.text, password: _password.text);

  @override
  Widget build(BuildContext context) {
    final state = context.watch<LoginCubit>().state;
    final message = state.failure?.message ?? context.select((SessionCubit c) => c.state.message);
    return Scaffold(
      body: SafeArea(
        child: AutofillGroup(
          child: ListView(
            padding: const EdgeInsets.all(AppSpacing.screen),
            children: [
              const SizedBox(height: AppSpacing.xxl * 2),
              const Wordmark(size: 36),
              const SizedBox(height: AppSpacing.xxl),
              Text('Inicia sesión', style: Theme.of(context).textTheme.headlineMedium),
              const SizedBox(height: AppSpacing.xl),
              AppTextField(
                label: 'Correo electrónico',
                controller: _email,
                keyboardType: TextInputType.emailAddress,
                autofillHints: const [AutofillHints.email],
                textInputAction: TextInputAction.next,
                enabled: !state.submitting,
              ),
              const SizedBox(height: AppSpacing.lg),
              AppPasswordField(controller: _password, enabled: !state.submitting, onSubmitted: (_) => _submit()),
              if (message != null) ...[
                const SizedBox(height: AppSpacing.md),
                Semantics(
                  liveRegion: true,
                  child: Text(message, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                ),
              ],
              const SizedBox(height: AppSpacing.xl),
              AppButton(label: 'Ingresar', loading: state.submitting, onPressed: _submit),
            ],
          ),
        ),
      ),
    );
  }
}
