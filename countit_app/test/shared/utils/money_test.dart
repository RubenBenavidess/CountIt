import 'package:countit_app/shared/utils/money.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Money.format (COU-18: \$1.234,56)', () {
    test('zero, cents, thousands and large amounts', () {
      expect(Money.format(0), r'$0,00');
      expect(Money.format(0.5), r'$0,50');
      expect(Money.format(3836.8), r'$3.836,80');
      expect(Money.format(999999999999.99), r'$999.999.999.999,99');
    });

    test('negatives use the minus sign before the symbol', () {
      expect(Money.format(-212), '−\$212,00');
    });

    test('signed movements never rely on colour alone', () {
      expect(Money.signed(450, income: true), r'+ $450,00');
      expect(Money.signed(212, income: false), '− \$212,00');
      expect(Money.signed(0, income: true), r'$0,00');
    });
  });

  group('Money.parse', () {
    test('accepts dot or comma decimals and grouping', () {
      expect(Money.parse('20'), 20);
      expect(Money.parse('12.5'), 12.5);
      expect(Money.parse('12,50'), 12.5);
      expect(Money.parse(r'$ 1,234.56'), 1234.56);
      expect(Money.parse('1.234,56'), 1234.56);
      expect(Money.parse('1,234'), 1234);
      expect(Money.parse('1.234'), 1234);
      expect(Money.parse('1.234.567'), 1234567);
    });

    test('rejects more than 2 decimals, signs and text', () {
      expect(Money.parse('1.234,567'), isNull);
      expect(Money.parse('1,234.567'), isNull);
      expect(Money.parse('-5'), isNull);
      expect(Money.parse('abc'), isNull);
      expect(Money.parse(''), isNull);
    });

    test('hasTooManyDecimals matches the API rule', () {
      expect(Money.hasTooManyDecimals(10.55), isFalse);
      expect(Money.hasTooManyDecimals(10.555), isTrue);
      expect(Money.hasTooManyDecimals(0.1 + 0.2), isFalse, reason: 'floating point noise is not a third decimal');
    });
  });
}
