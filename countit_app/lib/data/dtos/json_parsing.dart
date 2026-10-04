/// Tolerant readers for PostgREST values shared by the DTOs.
library;

/// Money in integer cents. PostgREST sends `numeric` as a JSON number (or a
/// string for very large values); keeping cents avoids `0.1 + 0.2` noise in
/// sums and comparisons. Amounts in the API have at most 2 decimals.
abstract final class Cents {
  /// `1234.5` / `"1234.50"` → `123450`; null for null or unparseable values.
  static int? parse(Object? value) {
    final amount = switch (value) {
      num() => value.toDouble(),
      String() => double.tryParse(value.trim()),
      _ => null,
    };
    if (amount == null || amount.isNaN || amount.isInfinite) return null;
    return (amount * 100).round();
  }

  /// `123450` → `1234.5` (what the API expects and what [Money.format] shows).
  static double toAmount(int cents) => cents / 100;

  /// `1234.5` → `123450` (user input already limited to 2 decimals).
  static int fromAmount(num amount) => (amount * 100).round();
}

/// `#RRGGBB` (or `RRGGBB`) → opaque ARGB `0xFFRRGGBB`; null when missing or malformed.
int? parseHexColor(Object? value) {
  if (value is! String) return null;
  final hex = value.trim().replaceFirst('#', '');
  if (hex.length != 6) return null;
  final rgb = int.tryParse(hex, radix: 16);
  return rgb == null ? null : 0xFF000000 | rgb;
}

/// ISO timestamp → DateTime; null when missing or malformed.
DateTime? parseTimestamp(Object? value) => value is String ? DateTime.tryParse(value) : null;
