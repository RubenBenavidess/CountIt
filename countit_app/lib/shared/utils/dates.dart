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

  // Built on first use (after [init] loaded the Spanish symbols) and reused:
  // lists format many dates per frame and a DateFormat parses its pattern
  // when created.
  static final _api = DateFormat('yyyy-MM-dd', 'en_US');
  static final _dayMonthYear = DateFormat('d MMM y', locale);
  static final _dayMonth = DateFormat('d MMM', locale);
  static final _hourMinute = DateFormat('HH:mm', locale);
  static final _monthYear = DateFormat('MMMM y', locale);
  static final _weekdayDayMonth = DateFormat("EEEE, d 'de' MMMM", locale);
  static final _weekdayDayMonthYear = DateFormat("EEEE, d 'de' MMMM 'de' y", locale);

  /// Formats a calendar day for the API («2026-10-03»).
  static String toApi(DateTime day) => _api.format(day);

  /// «3 oct 2026».
  static String date(DateTime day) => _dayMonthYear.format(day).replaceAll('.', '');

  /// «3 oct 2026, 21:05».
  static String dateTime(DateTime value) => '${date(value)}, ${_hourMinute.format(value)}';

  /// «21:05».
  static String time(DateTime value) => _hourMinute.format(value);

  /// «1 oct – 31 oct 2026»; the year on both ends when they differ
  /// («15 dic 2026 – 14 ene 2027»).
  static String range(DateTime start, DateTime end) {
    if (start.year != end.year) return '${date(start)} – ${date(end)}';
    final first = _dayMonth.format(start).replaceAll('.', '');
    return '$first – ${date(end)}';
  }

  /// «octubre 2026».
  static String month(DateTime day) => _monthYear.format(day);

  /// «jueves, 1 de octubre de 2026» (screen readers, detail screens).
  static String long(DateTime day) => _weekdayDayMonthYear.format(day);

  /// Header of a day in a list: «Hoy», «Ayer», «Jueves, 1 de octubre» (this
  /// year) or «Martes, 30 de septiembre de 2025».
  static String dayHeader(DateTime day, {required DateTime today}) {
    final d = DateTime(day.year, day.month, day.day);
    // UTC midnights: a daylight-saving change on the device never makes a day 23 h long.
    final difference = DateTime.utc(
      today.year,
      today.month,
      today.day,
    ).difference(DateTime.utc(d.year, d.month, d.day)).inDays;
    if (difference == 0) return 'Hoy';
    if (difference == 1) return 'Ayer';
    final text = (d.year == today.year ? _weekdayDayMonth : _weekdayDayMonthYear).format(d);
    return '${text[0].toUpperCase()}${text.substring(1)}';
  }

  /// «Hoy», «Ayer», «30 sept» (same year) or «30 sept 2025» (intl es abbreviations).
  static String relative(DateTime day, {required DateTime today}) {
    final d = DateTime(day.year, day.month, day.day);
    final difference = DateTime(today.year, today.month, today.day).difference(d).inDays;
    if (difference == 0) return 'Hoy';
    if (difference == 1) return 'Ayer';
    if (d.year == today.year) return _dayMonth.format(d).replaceAll('.', '');
    return date(d);
  }
}
