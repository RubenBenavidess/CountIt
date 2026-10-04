import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:timezone/data/latest_10y.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

/// Dates in Spanish and in the user's own time zone.
///
/// The backend stores business dates as plain `date` values computed in the
/// user's zone (`private.user_today`); the app must use the same «today» or a
/// movement registered at 21:00 in Guayaquil would land on tomorrow (UTC).
abstract final class Dates {
  static const locale = 'es';
  static const defaultTimezone = 'America/Guayaquil';

  static bool _ready = false;

  /// Loads the time-zone database and the Spanish date symbols. Call once at
  /// start-up (tests call it in `setUpAll`).
  static Future<void> init() async {
    if (_ready) return;
    tzdata.initializeTimeZones();
    await initializeDateFormatting(locale);
    _ready = true;
  }

  static tz.Location _location(String? timezone) {
    try {
      return tz.getLocation(timezone ?? defaultTimezone);
    } on tz.LocationNotFoundException {
      return tz.getLocation(defaultTimezone);
    }
  }

  /// Calendar day in the user's zone (falls back to America/Guayaquil).
  static DateTime userToday(String? timezone, {DateTime? now}) {
    final local = tz.TZDateTime.from(now ?? DateTime.now(), _location(timezone));
    return DateTime(local.year, local.month, local.day);
  }

  /// A timestamp from the API (`timestamptz`) shown in the user's zone.
  static DateTime inUserZone(DateTime instant, String? timezone) {
    final t = tz.TZDateTime.from(instant, _location(timezone));
    return DateTime(t.year, t.month, t.day, t.hour, t.minute, t.second);
  }

  /// Parses an API `date` («2026-10-03») as a calendar day, never shifted by zones.
  static DateTime parseDay(String value) {
    final parts = value.split('-').map(int.parse).toList();
    return DateTime(parts[0], parts[1], parts[2]);
  }

  /// Formats a calendar day for the API («2026-10-03»).
  static String toApi(DateTime day) => DateFormat('yyyy-MM-dd').format(day);

  /// «3 oct 2026».
  static String date(DateTime day) => DateFormat('d MMM y', locale).format(day).replaceAll('.', '');

  /// «3 oct 2026, 21:05».
  static String dateTime(DateTime value) => '${date(value)}, ${DateFormat('HH:mm', locale).format(value)}';

  /// «octubre 2026».
  static String month(DateTime day) => DateFormat('MMMM y', locale).format(day);

  /// «Hoy», «Ayer», «30 sept» (same year) or «30 sept 2025» (intl es abbreviations).
  static String relative(DateTime day, {required DateTime today}) {
    final d = DateTime(day.year, day.month, day.day);
    final difference = DateTime(today.year, today.month, today.day).difference(d).inDays;
    if (difference == 0) return 'Hoy';
    if (difference == 1) return 'Ayer';
    if (d.year == today.year) return DateFormat('d MMM', locale).format(d).replaceAll('.', '');
    return date(d);
  }
}
