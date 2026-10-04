import 'package:intl/intl.dart';

/// Amount formatting and parsing for USD (Ecuador).
///
/// Ecuadorian style agreed in COU-18: `$1.234,56` (dot thousands, comma
/// decimals, symbol first with no space). The API always uses a dot decimal;
/// this class is only for display and user input.
abstract final class Money {
  static final NumberFormat _style = NumberFormat('#,##0.00', 'es');
  static final _noise = RegExp(r'[\s$]');
  static final _amount = RegExp(r'^\d+(\.\d{0,2})?$');

  /// U+2212 MINUS SIGN, as in the design («− $212»).
  static const minus = '−';

  /// `$1.234,50`; negatives as `−$1.234,50`.
  static String format(num amount) {
    final text = '\$${_style.format(amount.abs())}';
    return amount < 0 ? '$minus$text' : text;
  }

  /// With an explicit sign and a thin gap, for movements: `+ $450,00`, `− $212,00`.
  /// Zero has no sign. Colour never carries the meaning alone (design rule).
  static String signed(num amount, {required bool income}) {
    if (amount == 0) return format(0);
    return '${income ? '+' : minus} ${format(amount.abs())}';
  }

  /// Parses user input («1.234,5», «1234.50», «$ 20») into an amount with at
  /// most 2 decimals; null when it is not a valid positive or zero amount.
  ///
  /// With a single kind of separator, one occurrence followed by 1–2 digits is
  /// the decimal mark (numeric keyboards may only offer «.»); otherwise it
  /// groups thousands.
  static double? parse(String input) {
    var text = input.replaceAll(_noise, '');
    if (text.isEmpty) return null;
    final lastDot = text.lastIndexOf('.');
    final lastComma = text.lastIndexOf(',');
    if (lastDot >= 0 && lastComma >= 0) {
      // Both present: the last one is the decimal separator.
      final decimal = lastDot > lastComma ? '.' : ',';
      final grouping = decimal == '.' ? ',' : '.';
      text = text.replaceAll(grouping, '').replaceAll(decimal, '.');
    } else if (lastComma >= 0 || lastDot >= 0) {
      final separator = lastComma >= 0 ? ',' : '.';
      final last = text.lastIndexOf(separator);
      final decimals = text.length - last - 1;
      final isDecimal = text.indexOf(separator) == last && decimals <= 2;
      text = isDecimal ? text.replaceAll(separator, '.') : text.replaceAll(separator, '');
    }
    if (!_amount.hasMatch(text)) return null;
    return double.parse(text);
  }

  /// True when [amount] has more than 2 decimals (the API answers 400 invalid_amount).
  static bool hasTooManyDecimals(num amount) => (amount * 100 - (amount * 100).round()).abs() > 1e-6;
}
