import 'money.dart';

/// Form validators that mirror the backend rules (CountIt-Backend-Dev
/// `register` DTO, `__shared/validation/password.ts`, `update_my_profile`).
/// The server validates again; these only give immediate feedback.
///
/// Each returns null when the value is valid, else the Spanish message, so
/// they plug straight into `TextFormField.validator`.
abstract final class Validators {
  static const requiredMessage = 'Este campo no puede quedar vacío';

  static final _email = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$');
  static final _username = RegExp(r'^[A-Za-z0-9_-]+$');
  static final _personName = RegExp(r"^\p{L}[\p{L}' -]*$", unicode: true);

  /// A required name of at most [max] characters (the API's `max_length` message).
  static String? name(String? value, {required int max}) {
    final missing = required(value);
    if (missing != null) return missing;
    return value!.trim().length > max ? 'Máximo de caracteres alcanzado ($max) en el nombre' : null;
  }

  /// The API bound for amounts: `0 < amount < 1.000.000.000.000`.
  static const maxAmountCents = 100000000000000;

  /// An amount as typed («1.234,5»): required, at most 2 decimals, within
  /// the API range (400 `invalid_amount` otherwise).
  static String? amount(String? value) {
    final text = value?.trim() ?? '';
    if (text.isEmpty) return requiredMessage;
    final parsed = Money.parse(text);
    if (parsed == null || Money.hasTooManyDecimals(parsed)) return 'Ingresa un monto válido, con hasta 2 decimales';
    final cents = (parsed * 100).round();
    return cents <= 0 || cents >= maxAmountCents ? 'El monto debe ser mayor que 0 y menor que 1.000.000.000.000' : null;
  }

  /// Cents of a valid [amount] text; null otherwise.
  static int? amountCents(String text) => amount(text) == null ? (Money.parse(text.trim())! * 100).round() : null;

  static String? required(String? value) => (value == null || value.trim().isEmpty) ? requiredMessage : null;

  static String? email(String? value) {
    final text = value?.trim() ?? '';
    if (text.isEmpty) return requiredMessage;
    if (text.length > 255) return 'Máximo de caracteres alcanzado (255)';
    return _email.hasMatch(text) ? null : 'El correo electrónico no es válido';
  }

  /// 5–12 letters, digits, `-` or `_`; the `del_` prefix is reserved for deleted accounts.
  static String? username(String? value) {
    final text = value?.trim() ?? '';
    if (text.isEmpty) return requiredMessage;
    if (text.length < 5) return 'El nombre de usuario debe tener al menos 5 caracteres';
    if (text.length > 12) return 'El nombre de usuario no puede exceder 12 caracteres';
    if (!_username.hasMatch(text)) {
      return 'El nombre de usuario solo puede contener letras, números, guiones y guiones bajos';
    }
    if (text.toLowerCase().startsWith('del_')) return 'Ese nombre de usuario no está disponible';
    return null;
  }

  /// First or last name: letters, spaces, apostrophes and hyphens, up to 40.
  static String? personName(String? value, {String label = 'nombre'}) {
    final text = value?.trim() ?? '';
    if (text.isEmpty) return requiredMessage;
    if (text.length > 40) return 'Máximo de caracteres alcanzado (40)';
    return _personName.hasMatch(text) ? null : 'El $label solo puede contener letras, espacios, apóstrofos y guiones';
  }

  /// A password the user already has (login, reauthentication): presence and bcrypt length only.
  static String? existingPassword(String? value) {
    if (value == null || value.isEmpty) return requiredMessage;
    return value.length > 72 ? 'Máximo de caracteres alcanzado (72)' : null;
  }

  /// A new password: the Supabase Auth policy (8–72, upper, lower and digit).
  static String? newPassword(String? value) {
    final text = value ?? '';
    if (text.isEmpty) return requiredMessage;
    if (text.length > 72) return 'La contraseña no puede exceder 72 caracteres';
    final unmet = PasswordRule.values.where((rule) => !rule.isMetBy(text));
    return unmet.isEmpty ? null : unmet.first.error;
  }

  /// Validator for a «repeat the password» field.
  static String? Function(String?) matches(String Function() other) =>
      (value) => (value ?? '').isEmpty
      ? requiredMessage
      : value == other()
      ? null
      : 'Las contraseñas no coinciden';
}

/// The password policy as a checklist (shown live under new-password fields).
enum PasswordRule {
  length('8 caracteres o más', 'La contraseña debe tener al menos 8 caracteres'),
  mixedCase('Mayúscula y minúscula', 'La contraseña debe tener una letra mayúscula y una minúscula'),
  digit('Al menos un número', 'La contraseña debe contener al menos un número');

  const PasswordRule(this.label, this.error);

  final String label;
  final String error;

  static final _upper = RegExp('[A-Z]');
  static final _lower = RegExp('[a-z]');
  static final _digit = RegExp('[0-9]');

  bool isMetBy(String password) => switch (this) {
    length => password.length >= 8,
    mixedCase => _upper.hasMatch(password) && _lower.hasMatch(password),
    digit => _digit.hasMatch(password),
  };
}

/// `maria@correo.ec` → `m•••@correo.ec`: confirms where the e-mail went without
/// putting the whole address on screen (COU-110).
String maskEmail(String email) {
  final at = email.indexOf('@');
  if (at <= 0) return email;
  return '${email[0]}•••${email.substring(at)}';
}
