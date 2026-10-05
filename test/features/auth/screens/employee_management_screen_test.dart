import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mark_aap/data/models/employee_summary.dart';
import 'package:mark_aap/data/models/user_model.dart';
import 'package:mark_aap/data/repositories/employee_repository.dart';
import 'package:mark_aap/features/auth/screens/employee_management_screen.dart';

class _FakeEmployeeRepository implements EmployeeRepository {
  _FakeEmployeeRepository(this.employees);

  List<EmployeeSummary> employees;
  final statusChanges = <(String, String, bool)>[];

  @override
  Future<List<EmployeeSummary>> listEmployees(String storeId) async =>
      employees;

  @override
  Future<void> setEmployeeActive(
    String storeId,
    String employeeUid,
    bool isActive,
  ) async {
    statusChanges.add((storeId, employeeUid, isActive));
    employees = employees
        .map(
          (employee) => employee.uid == employeeUid
              ? EmployeeSummary(
                  uid: employee.uid,
                  name: employee.name,
                  email: employee.email,
                  isActive: isActive,
                )
              : employee,
        )
        .toList();
  }
}

const _admin = UserModel(
  uid: 'admin-1',
  storeId: 'store-1',
  name: 'Store Admin',
  email: 'admin@example.com',
  role: 'ADMIN',
  isActive: true,
);

Widget _screen(_FakeEmployeeRepository repository) => MaterialApp(
  home: EmployeeManagementScreen(user: _admin, repository: repository),
);

void main() {
  testWidgets('renders employee details, status, and available status action', (
    tester,
  ) async {
    final repository = _FakeEmployeeRepository([
      const EmployeeSummary(
        uid: 'active-employee',
        name: 'Active Employee',
        email: 'active@example.com',
        isActive: true,
      ),
      const EmployeeSummary(
        uid: 'inactive-employee',
        name: 'Inactive Employee',
        email: 'inactive@example.com',
        isActive: false,
      ),
    ]);
    await tester.pumpWidget(_screen(repository));
    await tester.pumpAndSettle();

    expect(find.text('Active Employee'), findsOneWidget);
    expect(find.text('active@example.com'), findsOneWidget);
    expect(find.text('نشط'), findsOneWidget);
    expect(find.text('Inactive Employee'), findsOneWidget);
    expect(find.text('inactive@example.com'), findsOneWidget);
    expect(find.text('غير نشط'), findsOneWidget);
    expect(find.text('إيقاف'), findsOneWidget);
    expect(find.text('إعادة تفعيل'), findsOneWidget);
    expect(find.text('تعديل الدور'), findsNothing);
    expect(find.text('حذف الموظف'), findsNothing);
  });

  testWidgets('requires confirmation and sends selected UID and active value', (
    tester,
  ) async {
    final repository = _FakeEmployeeRepository([
      const EmployeeSummary(
        uid: 'selected-employee',
        name: 'Selected Employee',
        email: 'selected@example.com',
        isActive: true,
      ),
    ]);
    await tester.pumpWidget(_screen(repository));
    await tester.pumpAndSettle();

    await tester.tap(find.text('إيقاف'));
    await tester.pumpAndSettle();
    expect(find.text('إيقاف الموظف؟'), findsOneWidget);
    expect(repository.statusChanges, isEmpty);

    await tester.tap(find.text('إلغاء'));
    await tester.pumpAndSettle();
    expect(repository.statusChanges, isEmpty);
    expect(find.text('نشط'), findsOneWidget);

    await tester.tap(find.text('إيقاف'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'إيقاف'));
    await tester.pumpAndSettle();

    expect(repository.statusChanges, [('store-1', 'selected-employee', false)]);
    expect(find.text('غير نشط'), findsOneWidget);
    expect(find.text('إعادة تفعيل'), findsOneWidget);
  });
}
