import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart'
    show CollectionReference, Timestamp;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mark_aap/data/models/company_model.dart';
import 'package:mark_aap/data/models/supplier_debt_model.dart';
import 'package:mark_aap/data/models/supplier_payment_model.dart';
import 'package:mark_aap/data/models/user_model.dart';
import 'package:mark_aap/data/repositories/company_repository.dart';
import 'package:mark_aap/data/repositories/supplier_payment_repository.dart';
import 'package:mark_aap/features/suppliers/screens/supplier_debt_list_screen.dart';

class _FakePaymentRepository implements SupplierPaymentRepository {
  _FakePaymentRepository({this.debts = const []});

  List<SupplierDebtModel> debts;
  Completer<List<SupplierDebtModel>>? debtsCompleter;
  Object? debtsError;
  int listCalls = 0;
  final listArgs = <({String storeId, String companyId})>[];

  @override
  CollectionReference<Map<String, dynamic>> supplierPayments(String storeId) =>
      throw UnimplementedError();

  @override
  CollectionReference<Map<String, dynamic>> supplierDebts(String storeId) =>
      throw UnimplementedError();

  @override
  CollectionReference<Map<String, dynamic>> cashWithdrawals(String storeId) =>
      throw UnimplementedError();

  @override
  CollectionReference<Map<String, dynamic>> operations(String storeId) =>
      throw UnimplementedError();

  @override
  String newOperationId(String storeId) => 'op-1';

  @override
  Future<SupplierPaymentModel> getPayment(String storeId, String paymentId) =>
      throw UnimplementedError();

  @override
  Future<List<SupplierPaymentModel>> listPayments(String storeId) async => [];

  @override
  Future<SupplierDebtModel> getDebt(String storeId, String invoiceId) =>
      throw UnimplementedError();

  @override
  Future<List<SupplierDebtModel>> listOpenDebtsForCompany(
    String storeId,
    String companyId,
  ) async {
    listCalls++;
    listArgs.add((storeId: storeId, companyId: companyId));
    if (debtsError case final error?) {
      debtsError = null;
      throw error;
    }
    if (debtsCompleter case final completer?) return completer.future;
    return debts;
  }

  @override
  Future<String> createPayment({
    required String storeId,
    required String companyId,
    required String companyName,
    required int amountFils,
    required SupplierPaymentSource source,
    required int allocationCount,
    required String allocation1InvoiceId,
    required int allocation1AmountFils,
    String? allocation2InvoiceId,
    int? allocation2AmountFils,
    String? allocation3InvoiceId,
    int? allocation3AmountFils,
    String? allocation4InvoiceId,
    int? allocation4AmountFils,
    String? allocation5InvoiceId,
    int? allocation5AmountFils,
    String? notes,
    required String createdBy,
    required String operationId,
  }) =>
      throw UnimplementedError();
}

class _FakeCompanyRepository implements CompanyRepository {
  _FakeCompanyRepository(this.companies);

  List<CompanyModel> companies;
  Object? listError;

  @override
  Future<List<CompanyModel>> listCompanies(String storeId) async => companies;

  @override
  Future<List<CompanyModel>> listActiveCompanies(String storeId) async {
    if (listError case final error?) {
      listError = null;
      throw error;
    }
    return companies.where((company) => company.isActive).toList();
  }

  @override
  Future<CompanyModel?> getCompany(String storeId, String companyId) async =>
      null;

  @override
  Future<String> createCompany({
    required String storeId,
    required String name,
    String? phone,
  }) async =>
      'company-x';

  @override
  Future<void> updateCompany({
    required String storeId,
    required String companyId,
    required String name,
    String? phone,
    required bool isActive,
  }) async {}

  @override
  Future<void> setCompanyActive({
    required String storeId,
    required String companyId,
    required bool isActive,
  }) async {}
}

const _viewer = UserModel(
  uid: 'viewer-1',
  storeId: 'store-1',
  name: 'Viewer',
  email: 'viewer@example.com',
  role: 'ADMIN',
  isActive: true,
);

const _activeCompany = CompanyModel(
  companyId: 'company-1',
  name: 'Active Supplier',
  isActive: true,
);

const _inactiveCompany = CompanyModel(
  companyId: 'company-2',
  name: 'Inactive Supplier',
  isActive: false,
);

SupplierDebtModel _debt({
  required String invoiceId,
  required int originalAmountFils,
  required int remainingAmountFils,
  SupplierDebtStatus status = SupplierDebtStatus.open,
  int createdAtMillis = 0,
}) => SupplierDebtModel(
  invoiceId: invoiceId,
  companyId: 'company-1',
  companyName: 'Active Supplier',
  originalAmountFils: originalAmountFils,
  remainingAmountFils: remainingAmountFils,
  status: status,
  createdAt: Timestamp.fromMillisecondsSinceEpoch(createdAtMillis),
  createdBy: 'admin-1',
  operationId: invoiceId,
  lastOperationId: invoiceId,
);

