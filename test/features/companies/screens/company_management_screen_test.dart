import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mark_aap/data/models/company_model.dart';
import 'package:mark_aap/data/models/user_model.dart';
import 'package:mark_aap/data/repositories/company_repository.dart';
import 'package:mark_aap/features/companies/screens/company_management_screen.dart';

class _FakeCompanyRepository implements CompanyRepository {
  _FakeCompanyRepository(this.companies);

  List<CompanyModel> companies;
  Completer<List<CompanyModel>>? listCompleter;
  Object? listError;
  int listCalls = 0;
  final createCalls = <({String storeId, String name, String? phone})>[];
  final updateCalls =
      <
        ({
          String storeId,
          String companyId,
          String name,
          String? phone,
          bool isActive,
        })
      >[];
  final statusCalls = <({String storeId, String companyId, bool isActive})>[];

  @override
  Future<List<CompanyModel>> listCompanies(String storeId) async {
    listCalls++;
    if (listError case final error?) {
      listError = null;
      throw error;
    }
    if (listCompleter case final completer?) return completer.future;
    return List<CompanyModel>.of(companies);
  }

  @override
  Future<List<CompanyModel>> listActiveCompanies(String storeId) async =>
      companies.where((company) => company.isActive).toList();

  @override
  Future<CompanyModel?> getCompany(String storeId, String companyId) async {
    for (final company in companies) {
      if (company.companyId == companyId) return company;
    }
    return null;
  }

  @override
  Future<String> createCompany({
    required String storeId,
    required String name,
    String? phone,
  }) async {
    createCalls.add((storeId: storeId, name: name, phone: phone));
    final companyId = 'company-${companies.length + 1}';
    companies = [
      ...companies,
      CompanyModel(
        companyId: companyId,
        name: name,
        phone: phone,
        isActive: true,
      ),
    ];
    return companyId;
  }

  @override
  Future<void> updateCompany({
    required String storeId,
    required String companyId,
    required String name,
    String? phone,
    required bool isActive,
  }) async {
    updateCalls.add((
      storeId: storeId,
      companyId: companyId,
      name: name,
      phone: phone,
      isActive: isActive,
    ));
    companies = companies
        .map(
          (company) => company.companyId == companyId
              ? CompanyModel(
                  companyId: companyId,
                  name: name,
                  phone: phone,
                  isActive: isActive,
                )
              : company,
        )
        .toList();
  }

