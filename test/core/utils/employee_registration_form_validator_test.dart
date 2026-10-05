import 'package:flutter_test/flutter_test.dart';
import 'package:mark_aap/core/utils/employee_registration_form_validator.dart';

void main() {
  const validator = EmployeeRegistrationFormValidator();

  group('EmployeeRegistrationFormValidator', () {
    test('requires a non-empty full name', () {
      expect(validator.validateName('  '), isNotNull);
      expect(validator.validateName('Ali Hassan'), isNull);
    });

    test('requires a valid email address', () {
      expect(validator.validateEmail(''), isNotNull);
      expect(validator.validateEmail('ali@example.com'), isNull);
      expect(validator.validateEmail('not-an-email'), isNotNull);
    });

    test('uses the existing minimum password length of six', () {
      expect(validator.validatePassword('12345'), isNotNull);
      expect(validator.validatePassword('123456'), isNull);
    });

    test('requires matching password confirmation', () {
      expect(validator.validatePasswordConfirmation('', 'secret1'), isNotNull);
      expect(
        validator.validatePasswordConfirmation('secret2', 'secret1'),
        isNotNull,
      );
      expect(
        validator.validatePasswordConfirmation('secret1', 'secret1'),
        isNull,
      );
    });

    test('requires the standard grouped Join Code format', () {
      expect(validator.validateJoinCode(''), isNotNull);
      expect(validator.validateJoinCode('SMAE-S9H4-LQ78-XCCY'), isNull);
      expect(validator.validateJoinCode('SMAES9H4-LQ78-XCCY'), isNotNull);
    });
  });
}
