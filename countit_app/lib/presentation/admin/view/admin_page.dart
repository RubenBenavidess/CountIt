import 'package:flutter/material.dart';

import '../../../app/theme/tokens.dart';

/// Placeholder for the admin area (F10 · COU-127): reachable only by admin and
/// superadmin, enforced by the router redirect.
class AdminPage extends StatelessWidget {
  const AdminPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Administración')),
      body: Padding(
        padding: const EdgeInsets.all(AppSpacing.screen),
        child: Text('Bancos, usuarios y auditoría llegarán en F10.', style: Theme.of(context).textTheme.bodySmall),
      ),
    );
  }
}
