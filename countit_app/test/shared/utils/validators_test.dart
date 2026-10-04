import 'package:countit_app/shared/utils/validators.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('required fields use the backend message', () {
    expect(Validators.required('  '), 'Este campo no puede quedar vacío');
    expect(Validators.required('x'), isNull);
  });

  test('e-mail', () {
    expect(Validators.email('maria@correo.ec'), isNull);
    expect(Validators.email(' maria@correo.ec '), isNull);
    expect(Validators.email('maria@correo'), isNotNull);
    expect(Validators.email('maria correo@x.ec'), isNotNull);
    expect(Validators.email(''), Validators.requiredMessage);
  });

  test('username: 5–12 of [A-Za-z0-9_-], del_ reserved', () {
    expect(Validators.username('mariaq'), isNull);
    expect(Validators.username('ma_ri-a2'), isNull);
    expect(Validators.username('mar'), contains('al menos 5'));
    expect(Validators.username('mariaquishpe1'), contains('exceder 12'));
    expect(Validators.username('maría'), contains('solo puede contener'));
    expect(Validators.username('maria q'), contains('solo puede contener'));
    expect(Validators.username('DEL_ana'), 'Ese nombre de usuario no está disponible');
  });

  test('person names accept accents, apostrophes and hyphens', () {
    expect(Validators.personName('María José'), isNull);
    expect(Validators.personName("D'Ambrosio"), isNull);
    expect(Validators.personName('Ruiz-Peña'), isNull);
    expect(Validators.personName('R2D2'), isNotNull);
    expect(Validators.personName('a' * 41), 'Máximo de caracteres alcanzado (40)');
  });

  test('new password follows the Auth policy', () {
    expect(Validators.newPassword('Quito2026'), isNull);
    expect(Validators.newPassword('Quito26'), PasswordRule.length.error);
    expect(Validators.newPassword('quito2026'), PasswordRule.mixedCase.error);
    expect(Validators.newPassword('QuitoQuito'), PasswordRule.digit.error);
    expect(Validators.newPassword('Aa1${'x' * 70}'), contains('72'));
  });

  test('confirmation must match', () {
    final validate = Validators.matches(() => 'Quito2026');
    expect(validate('Quito2026'), isNull);
    expect(validate('Quito2027'), 'Las contraseñas no coinciden');
    expect(validate(''), Validators.requiredMessage);
  });

  test('maskEmail', () {
    expect(maskEmail('maria@correo.ec'), 'm•••@correo.ec');
    expect(maskEmail('sin-arroba'), 'sin-arroba');
  });
}
