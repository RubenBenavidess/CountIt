import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router/app_router.dart';
import '../../../app/session/session_cubit.dart';
import '../../../app/theme/tokens.dart';
import '../../../shared/widgets/wordmark.dart';

/// Placeholder home: proves the session, profile and role wiring until the
/// wallets home lands (F03 · COU-168).
class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    final profile = context.select((SessionCubit c) => c.state.profile);
    final textTheme = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(
        title: const Wordmark(size: 24),
        actions: [
          IconButton(
            tooltip: 'Perfil',
            icon: const Icon(Icons.person_outline_rounded),
            onPressed: () => context.push(AppRoutes.profile),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.screen),
        children: [
          Text('Hola, ${profile?.displayName ?? ''}', style: textTheme.headlineMedium),
          const SizedBox(height: AppSpacing.sm),
          Text('Plan ${profile?.plan?.name ?? '—'}', style: textTheme.bodySmall),
          if (profile?.role.canAdminister ?? false) ...[
            const SizedBox(height: AppSpacing.xl),
            OutlinedButton(onPressed: () => context.push(AppRoutes.admin), child: const Text('Administración')),
          ],
        ],
      ),
    );
  }
}
