import 'package:intl/intl.dart';

/// Amount formatting and parsing for USD (Ecuador).
///
/// The design canvas writes amounts as `$3,836.80` (comma thousands, dot
/// decimals). COU-18 proposed the es-EC style `$1.234,56`; switching is a
/// one-line change of [_style] below.
abstract final class Money {
  static final NumberFormat _style = NumberFormat.currency(locale: 'en_US', symbol: r'$', decimalDigits: 2);

  /// U+2212 MINUS SIGN, as in the design («− $212»).
  static const minus = '−';

  /// `$1,234.50`; negatives as `−$1,234.50`.
  static String format(num amount) {
    final text = _style.format(amount.abs());
    return amount < 0 ? '$minus$text' : text;
  }

  /// With an explicit sign and a thin gap, for movements: `+ $450.00`, `− $212.00`.
  /// Zero has no sign. Colour never carries the meaning alone (design rule).
  static String signed(num amount, {required bool income}) {
    if (amount == 0) return format(0);
    return '${income ? '+' : minus} ${format(amount.abs())}';
  }

  /// Parses user input («1,234.5», «1234,50», «$ 20») into an amount with at
  /// most 2 decimals; null when it is not a valid positive or zero amount.
  static double? parse(String input) {
    var text = input.replaceAll(RegExp(r'[\s$]'), '');
    if (text.isEmpty) return null;
    final lastDot = text.lastIndexOf('.');
    final lastComma = text.lastIndexOf(',');
    if (lastDot >= 0 && lastComma >= 0) {
      // Both present: the last one is the decimal separator.
      final decimal = lastDot > lastComma ? '.' : ',';
      final grouping = decimal == '.' ? ',' : '.';
      text = text.replaceAll(grouping, '').replaceAll(decimal, '.');
    } else if (lastComma >= 0) {
      // Only commas: «1,234» groups thousands, «12,5» / «12,50» is a decimal.
      final decimals = text.length - lastComma - 1;
      text = (text.indexOf(',') == lastComma && decimals <= 2) ? text.replaceAll(',', '.') : text.replaceAll(',', '');
    }
    if (!RegExp(r'^\d+(\.\d{0,2})?$').hasMatch(text)) return null;
    return double.parse(text);
  }

  /// True when [amount] has more than 2 decimals (the API answers 400 invalid_amount).
  static bool hasTooManyDecimals(num amount) => (amount * 100 - (amount * 100).round()).abs() > 1e-6;
}
