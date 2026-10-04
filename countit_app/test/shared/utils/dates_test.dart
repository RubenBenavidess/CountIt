import 'package:countit_app/shared/utils/dates.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUpAll(Dates.init);

  group('userToday follows the profile time zone (COU-18)', () {
    // 03:30 UTC on 4 Oct = 22:30 on 3 Oct in Guayaquil (UTC-5).
    final instant = DateTime.utc(2026, 10, 4, 3, 30);

    test('Guayaquil is still the 3rd while UTC is the 4th', () {
      expect(Dates.userToday('America/Guayaquil', now: instant), DateTime(2026, 10, 3));
    });

    test('Madrid is already the 4th', () {
      expect(Dates.userToday('Europe/Madrid', now: instant), DateTime(2026, 10, 4));
    });

    test('unknown or missing zones fall back to Guayaquil', () {
      expect(Dates.userToday('Mars/Base', now: instant), DateTime(2026, 10, 3));
      expect(Dates.userToday(null, now: instant), DateTime(2026, 10, 3));
    });

    test('timestamps are shown in the user zone', () {
      expect(Dates.inUserZone(instant, 'America/Guayaquil'), DateTime(2026, 10, 3, 22, 30));
    });
  });

  group('API dates are calendar days', () {
    test('parse and format without zone shifts', () {
      final day = Dates.parseDay('2026-10-03');
      expect(day, DateTime(2026, 10, 3));
      expect(Dates.toApi(day), '2026-10-03');
    });
  });

  group('Spanish formats', () {
    final today = DateTime(2026, 10, 3);

    test('date, date-time and month', () {
      expect(Dates.date(DateTime(2026, 10, 3)), '3 oct 2026');
      expect(Dates.dateTime(DateTime(2026, 10, 3, 21, 5)), '3 oct 2026, 21:05');
      expect(Dates.month(DateTime(2026, 10, 3)), 'octubre 2026');
    });

    test('range: one year once, both years across a new year', () {
      expect(Dates.range(DateTime(2026, 10, 1), DateTime(2026, 10, 31)), '1 oct – 31 oct 2026');
      expect(Dates.range(DateTime(2026, 12, 15), DateTime(2027, 1, 14)), '15 dic 2026 – 14 ene 2027');
    });

    test('relative: today, yesterday, this year and older', () {
      expect(Dates.relative(today, today: today), 'Hoy');
      expect(Dates.relative(DateTime(2026, 10, 2), today: today), 'Ayer');
      expect(Dates.relative(DateTime(2026, 9, 30), today: today), '30 sept');
      expect(Dates.relative(DateTime(2025, 9, 30), today: today), '30 sept 2025');
    });

    test('dayHeader: today, yesterday, long date this year and with the year before', () {
      expect(Dates.dayHeader(DateTime(2026, 10, 3), today: today), 'Hoy');
      expect(Dates.dayHeader(DateTime(2026, 10, 2), today: today), 'Ayer');
      expect(Dates.dayHeader(DateTime(2026, 10, 1), today: today), 'Jueves, 1 de octubre');
      expect(Dates.dayHeader(DateTime(2025, 9, 30), today: today), 'Martes, 30 de septiembre de 2025');
      expect(Dates.long(DateTime(2026, 10, 1)), 'jueves, 1 de octubre de 2026');
    });
  });
}
