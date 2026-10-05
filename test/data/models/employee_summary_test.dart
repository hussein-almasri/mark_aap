import 'package:flutter_test/flutter_test.dart';
import 'package:mark_aap/data/models/employee_summary.dart';

void main() {
  test('EmployeeSummary holds employee list row values', () {
    const employee = EmployeeSummary(
      uid: 'employee-1',
      name: 'Example Employee',
      email: 'employee@example.com',
      isActive: true,
    );

    expect(employee.uid, 'employee-1');
    expect(employee.name, 'Example Employee');
    expect(employee.email, 'employee@example.com');
    expect(employee.isActive, isTrue);
  });
}
