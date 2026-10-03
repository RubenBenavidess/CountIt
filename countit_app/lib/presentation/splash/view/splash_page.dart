import 'package:flutter/material.dart';

import '../../../app/config/app_config.dart';
import '../../../app/theme/tokens.dart';
import '../../../shared/widgets/wordmark.dart';

/// Entry screen. Session restore and routing arrive with the data layer (F01/F02).
class SplashPage extends StatelessWidget {
  const SplashPage({super.key, required this.environment});

  final AppEnvironment environment;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            spacing: AppSpacing.md,
            children: [
              const Wordmark(size: 44),
              Text('Cuéntalo todo.', style: Theme.of(context).textTheme.bodySmall),
              if (environment != AppEnvironment.prod)
                Text(environment.name.toUpperCase(), style: Theme.of(context).textTheme.labelSmall),
            ],
          ),
        ),
      ),
    );
  }
}
