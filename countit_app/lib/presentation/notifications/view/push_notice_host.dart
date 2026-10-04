import 'dart:async';

import 'package:flutter/material.dart';

import '../../../app/push/push_open_handler.dart';
import '../../../app/theme/tokens.dart';

/// Shows pushes received in the foreground as a snackbar with «Ver»
/// (COU-179): the system does not display them while the app is open.
class PushNoticeHost extends StatefulWidget {
  const PushNoticeHost({super.key, required this.notices, required this.onOpen, required this.child});

  final Stream<PushNotice> notices;

  /// Opens the notice's (already validated) location.
  final void Function(String location) onOpen;
  final Widget child;

  @override
  State<PushNoticeHost> createState() => _PushNoticeHostState();
}

class _PushNoticeHostState extends State<PushNoticeHost> {
  StreamSubscription<PushNotice>? _subscription;

  @override
  void initState() {
    super.initState();
    _subscription = widget.notices.listen(_show);
  }

  @override
  void didUpdateWidget(PushNoticeHost oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.notices != widget.notices) {
      unawaited(_subscription?.cancel());
      _subscription = widget.notices.listen(_show);
    }
  }

  void _show(PushNotice notice) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          key: const ValueKey('push-notice'),
          duration: const Duration(seconds: 6),
          content: Row(
            spacing: AppSpacing.md,
            children: [
              const Icon(Icons.notifications_active_outlined),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(notice.title, style: AppTypography.label, maxLines: 1, overflow: TextOverflow.ellipsis),
                    if (notice.body.isNotEmpty) Text(notice.body, maxLines: 2, overflow: TextOverflow.ellipsis),
                  ],
                ),
              ),
            ],
          ),
          action: SnackBarAction(label: 'Ver', onPressed: () => widget.onOpen(notice.location)),
        ),
      );
  }

  @override
  void dispose() {
    unawaited(_subscription?.cancel());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
