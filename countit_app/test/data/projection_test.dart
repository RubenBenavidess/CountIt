import 'package:countit_app/data/dtos/projection.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/projection_fixtures.dart';

void main() {
  group('WalletProjection.fromJson (COU-24)', () {
    test('balances in cents, today first, horizon as a calendar day', () {
      final projection = WalletProjection.fromJson(projectionJson());
      expect(projection.walletId, 4);
      expect(projection.currentBalanceCents, 125050);
      expect(projection.projectedBalanceCents, 175050);
      expect(projection.changeCents, 50000);
      expect(projection.until, DateTime(2026, 11, 5));
      expect(projection.points.first.date, DateTime(2026, 10, 4));
      expect(projection.points.first.hasMovements, isFalse);
      expect(projection.points[1].expenseCents, 40000);
      expect(projection.points[1].balanceCents, 85050);
    });

    test('movements leave out today\'s starting point', () {
      final projection = WalletProjection.fromJson(projectionJson());
      expect(projection.movements.map((p) => p.date), [DateTime(2026, 10, 5), DateTime(2026, 10, 31)]);
      expect(projection.isFlat, isFalse);
    });

    test('without running rules the balance stays flat', () {
      final projection = WalletProjection.fromJson(projectionJson(flat: true));
      expect(projection.isFlat, isTrue);
      expect(projection.movements, isEmpty);
      expect(projection.changeCents, 0);
    });
  });
}
