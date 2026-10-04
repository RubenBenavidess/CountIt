import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme/tokens.dart';
import '../../notifications/cubit/notifications_cubit.dart';

/// Signed-in shell (COU-168): bottom navigation whose tabs keep their own
/// navigator and state (scroll position included) while switching:
/// «Inicio», «Movimientos» (every wallet), «Estadísticas», «Avisos» (with
/// the unread badge, COU-111) and «Perfil».
class AppShell extends StatelessWidget {
  const AppShell({super.key, required this.shell});

  final StatefulNavigationShell shell;

  /// Branch index of each tab (same order as the router's branches).
  static const homeTab = 0;
  static const movementsTab = 1;
  static const statisticsTab = 2;
  static const notificationsTab = 3;
  static const profileTab = 4;

  void _select(int index) =>
      // Tapping the current tab again goes back to its first screen.
      shell.goBranch(index, initialLocation: index == shell.currentIndex);

  @override
  Widget build(BuildContext context) {
    // Only the badge text rebuilds the bar, not every inbox change.
    final badge = context.select((NotificationsCubit c) => c.state.badgeLabel);
    // System back on another tab returns to «Inicio» before leaving the app.
    return PopScope(
      canPop: shell.currentIndex == homeTab,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) shell.goBranch(homeTab);
      },
      child: Scaffold(
        body: shell,
        bottomNavigationBar: NavigationBar(
          selectedIndex: shell.currentIndex,
          onDestinationSelected: _select,
          destinations: [
            const NavigationDestination(
              icon: Icon(Icons.home_outlined),
              selectedIcon: Icon(Icons.home_rounded),
              label: 'Inicio',
            ),
            const NavigationDestination(
              icon: Icon(Icons.receipt_long_outlined),
              selectedIcon: Icon(Icons.receipt_long_rounded),
              label: 'Movimientos',
            ),
            const NavigationDestination(
              icon: Icon(Icons.insights_outlined),
              selectedIcon: Icon(Icons.insights_rounded),
              label: 'Estadísticas',
            ),
            NavigationDestination(
              key: const ValueKey('tab-notifications'),
              icon: _BadgedIcon(Icons.notifications_none_rounded, badge: badge),
              selectedIcon: _BadgedIcon(Icons.notifications_rounded, badge: badge),
              label: 'Avisos',
              tooltip: badge == null ? 'Avisos' : 'Avisos: $badge sin leer',
            ),
            const NavigationDestination(
              icon: Icon(Icons.person_outline_rounded),
              selectedIcon: Icon(Icons.person_rounded),
              label: 'Perfil',
            ),
          ],
        ),
      ),
    );
  }
}

class _BadgedIcon extends StatelessWidget {
  const _BadgedIcon(this.icon, {required this.badge});

  final IconData icon;
  final String? badge;

  @override
  Widget build(BuildContext context) {
    final label = badge;
    // The tab reads «N sin leer» before its label; the digits are not read twice.
    return Semantics(
      label: label == null ? null : '$label sin leer',
      excludeSemantics: true,
      child: Badge(
        key: const ValueKey('notifications-badge'),
        isLabelVisible: label != null,
        label: Text(label ?? ''),
        backgroundColor: AppColors.lavender,
        textColor: AppColors.ink,
        child: Icon(icon),
      ),
    );
  }
}
