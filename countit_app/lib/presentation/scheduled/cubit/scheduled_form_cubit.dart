import 'package:intl/intl.dart';

import '../../../data/dtos/scheduled_transaction.dart';
import '../../../data/repositories/scheduled_transaction_repository.dart';
import '../../../shared/state/submit_cubit.dart';
import '../../../shared/utils/validators.dart';

/// One form for scheduling and editing rules (HU-16/HU-20 · COU-89,
/// COU-151, COU-152).
///
/// Editing sends the whole form ([ScheduledTransactionInput]):
/// `update_scheduled_transaction` replaces the editable fields (an omitted
/// budget or end date is cleared) and keeps the start date. Editing never
/// asks for the password; only deleting does.
class ScheduledFormCubit extends SubmitCubit {
  ScheduledFormCubit(this._scheduled, {required this.walletId, this.scheduledTransactionId});

  final ScheduledTransactionRepository _scheduled;
  final int walletId;

  /// The rule being edited; null when scheduling a new one.
  final int? scheduledTransactionId;

  bool get isEditing => scheduledTransactionId != null;

  /// The rule as the API left it after the last successful save.
  ScheduledTransaction? saved;

  Future<bool> save(ScheduledTransactionInput input) => submit(() async {
    final id = scheduledTransactionId;
    saved = id == null ? await _scheduled.create(walletId, input) : await _scheduled.update(id, input);
  });
}

/// Client-side mirror of `create_scheduled_transaction`,
/// `update_scheduled_transaction` and `private.validate_schedule_fields`:
/// the server validates again, these only give immediate feedback. Each
/// returns null when valid, else the Spanish message of the API.
abstract final class ScheduledValidators {
  static const nameMax = 100;
  static const intervalMin = 1;
  static const intervalMax = 365;

  static String? name(String? value) => Validators.name(value, max: nameMax);

  static String? amount(String? value) => Validators.amount(value);

  /// The first run must be after the user's own calendar day (400 `invalid_start_date`).
  static String? startDate(DateTime day, {required DateTime today}) =>
      day.isAfter(today) ? null : 'La fecha programada debe ser posterior a hoy';

  /// «Cada N»: a whole number from 1 to 365 (400 `invalid_interval`).
  static String? interval(String? value) {
    final text = value?.trim() ?? '';
    if (text.isEmpty) return Validators.requiredMessage;
    final n = int.tryParse(text);
    return n == null || n < intervalMin || n > intervalMax ? 'El intervalo debe estar entre 1 y 365' : null;
  }

  /// The end (optional, recurring rules only) can be neither before the
  /// start nor, when editing without a new cadence, before the next run
  /// (400 `invalid_date_range`).
  static String? endDate(
    Periodicity periodicity, {
    required DateTime start,
    required DateTime? end,
    DateTime? nextRun,
  }) {
    if (!periodicity.recurs || end == null) return null;
    if (end.isBefore(start)) return 'La fecha de fin no puede ser anterior a la de inicio';
    if (nextRun != null && end.isBefore(nextRun)) {
      return 'La fecha de fin no puede ser anterior a la próxima ejecución (${DateFormat('dd/MM/yyyy').format(nextRun)})';
    }
    return null;
  }

  /// A recurring rule that already started cannot become one-time (400
  /// `invalid_periodicity`): the API has no later single occurrence for it.
  static bool canBecomeOneTime(ScheduledTransaction? rule, {required DateTime today}) =>
      rule == null || !rule.periodicity.recurs || rule.startDate.isAfter(today);
}
