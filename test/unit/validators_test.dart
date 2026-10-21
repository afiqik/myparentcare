import 'package:flutter_test/flutter_test.dart';
import 'package:my_parent_care/security/input_validator.dart';

void main() {
  test('emel', () {
    expect(InputValidator.validateEmail(''), 'Email is required');
    expect(InputValidator.validateEmail('invalid-email'), isNotNull);
    expect(InputValidator.validateEmail('a@b'), isNotNull);
    expect(InputValidator.validateEmail('test@kptm.edu.my'), isNull);
    expect(InputValidator.validateEmail(' spaced@example.com '), isNull);
  });

  test('telefon, matrik & medan wajib', () {
    expect(InputValidator.validatePhone('123'), isNotNull);
    expect(InputValidator.validatePhone('012-345 6789'), isNull);
    expect(InputValidator.validateMatricNo('123'), 'Matric number is too short');
    expect(InputValidator.validateMatricNo('KPTM12345'), isNull);
    expect(InputValidator.validateRequired('x' * 121, 'Title'), contains('120'));
  });

  test('pautan video mesti https', () {
    expect(InputValidator.validateVideoUrl('http://youtube.com/x'), isNotNull);
    expect(InputValidator.validateVideoUrl('javascript:alert(1)'), isNotNull);
    expect(InputValidator.validateVideoUrl('https://youtu.be/abc'), isNull);
  });
}
