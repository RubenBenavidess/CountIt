import 'dart:async';

import 'package:flutter/widgets.dart';

import '../../../app/errors/app_failure.dart';
import 'plan_upsell_sheet.dart';

/// Title of the sheet for a function the plan lacks (403 `feature_not_in_plan`).
const featureNotInPlanTitle = 'Tu plan no incluye esta función';

/// Shows the plans sheet for every `403 feature_not_in_plan` the API client
/// reports (COU-183, COU-61), whatever screen made the request. One sheet at
/// a time: answers arriving while it is open are dropped.
class PlanUpsellHost extends StatefulWidget {
  const PlanUpsellHost({super.key, required this.notices, required this.navigatorKey, required this.child});

  final Stream<AppFailure> notices;

  /// The root navigator: the sheet covers any screen, including pushed ones.
  final GlobalKey<NavigatorState> navigatorKey;
  final Widget child;

  @override
  State<PlanUpsellHost> createState() => _PlanUpsellHostState();
}

class _PlanUpsellHostState extends State<PlanUpsellHost> {
  StreamSubscription<AppFailure>? _subscription;
  bool _open = false;

  @override
  void initState() {
    super.initState();
    _subscription = widget.notices.listen((failure) => unawaited(_show(failure)));
  }

  @override
  void didUpdateWidget(PlanUpsellHost oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.notices != widget.notices) {
      unawaited(_subscription?.cancel());
      _subscription = widget.notices.listen((failure) => unawaited(_show(failure)));
    }
  }

  Future<void> _show(AppFailure failure) async {
    final context = widget.navigatorKey.currentContext;
    if (_open || context == null || !context.mounted) return;
    _open = true;
    try {
      await showPlanUpsell(context, title: featureNotInPlanTitle, message: failure.message);
    } finally {
      _open = false;
    }
  }

  @override
  void dispose() {
    unawaited(_subscription?.cancel());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
