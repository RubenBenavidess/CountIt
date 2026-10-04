import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../app/push/push_messaging.dart';
import '../../../../app/theme/tokens.dart';
import '../../../../shared/platform/notification_permission.dart';
import '../../../../shared/widgets/app_button.dart';
import '../../../../shared/widgets/app_feedback.dart';

/// Asks for the notifications permission where it makes sense (COU-175):
/// in the inbox, after signing in, never at start-up. Hidden while push is
/// not configured, once granted, or after «Ahora no».
class PushPermissionCard extends StatefulWidget {
  const PushPermissionCard({super.key});

  @override
  State<PushPermissionCard> createState() => _PushPermissionCardState();
}

class _PushPermissionCardState extends State<PushPermissionCard> {
  NotificationPermissionStatus? _status;
  bool _dismissed = false;
  bool _busy = false;

  // Back from the system settings: the switch may have changed.
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(onResume: () => unawaited(_refresh()));
    unawaited(_refresh());
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    if (!context.read<PushMessaging>().isAvailable) return;
    final status = await context.read<NotificationPermission>().status();
    if (mounted) setState(() => _status = status);
  }

  Future<void> _request() async {
    setState(() => _busy = true);
    final status = await context.read<NotificationPermission>().request();
    if (!mounted) return;
    setState(() {
      _status = status;
      _busy = false;
    });
  }

  Future<void> _openSettings() => context.read<NotificationPermission>().openSettings();

  @override
  Widget build(BuildContext context) {
    final status = _status;
    if (_dismissed ||
        status == null ||
        status == NotificationPermissionStatus.granted ||
        status == NotificationPermissionStatus.unsupported) {
      return const SizedBox.shrink();
    }
    final denied = status == NotificationPermissionStatus.denied;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: NoteCard(
        key: const ValueKey('push-permission-card'),
        icon: Icons.notifications_active_outlined,
        message: denied
            ? 'Las notificaciones están desactivadas. Actívalas en Ajustes para enterarte de invitaciones, '
                  'presupuestos y pagos programados aunque no tengas la app abierta.'
            : 'Activa las notificaciones para enterarte de invitaciones, presupuestos y pagos programados '
                  'aunque no tengas la app abierta.',
        action: Wrap(
          spacing: AppSpacing.sm,
          children: [
            AppButton(
              label: denied ? 'Abrir ajustes' : 'Activar',
              expand: false,
              loading: _busy,
              onPressed: _busy ? null : () => unawaited(denied ? _openSettings() : _request()),
            ),
            AppButton(
              label: 'Ahora no',
              expand: false,
              variant: AppButtonVariant.ghost,
              onPressed: () => setState(() => _dismissed = true),
            ),
          ],
        ),
      ),
    );
  }
}
