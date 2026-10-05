import 'join_code.dart';

/// Local validation shared by the employee registration form and its tests.
class EmployeeRegistrationFormValidator {
  const EmployeeRegistrationFormValidator();

  static const int minimumPasswordLength = 6;
  static final RegExp _emailPattern = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

  String? validateName(String? value) =>
      value == null || value.trim().isEmpty ? 'أدخل الاسم الكامل' : null;

  String? validateEmail(String? value) {
    if (value == null || value.trim().isEmpty) return 'أدخل البريد الإلكتروني';
    if (!_emailPattern.hasMatch(value.trim())) {
      return 'أدخل بريدًا إلكترونيًا صحيحًا';
    }
    return null;
  }

  String? validatePassword(String? value) {
    if (value == null || value.isEmpty) return 'أدخل كلمة المرور';
    if (value.length < minimumPasswordLength) {
      return 'كلمة المرور يجب أن تكون 6 أحرف على الأقل';
    }
    return null;
  }

  String? validatePasswordConfirmation(String? value, String password) {
    if (value == null || value.isEmpty) return 'أكد كلمة المرور';
    if (value != password) return 'كلمتا المرور غير متطابقتين';
    return null;
  }

  String? validateJoinCode(String? value) {
    if (value == null || value.trim().isEmpty) return 'أدخل كود الانضمام';
    if (!JoinCode.isValidFormat(value)) return 'صيغة كود الانضمام غير صحيحة';
    return null;
  }
}
