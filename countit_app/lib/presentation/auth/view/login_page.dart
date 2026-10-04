import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../app/errors/app_failure.dart';
import '../../../app/session/session_cubit.dart';
import '../../../app/theme/tokens.dart';
import '../../../data/repositories/auth_repository.dart';
import '../../../shared/widgets/app_button.dart';
import '../../../shared/widgets/app_fields.dart';
import '../../../shared/widgets/wordmark.dart';

/// Minimal working login to exercise the session flow end to end.
/// The designed screen, validations and captcha arrive in F02 (COU-84, COU-118).
class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await context.read<AuthRepository>().login(email: _email.text.trim(), password: _password.text);
      if (mounted) await context.read<SessionCubit>().refreshProfile();
    } on AppFailure catch (failure) {
      if (mounted) setState(() => _error = failure.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final sessionMessage = context.select((SessionCubit c) => c.state.message);
    final message = _error ?? sessionMessage;
    return Scaffold(
      body: SafeArea(
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
            ),
            const SizedBox(height: AppSpacing.lg),
            AppPasswordField(controller: _password, onSubmitted: (_) => _submit()),
            if (message != null) ...[
              const SizedBox(height: AppSpacing.md),
              Text(message, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ],
            const SizedBox(height: AppSpacing.xl),
            AppButton(label: 'Ingresar', loading: _busy, onPressed: _submit),
          ],
        ),
      ),
    );
  }
}
