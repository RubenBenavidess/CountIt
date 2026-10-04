import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../data/dtos/profile.dart';
import '../errors/app_failure.dart';
import '../session/session_cubit.dart';

/// The single place where screens ask what the plan includes (COU-121).
///
/// Answers are *hints* from the plan `get_my_profile` returned: they hide a
/// form the API would refuse or explain a quota before the request. The API
/// always decides (403 `feature_not_in_plan`, 409 `<x>_limit_exceeded`);
/// without a known plan everything is allowed and the backend answers.
class PlanGate extends Equatable {
  const PlanGate(this.plan);

  final UserPlan? plan;

  /// [feature] is one of [PlanFeatures]; false only when the known plan lacks it.
  bool allows(String feature) => plan?.hasFeature(feature) ?? true;

  /// The quota of [limitation] (`max_wallets`…); null when unlimited or unknown.
  int? quota(String limitation) => plan?.quota(limitation);

  /// False only when [used] is known to fill the quota of [limitation].
  bool canAdd(String limitation, {required int? used}) {
    final limit = quota(limitation);
    return limit == null || used == null || used < limit;
  }

  @override
  List<Object?> get props => [plan];
}

extension PlanGateContext on BuildContext {
  /// The gate for one-off checks (button handlers): no rebuilds.
  PlanGate get planGate => PlanGate(read<SessionCubit>().state.profile?.plan);

  /// Whether the plan allows [feature], rebuilding only when that answer changes.
  bool watchPlanAllows(String feature) => select((SessionCubit c) => PlanGate(c.state.profile?.plan).allows(feature));
}

/// Global channel for `403 feature_not_in_plan` (COU-183, COU-61): the API
/// client reports every such answer and the app shows one plans sheet,
/// whatever screen made the request.
class PlanNotices {
  final _controller = StreamController<AppFailure>.broadcast();

  Stream<AppFailure> get featureNotInPlan => _controller.stream;

  void report(AppFailure failure) {
    if (!_controller.isClosed) _controller.add(failure);
  }

  Future<void> dispose() => _controller.close();
}
