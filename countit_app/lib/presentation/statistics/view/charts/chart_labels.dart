import 'dart:math' as math;

import 'package:intl/intl.dart';

import '../../../../data/dtos/statistics.dart';
import '../../../../shared/utils/dates.dart';

final _dayMonth = DateFormat('d MMM', Dates.locale);
final _monthYear = DateFormat('MMM y', Dates.locale);

String _clean(String text) => text.replaceAll('.', '');

/// Name of a bucket: «5 sept 2026», «Semana del 6 jul 2026», «octubre 2026».
/// [short] is the axis variant: «5 sept», «6 jul», «oct 2026».
String bucketLabel(StatisticsBucket bucket, DateTime start, {bool short = false}) => switch (bucket) {
  StatisticsBucket.day => short ? _clean(_dayMonth.format(start)) : Dates.date(start),
  StatisticsBucket.week => short ? _clean(_dayMonth.format(start)) : 'Semana del ${Dates.date(start)}',
  StatisticsBucket.month => short ? _clean(_monthYear.format(start)) : Dates.month(start),
};

/// Smallest «round» amount (1, 2, 2,5 or 5 × 10ⁿ cents) at or above
/// [cents], so the axis reads `$500` instead of `$487,30`. Never below $1.
int niceCeiling(int cents) {
  if (cents <= 100) return 100;
  final magnitude = math.pow(10, (math.log(cents) / math.ln10).floor()).toInt();
  for (final step in const [1.0, 2.0, 2.5, 5.0, 10.0]) {
    final candidate = (step * magnitude).round();
    if (candidate >= cents) return candidate;
  }
  return 10 * magnitude;
}
