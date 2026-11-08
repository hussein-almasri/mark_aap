import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mark_aap/data/models/user_model.dart';
import 'package:mark_aap/features/auth/screens/admin_dashboard.dart';
import 'package:mark_aap/features/auth/screens/employee_dashboard.dart';

void main() {
  const admin = UserModel(
    uid: 'admin-1',
    storeId: 'store-1',
    name: 'مدير المتجر',
    email: 'admin@example.com',
    role: 'ADMIN',
    isActive: true,
  );
  const employee = UserModel(
    uid: 'employee-1',
    storeId: 'store-1',
    name: 'موظف المتجر',
    email: 'employee@example.com',
    role: 'EMPLOYEE',
    isActive: true,
  );

  testWidgets('admin menu retains management-only destinations', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        locale: Locale('ar'),
        supportedLocales: [Locale('ar')],
        localizationsDelegates: [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: AdminDashboard(user: admin),
      ),
    );

    expect(find.text('الرئيسية'), findsOneWidget);
    expect(find.text('الشركات'), findsOneWidget);
    expect(find.text('المنتجات'), findsWidgets);
    await tester.tap(find.text('المزيد'));
    await tester.pumpAndSettle();

    expect(find.text('إدارة الشركات'), findsOneWidget);
    expect(find.text('إدارة الموظفين'), findsOneWidget);
    expect(find.text('كود انضمام الموظفين'), findsOneWidget);
    expect(find.text('إدارة العملاء'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('سجل العمليات'),
      250,
      scrollable: find.byType(Scrollable).last,
    );
    expect(find.text('سجل العمليات'), findsOneWidget);
  });

  testWidgets('employee menu excludes admin-only destinations', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        locale: Locale('ar'),
        supportedLocales: [Locale('ar')],
        localizationsDelegates: [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: EmployeeDashboard(user: employee),
      ),
    );

    expect(find.text('الموردون'), findsOneWidget);
    await tester.tap(find.text('المزيد'));
    await tester.pumpAndSettle();

    expect(find.text('إدارة الموظفين'), findsNothing);
    expect(find.text('إدارة الشركات'), findsNothing);
    expect(find.text('كود انضمام الموظفين'), findsNothing);
    expect(find.text('فواتير المشتريات'), findsOneWidget);
    expect(find.text('صندوق النقد'), findsOneWidget);
    expect(find.text('بيانات المتجر'), findsOneWidget);
  });

  testWidgets('shell preserves RTL and compact-width layout', (tester) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      const MaterialApp(
        locale: Locale('ar'),
        supportedLocales: [Locale('ar')],
        localizationsDelegates: [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: AdminDashboard(user: admin),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(
      Directionality.of(tester.element(find.text('الرئيسية'))),
      TextDirection.rtl,
    );
  });
}
