import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart' show CollectionReference;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mark_aap/data/models/company_model.dart';
import 'package:mark_aap/data/models/purchase_invoice_model.dart';
import 'package:mark_aap/data/models/user_model.dart';
import 'package:mark_aap/data/repositories/company_repository.dart';
import 'package:mark_aap/data/repositories/purchase_invoice_repository.dart';
import 'package:mark_aap/features/purchases/screens/purchase_invoice_form_screen.dart';

class _FakeInvoiceRepository implements PurchaseInvoiceRepository {
  final createCalls = <Map<String, dynamic>>[];
  Object? createError;
  Completer<void>? createCompleter;
  int newIdCalls = 0;

  @override
  CollectionReference<Map<String, dynamic>> purchaseInvoices(String storeId) =>
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
  String newOperationId(String storeId) {
    newIdCalls++;
    return 'op-$newIdCalls';
  }

  @override
  Future<PurchaseInvoiceModel> getInvoice(String storeId, String invoiceId) =>
      throw UnimplementedError();

  @override
  Future<List<PurchaseInvoiceModel>> listInvoices(String storeId) async => [];

  @override
  Future<String> createInvoice({
    required String storeId,
    required String companyId,
    required String companyName,
    required int totalAmountFils,
    required int shopCashAmountFils,
    required int outsideCashAmountFils,
    required int supplierDebtAmountFils,
    String? supplierInvoiceNumber,
    String? notes,
    required List<String> photoIds,
    required String createdBy,
    required String operationId,
  }) async {
    createCalls.add({
      'storeId': storeId,
      'companyId': companyId,
      'companyName': companyName,
      'totalAmountFils': totalAmountFils,
      'shopCashAmountFils': shopCashAmountFils,
      'outsideCashAmountFils': outsideCashAmountFils,
      'supplierDebtAmountFils': supplierDebtAmountFils,
      'supplierInvoiceNumber': supplierInvoiceNumber,
      'notes': notes,
      'photoIds': photoIds,
      'createdBy': createdBy,
      'operationId': operationId,
    });
    if (createCompleter case final completer?) await completer.future;
    if (createError case final error?) {
      createError = null;
      throw error;
    }
    return operationId;
  }
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

const _admin = UserModel(
  uid: 'admin-1',
  storeId: 'store-1',
  name: 'Store Admin',
  email: 'admin@example.com',
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

Widget _screen({
  required _FakeInvoiceRepository invoices,
  required _FakeCompanyRepository companies,
}) => MaterialApp(
  home: PurchaseInvoiceFormScreen(
    user: _admin,
    invoiceRepository: invoices,
    companyRepository: companies,
  ),
);

/// Enters a valid total + split that sums exactly to the total.
Future<void> _enterValidSplit(WidgetTester tester) async {
  final fields = find.byType(TextFormField);
  // Order: supplier number, total, shopCash, outsideCash, debt, notes.
  await tester.enterText(fields.at(1), '125.50'); // total
  await tester.enterText(fields.at(2), '50.00'); // shop cash
  await tester.enterText(fields.at(3), '25.50'); // outside cash
  await tester.enterText(fields.at(4), '50.00'); // supplier debt
  await tester.pump();
}

void main() {
  testWidgets('loads only active companies and defaults the selection', (
    tester,
  ) async {
    await tester.pumpWidget(
      _screen(
        invoices: _FakeInvoiceRepository(),
        companies: _FakeCompanyRepository([_activeCompany, _inactiveCompany]),
      ),
    );
    await tester.pumpAndSettle();

    // Only the active company is offered.
    expect(find.text('Active Supplier'), findsOneWidget);
    expect(find.text('Inactive Supplier'), findsNothing);
  });

  testWidgets('shows a load error and retries', (tester) async {
    final companies = _FakeCompanyRepository([_activeCompany]);
    companies.listError = StateError('temporary');
    companies.companies = [_activeCompany];

    await tester.pumpWidget(
      _screen(invoices: _FakeInvoiceRepository(), companies: companies),
    );
    await tester.pumpAndSettle();

    expect(find.text('تعذر تحميل قائمة الشركات النشطة.'), findsOneWidget);

    await tester.tap(find.text('إعادة المحاولة'));
    await tester.pumpAndSettle();
    expect(find.text('Active Supplier'), findsOneWidget);
  });

  testWidgets('blocks saving while the split does not match the total', (
    tester,
  ) async {
    final invoices = _FakeInvoiceRepository();
    await tester.pumpWidget(
      _screen(
        invoices: invoices,
        companies: _FakeCompanyRepository([_activeCompany]),
      ),
    );
    await tester.pumpAndSettle();

    final fields = find.byType(TextFormField);
    await tester.enterText(fields.at(1), '100.00'); // total
    await tester.enterText(fields.at(2), '50.00'); // shop cash
    await tester.enterText(fields.at(3), '30.00'); // outside cash
    await tester.enterText(fields.at(4), '20.00'); // debt => sums to 100.00
    await tester.pump();
    expect(find.text('التقسيم مطابق للإجمالي'), findsOneWidget);

    // Break the split so it sums to 90.00 instead of 100.00.
    await tester.enterText(fields.at(4), '10.00');
    await tester.pump();
    expect(find.textContaining('لا يساوي الإجمالي'), findsOneWidget);

    await tester.tap(find.text('حفظ الفاتورة'));
    await tester.pump();
    expect(invoices.createCalls, isEmpty);
  });

  testWidgets('rejects a total with more than two decimal places', (
    tester,
  ) async {
    final invoices = _FakeInvoiceRepository();
    await tester.pumpWidget(
      _screen(
        invoices: invoices,
        companies: _FakeCompanyRepository([_activeCompany]),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextFormField).at(1), '10.123');
    await tester.pump();
    await tester.tap(find.text('حفظ الفاتورة'));
    await tester.pump();

    expect(
      find.text('مبلغ غير صحيح؛ يقبل رقمين عشريين كحد أقصى.'),
      findsOneWidget,
    );
    expect(invoices.createCalls, isEmpty);
  });

  testWidgets('saves a valid invoice with the parsed fils amounts', (
    tester,
  ) async {
    final invoices = _FakeInvoiceRepository();
    await tester.pumpWidget(
      _screen(
        invoices: invoices,
        companies: _FakeCompanyRepository([_activeCompany]),
      ),
    );
    await tester.pumpAndSettle();

    await _enterValidSplit(tester);
    await tester.tap(find.text('حفظ الفاتورة'));
    await tester.pump();
    await tester.pump(); // let the future + snackbar settle

    expect(invoices.createCalls, hasLength(1));
    final call = invoices.createCalls.single;
    expect(call['companyId'], 'company-1');
    expect(call['companyName'], 'Active Supplier');
    expect(call['totalAmountFils'], 125500);
    expect(call['shopCashAmountFils'], 50000);
    expect(call['outsideCashAmountFils'], 25500);
    expect(call['supplierDebtAmountFils'], 50000);
    expect(call['createdBy'], 'admin-1');
    expect(call['operationId'], 'op-1');
    expect(call['photoIds'], isEmpty);
  });

  testWidgets('mints one operation id and prevents a duplicate submission', (
    tester,
  ) async {
    final invoices = _FakeInvoiceRepository()..createCompleter = Completer<void>();
    await tester.pumpWidget(
      _screen(
        invoices: invoices,
        companies: _FakeCompanyRepository([_activeCompany]),
      ),
    );
    await tester.pumpAndSettle();

    await _enterValidSplit(tester);

    final saveButton = find.byType(FilledButton);
    await tester.tap(saveButton);
    await tester.pump(); // save begins; label swaps to spinner and button disables
    await tester.tap(saveButton); // no-op while saving
    await tester.pump();

    expect(invoices.createCalls, hasLength(1));
    expect(invoices.newIdCalls, 1);

    invoices.createCompleter!.complete();
    await tester.pump();
    await tester.pump();
  });

  testWidgets('shows an error and keeps the form when saving fails', (
    tester,
  ) async {
    final invoices = _FakeInvoiceRepository()
      ..createError = StateError('permission denied');
    await tester.pumpWidget(
      _screen(
        invoices: invoices,
        companies: _FakeCompanyRepository([_activeCompany]),
      ),
    );
    await tester.pumpAndSettle();

    await _enterValidSplit(tester);
    await tester.tap(find.text('حفظ الفاتورة'));
    await tester.pump();
    await tester.pump();

    expect(invoices.createCalls, hasLength(1));
    expect(
      find.text('تعذر حفظ الفاتورة. تحقق من الاتصال وحاول مرة أخرى.'),
      findsOneWidget,
    );
  });

  testWidgets('reports a duplicate operation instead of re-creating', (
    tester,
  ) async {
    final invoices = _FakeInvoiceRepository()
      ..createError = const InvoiceAlreadyExistsException();
    await tester.pumpWidget(
      _screen(
        invoices: invoices,
        companies: _FakeCompanyRepository([_activeCompany]),
      ),
    );
    await tester.pumpAndSettle();

    await _enterValidSplit(tester);
    await tester.tap(find.text('حفظ الفاتورة'));
    await tester.pump();
    await tester.pump();

    expect(
      find.text('تم إنشاء هذه الفاتورة مسبقاً؛ لم تُنشأ فاتورة جديدة.'),
      findsOneWidget,
    );
  });
}