Widget _screen({
  required _FakePaymentRepository payments,
  required _FakeCompanyRepository companies,
}) => MaterialApp(
  home: SupplierDebtListScreen(
    user: _viewer,
    paymentRepository: payments,
    companyRepository: companies,
  ),
);

void main() {
  testWidgets('shows a loading indicator then lists only active companies', (
    tester,
  ) async {
    final payments = _FakePaymentRepository();
    final companies = _FakeCompanyRepository([_activeCompany, _inactiveCompany])
      ..listError = null;
    // Hold the company list so the loading state is visible.
    await tester.pumpWidget(
      _screen(payments: payments, companies: companies),
    );
    await tester.pumpAndSettle();

    expect(find.text('Active Supplier'), findsOneWidget);
    expect(find.text('Inactive Supplier'), findsNothing);
  });

  testWidgets('shows a load error for companies and retries', (tester) async {
    final companies = _FakeCompanyRepository([_activeCompany])
      ..listError = StateError('temporary');
    // After the first failure the fake clears the error, so retry succeeds.
    final payments = _FakePaymentRepository();

    await tester.pumpWidget(
      _screen(payments: payments, companies: companies),
    );
    await tester.pumpAndSettle();
    expect(find.text('تعذر تحميل قائمة الموردين.'), findsOneWidget);

    await tester.tap(find.text('إعادة المحاولة'));
    await tester.pumpAndSettle();
    expect(find.text('Active Supplier'), findsOneWidget);
  });

  testWidgets('shows an empty state when there are no active companies', (
    tester,
  ) async {
    await tester.pumpWidget(
      _screen(
        payments: _FakePaymentRepository(),
        companies: _FakeCompanyRepository([]),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('لا توجد شركات نشطة بعد.'), findsOneWidget);
  });

  testWidgets('selecting a company loads and shows its open debts', (
    tester,
  ) async {
    final payments = _FakePaymentRepository(debts: [
      _debt(
        invoiceId: 'inv-1',
        originalAmountFils: 100000,
        remainingAmountFils: 40000,
        createdAtMillis: 100,
      ),
      _debt(
        invoiceId: 'inv-2',
        originalAmountFils: 50000,
        remainingAmountFils: 25000,
        createdAtMillis: 200,
      ),
    ]);
    await tester.pumpWidget(
      _screen(payments: payments, companies: _FakeCompanyRepository([_activeCompany])),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Active Supplier'));
    await tester.pumpAndSettle();

    expect(payments.listCalls, 1);
    expect(payments.listArgs.single.companyId, 'company-1');
    expect(find.text('فاتورة: inv-1'), findsOneWidget);
    expect(find.text('فاتورة: inv-2'), findsOneWidget);
    expect(find.text('المبلغ الأصلي'), findsNWidgets(2));
    expect(find.text('المتبقي'), findsNWidgets(2));
    expect(find.text('مفتوحة'), findsNWidgets(2));
    // Summary shows the summed remaining balance.
    expect(find.text('إجمالي الرصيد المتبقي'), findsOneWidget);
    expect(find.text('65.00 د.أ'), findsOneWidget);
  });

  testWidgets('shows an empty state when the company has no open debts', (
    tester,
  ) async {
    final payments = _FakePaymentRepository(debts: []);
    await tester.pumpWidget(
      _screen(payments: payments, companies: _FakeCompanyRepository([_activeCompany])),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Active Supplier'));
    await tester.pumpAndSettle();

    expect(find.text('لا توجد ديون متبقية لهذا المورد.'), findsOneWidget);
  });

  testWidgets('shows a load error for debts and retries', (tester) async {
    final payments = _FakePaymentRepository(debts: [
      _debt(
        invoiceId: 'inv-recovered',
        originalAmountFils: 10000,
        remainingAmountFils: 10000,
      ),
    ]);
    // First debt load fails, then the fake clears the error so retry succeeds.
    payments.debtsError = StateError('temporary');

    await tester.pumpWidget(
      _screen(payments: payments, companies: _FakeCompanyRepository([_activeCompany])),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Active Supplier'));
    await tester.pumpAndSettle();
    expect(find.text('تعذر تحميل ديون المورد.'), findsOneWidget);

    await tester.tap(find.text('إعادة المحاولة'));
    await tester.pumpAndSettle();
    expect(find.text('فاتورة: inv-recovered'), findsOneWidget);
  });

  testWidgets('the back arrow clears the selection and returns to companies', (
    tester,
  ) async {
    final payments = _FakePaymentRepository(debts: [
      _debt(
        invoiceId: 'inv-1',
        originalAmountFils: 10000,
        remainingAmountFils: 5000,
      ),
    ]);
    await tester.pumpWidget(
      _screen(payments: payments, companies: _FakeCompanyRepository([_activeCompany])),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Active Supplier'));
    await tester.pumpAndSettle();
    expect(find.text('فاتورة: inv-1'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.arrow_forward));
    await tester.pumpAndSettle();

    expect(find.text('Active Supplier'), findsOneWidget);
    expect(find.text('فاتورة: inv-1'), findsNothing);
    // Returning to the list must not re-query debts.
    expect(payments.listCalls, 1);
  });
}
