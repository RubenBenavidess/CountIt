import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../app/session/session_cubit.dart';
import '../../../../data/dtos/profile.dart';
import '../../../../shared/widgets/app_feedback.dart';
import '../../../../shared/widgets/app_layout.dart';

/// Second guard of the admin area (the router redirect is the first): the
/// [builder] only runs for a role that [allows]; anyone else gets a neutral
/// screen and the admin widgets are never built. The API checks the role on
/// every call anyway.
class RoleGuard extends StatelessWidget {
  const RoleGuard({super.key, required this.allows, required this.builder});

  /// Admin screens: [UserRole.canAdminister]; plans, roles and audit: superadmin.
  final bool Function(UserRole role) allows;
  final WidgetBuilder builder;

  static bool admin(UserRole role) => role.canAdminister;
  static bool superadmin(UserRole role) => role.isSuperadmin;

  @override
  Widget build(BuildContext context) {
    final role = context.select((SessionCubit c) => c.state.profile?.role);
    if (role != null && allows(role)) return builder(context);
    return const Scaffold(
      appBar: AppTopBar(),
      body: EmptyState(
        icon: Icons.lock_outline_rounded,
        title: 'Sin acceso',
        message: 'Esta sección no está disponible.',
      ),
    );
  }
}
