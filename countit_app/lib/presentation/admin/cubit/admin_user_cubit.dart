import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../app/errors/app_failure.dart';
import '../../../data/dtos/admin.dart';
import '../../../data/dtos/plan_offer.dart';
import '../../../data/repositories/admin_repository.dart';
import 'admin_failures.dart';

enum AdminUserAction { plan }

class AdminUserState extends Equatable {
  const AdminUserState({required this.user, this.busy, this.failure, this.done, this.assignment});

  final AdminUser user;

  /// The change in flight, if any (one at a time).
  final AdminUserAction? busy;

  /// Last failure, shown once (snackbar).
  final AppFailure? failure;

  /// The change that just succeeded, shown once (snackbar).
  final AdminUserAction? done;

  /// What the last plan change enforced.
  final PlanAssignment? assignment;

  @override
  List<Object?> get props => [user, busy, failure, done, assignment];
}

/// Detail of one user for administration (HU-28 · COU-202, COU-203): changes
/// the plan (superadmin only; the API answers 403 otherwise). Roles are not
/// changed from the app (contract 1.4): only the owner changes them in the
/// database.
class AdminUserCubit extends Cubit<AdminUserState> {
  AdminUserCubit(this._admin, {required AdminUser user, this.onForbidden}) : super(AdminUserState(user: user));

  final AdminRepository _admin;

  /// Called on 403 `forbidden`: our role may have changed (profile reload).
  final void Function()? onForbidden;

  /// First day accepted as `valid_until`: the API wants a date after its own
  /// today (UTC), and the user thinks in [today] (their zone).
  static DateTime firstValidUntil(DateTime today, {DateTime? nowUtc}) {
    final utc = (nowUtc ?? DateTime.now().toUtc());
    final utcToday = DateTime(utc.year, utc.month, utc.day);
    final base = utcToday.isAfter(today) ? utcToday : today;
    return DateTime(base.year, base.month, base.day + 1);
  }

  /// Local check that mirrors the API (400 `invalid_date`); null when valid.
  static String? validateValidUntil(DateTime? value, DateTime today, {DateTime? nowUtc}) {
    if (value == null) return 'Elige hasta cuándo rige el plan';
    final first = firstValidUntil(today, nowUtc: nowUtc);
    return value.isBefore(first) ? 'La fecha de vencimiento debe ser posterior a hoy' : null;
  }

  Future<bool> changePlan(PlanOffer offer, DateTime validUntil, {required DateTime today}) async {
    final invalid = validateValidUntil(validUntil, today);
    if (invalid != null) {
      emit(
        AdminUserState(
          user: state.user,
          failure: AppFailure(kind: FailureKind.validation, message: invalid),
        ),
      );
      return false;
    }
    return _run(AdminUserAction.plan, () async {
      final assignment = await _admin.setUserPlan(state.user.userId, planId: offer.planId, validUntil: validUntil);
      final user = state.user.copyWith(
        planId: assignment.planId,
        planName: assignment.planName,
        planValidUntil: assignment.validUntil,
      );
      return AdminUserState(user: user, done: AdminUserAction.plan, assignment: assignment);
    });
  }

  Future<bool> _run(AdminUserAction action, Future<AdminUserState> Function() request) async {
    if (state.busy != null) return false;
    emit(AdminUserState(user: state.user, busy: action, assignment: state.assignment));
    try {
      final next = await request();
      if (!isClosed) emit(next);
      return true;
    } on AppFailure catch (failure) {
      if (isClosed) return false;
      if (failure.kind == FailureKind.forbidden) onForbidden?.call();
      emit(AdminUserState(user: state.user, failure: adminFailure(failure), assignment: state.assignment));
      return false;
    }
  }
}