  @override
  Future<void> setCompanyActive({
    required String storeId,
    required String companyId,
    required bool isActive,
  }) async {
    statusCalls.add((
      storeId: storeId,
      companyId: companyId,
      isActive: isActive,
    ));
    companies = companies
        .map(
          (company) => company.companyId == companyId
              ? CompanyModel(
                  companyId: companyId,
                  name: company.name,
                  phone: company.phone,
                  isActive: isActive,
                )
              : company,
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

Widget _screen(_FakeCompanyRepository repository) => MaterialApp(
  home: CompanyManagementScreen(user: _admin, repository: repository),
);

void main() {
  testWidgets('shows a loading indicator while companies are loading', (
    tester,
  ) async {
    final repository = _FakeCompanyRepository([]);
    repository.listCompleter = Completer<List<CompanyModel>>();

    await tester.pumpWidget(_screen(repository));
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    repository.listCompleter!.complete([]);
    await tester.pumpAndSettle();
    expect(find.text('لا توجد شركات مسجلة بعد.'), findsOneWidget);
  });

  testWidgets('lists company details and active status actions', (
    tester,
  ) async {
    final repository = _FakeCompanyRepository([
      const CompanyModel(
        companyId: 'active-company',
        name: 'Active Supplier',
        phone: '+1 555 0100',
        isActive: true,
      ),
      const CompanyModel(
        companyId: 'inactive-company',
        name: 'Inactive Supplier',
        isActive: false,
      ),
    ]);

    await tester.pumpWidget(_screen(repository));
    await tester.pumpAndSettle();

    expect(find.text('Active Supplier'), findsOneWidget);
    expect(find.text('+1 555 0100'), findsOneWidget);
    expect(find.text('Inactive Supplier'), findsOneWidget);
    expect(find.text('نشطة'), findsOneWidget);
    expect(find.text('غير نشطة'), findsOneWidget);
    expect(find.text('تعديل'), findsNWidgets(2));
    expect(find.text('إيقاف'), findsOneWidget);
    expect(find.text('إعادة تفعيل'), findsOneWidget);
    expect(find.text('حذف'), findsNothing);
  });

  testWidgets('shows an empty state when no companies exist', (tester) async {
    await tester.pumpWidget(_screen(_FakeCompanyRepository([])));
    await tester.pumpAndSettle();

    expect(find.text('لا توجد شركات مسجلة بعد.'), findsOneWidget);
    expect(find.text('إضافة شركة'), findsOneWidget);
  });

  testWidgets('creates and edits a company and changes its status', (
    tester,
  ) async {
    final repository = _FakeCompanyRepository([
      const CompanyModel(
        companyId: 'company-1',
        name: 'Original Supplier',
        phone: '+1 555 0100',
        isActive: true,
      ),
    ]);
    await tester.pumpWidget(_screen(repository));
    await tester.pumpAndSettle();

    await tester.tap(find.text('إضافة شركة'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).at(0), 'New Supplier');
    await tester.enterText(find.byType(TextFormField).at(1), '+1 555 0200');
    await tester.tap(find.widgetWithText(FilledButton, 'حفظ'));
    await tester.pumpAndSettle();

    expect(repository.createCalls, [
      (storeId: 'store-1', name: 'New Supplier', phone: '+1 555 0200'),
    ]);
    expect(find.text('New Supplier'), findsOneWidget);

    await tester.tap(find.widgetWithText(OutlinedButton, 'تعديل').first);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byType(TextFormField).at(0),
      'Updated Supplier',
    );
    await tester.enterText(find.byType(TextFormField).at(1), '');
    await tester.tap(find.widgetWithText(FilledButton, 'حفظ'));
    await tester.pumpAndSettle();

    expect(repository.updateCalls.single, (
      storeId: 'store-1',
      companyId: 'company-1',
      name: 'Updated Supplier',
      phone: null,
      isActive: true,
    ));
    expect(find.text('Updated Supplier'), findsOneWidget);

    await tester.tap(find.widgetWithText(OutlinedButton, 'إيقاف').first);
    await tester.pumpAndSettle();
    expect(find.text('إيقاف الشركة؟'), findsOneWidget);
    expect(repository.statusCalls, isEmpty);
    await tester.tap(find.widgetWithText(FilledButton, 'إيقاف'));
    await tester.pumpAndSettle();

    expect(repository.statusCalls.single, (
      storeId: 'store-1',
      companyId: 'company-1',
      isActive: false,
    ));
    expect(find.text('غير نشطة'), findsOneWidget);
  });

  testWidgets('requires confirmation before changing company status', (
    tester,
  ) async {
    final repository = _FakeCompanyRepository([
      const CompanyModel(
        companyId: 'company-1',
        name: 'Supplier',
        isActive: true,
      ),
    ]);
    await tester.pumpWidget(_screen(repository));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(OutlinedButton, 'إيقاف'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('إلغاء'));
    await tester.pumpAndSettle();

    expect(repository.statusCalls, isEmpty);
    expect(find.text('نشطة'), findsOneWidget);
  });

  testWidgets('shows a load error and retries successfully', (tester) async {
    final repository = _FakeCompanyRepository([]);
    repository.listError = StateError('temporary error');
    repository.companies = [
      const CompanyModel(
        companyId: 'company-1',
        name: 'Recovered Supplier',
        isActive: true,
      ),
    ];

    await tester.pumpWidget(_screen(repository));
    await tester.pumpAndSettle();
    expect(find.text('تعذر تحميل قائمة الشركات.'), findsOneWidget);
    expect(find.text('إعادة المحاولة'), findsOneWidget);

    await tester.tap(find.text('إعادة المحاولة'));
    await tester.pumpAndSettle();
    expect(find.text('Recovered Supplier'), findsOneWidget);
    expect(repository.listCalls, 2);
  });
}
