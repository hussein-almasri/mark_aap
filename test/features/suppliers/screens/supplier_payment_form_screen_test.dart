import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart'
    show CollectionReference, FirebaseException, Timestamp;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:mark_aap/data/models/purchase_invoice_model.dart';
import 'package:mark_aap/data/models/supplier_debt_model.dart';
import 'package:mark_aap/data/models/supplier_payment_model.dart';
import 'package:mark_aap/data/models/user_model.dart';
import 'package:mark_aap/data/repositories/purchase_invoice_repository.dart';
import 'package:mark_aap/data/repositories/supplier_payment_repository.dart';
import 'package:mark_aap/features/suppliers/screens/supplier_payment_form_screen.dart';

class _CreatePaymentCall {
  _CreatePaymentCall({
    required this.amountFils,
    required this.source,
    required this.allocationCount,
    required this.allocationInvoiceIds,
    required this.allocationAmountFils,
    required this.notes,
    required this.createdBy,
    required this.operationId,
  });

  final int amountFils;
  final SupplierPaymentSource source;
  final int allocationCount;
  final List<String?> allocationInvoiceIds;
  final List<int?> allocationAmountFils;
  final String? notes;
  final String createdBy;
  final String operationId;
}

class _FakePaymentRepository implements SupplierPaymentRepository {
  _FakePaymentRepository({this.debts = const []});

  List<SupplierDebtModel> debts;
  Completer<List<SupplierDebtModel>>? debtsCompleter;
  Object? debtsError;
  int newIdCalls = 0;
  final createCalls = <_CreatePaymentCall>[];
  Object? createError;
  SupplierPaymentSaveStage createStage = SupplierPaymentSaveStage.paymentTransaction;
  SupplierPaymentConflictReason? createConflict;
  Completer<void>? createGate;
  bool throwAlreadyExists = false;

  @override
  CollectionReference<Map<String, dynamic>> supplierPayments(String storeId) =>
      throw UnimplementedError();

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
  }) async {
    createCalls.add(
      _CreatePaymentCall(
        amountFils: amountFils,
        source: source,
        allocationCount: allocationCount,
        allocationInvoiceIds: [
          allocation1InvoiceId,
          allocation2InvoiceId,
          allocation3InvoiceId,
          allocation4InvoiceId,
          allocation5InvoiceId,
        ],
        allocationAmountFils: [
          allocation1AmountFils,
          allocation2AmountFils,
          allocation3AmountFils,
          allocation4AmountFils,
          allocation5AmountFils,
        ],
        notes: notes,
        createdBy: createdBy,
        operationId: operationId,
      ),
    );
    if (createGate case final gate?) {
      await gate.future;
    }
    if (throwAlreadyExists) throw const PaymentAllocationMismatchException();
    if (createError case final error?) {
      createError = null;
      throw SupplierPaymentStageException(
        stage: createStage,
        cause: error,
        conflict: createConflict,
      );
    }
    return operationId;
  }
}

/// Read-only fake for the invoice documents that carry the optional supplier
/// invoice number.
///
/// An id present in [numbers] resolves: the value (or `null`) is the invoice's
/// `supplierInvoiceNumber`. An id absent from [numbers] simulates a missing
/// invoice document, which the screen must treat as "no number".
class _FakeInvoiceRepository implements PurchaseInvoiceRepository {
  _FakeInvoiceRepository({this.numbers = const {}});

  final Map<String, String?> numbers;
  int getCalls = 0;
  final requestedIds = <String>[];

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
  String newOperationId(String storeId) => 'op-x';

  @override
  Future<PurchaseInvoiceModel> getInvoice(
    String storeId,
    String invoiceId,
  ) async {
    getCalls++;
    requestedIds.add(invoiceId);
    if (!numbers.containsKey(invoiceId)) {
      throw StateError('Purchase invoice document is empty.');
    }
    return _invoice(
      invoiceId: invoiceId,
      supplierInvoiceNumber: numbers[invoiceId],
    );
  }

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
  }) =>
      throw UnimplementedError();
}

PurchaseInvoiceModel _invoice({
  required String invoiceId,
  String? supplierInvoiceNumber,
}) => PurchaseInvoiceModel(
  invoiceId: invoiceId,
  companyId: 'company-1',
  companyName: 'Supplier',
  totalAmountFils: 100000,
  shopCashAmountFils: 0,
  outsideCashAmountFils: 0,
  supplierDebtAmountFils: 100000,
  status: PurchaseInvoiceStatus.active,
  createdAt: Timestamp.fromMillisecondsSinceEpoch(0),
  createdBy: 'admin-1',
  operationId: invoiceId,
  photoIds: const [],
  supplierInvoiceNumber: supplierInvoiceNumber,
);

const _user = UserModel(
  uid: 'u1',
  storeId: 'store-1',
  name: 'User',
  email: 'u@example.com',
  role: 'ADMIN',
  isActive: true,
);

SupplierDebtModel _debt({
  required String invoiceId,
  required int remainingAmountFils,
  int createdAtMillis = 0,
}) => SupplierDebtModel(
  invoiceId: invoiceId,
  companyId: 'company-1',
  companyName: 'Supplier',
  originalAmountFils: remainingAmountFils,
  remainingAmountFils: remainingAmountFils,
  status: SupplierDebtStatus.open,
  createdAt: Timestamp.fromMillisecondsSinceEpoch(createdAtMillis),
  createdBy: 'admin-1',
  operationId: invoiceId,
  lastOperationId: invoiceId,
);

/// Pumps the form. Unless given otherwise, every debt's invoice resolves but
/// carries no supplier number, so its option reads «فاتورة بدون رقم».
///
/// The viewport is enlarged so the whole form fits without scrolling — the list
/// builds its children lazily, so a scrolled-out field would be unmounted and
/// unreachable for `enterText`.
Future<void> _pump(
  WidgetTester tester, {
  required _FakePaymentRepository payments,
  _FakeInvoiceRepository? invoices,
}) async {
  tester.view.physicalSize = const Size(800, 3000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final invoiceRepo =
      invoices ??
      _FakeInvoiceRepository(
        numbers: {for (final debt in payments.debts) debt.invoiceId: null},
      );
  await tester.pumpWidget(
    MaterialApp(
      home: SupplierPaymentFormScreen(
        user: _user,
        companyId: 'company-1',
        companyName: 'Supplier',
        paymentRepository: payments,
        invoiceRepository: invoiceRepo,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _selectAt(WidgetTester tester, int debtIndex) async {
  final tile = find.byType(CheckboxListTile).at(debtIndex);
  await tester.ensureVisible(tile);
  await tester.pumpAndSettle();
  await tester.tap(tile, warnIfMissed: false);
  await tester.pump();
}

Future<void> _enterAllocation(
  WidgetTester tester, {
  required int debtIndex,
  required String value,
}) async {
  final tile = find.byType(CheckboxListTile).at(debtIndex);
  final card = find.ancestor(of: tile, matching: find.byType(Card)).first;
  final field = find.descendant(of: card, matching: find.byType(TextFormField));
  await tester.ensureVisible(field);
  await tester.pumpAndSettle();
  await tester.enterText(field, value);
  await tester.pump();
}

/// Fills the payment amount, then selects the given debts and their allocation
/// amounts.
Future<void> _fill(
  WidgetTester tester, {
  required String amount,
  required Map<int, String> allocations,
}) async {
  // Enter the payment amount first, while the field is at the top of the form.
  await tester.enterText(
    find.widgetWithText(TextFormField, 'إجمالي مبلغ الدفعة (د.أ)'),
    amount,
  );
  await tester.pump();
  for (final entry in allocations.entries) {
    await _selectAt(tester, entry.key);
    await _enterAllocation(tester, debtIndex: entry.key, value: entry.value);
  }
}

Future<void> _tapSave(WidgetTester tester) async {
  await tester.tap(find.byType(FilledButton), warnIfMissed: false);
  await tester.pump();
}

String _dateOf(int millis) =>
    DateFormat('dd/MM/yyyy - HH:mm').format(
      Timestamp.fromMillisecondsSinceEpoch(millis).toDate(),
    );

void main() {
  testWidgets('lists open debts as selectable options without raw ids', (
    tester,
  ) async {
    final payments = _FakePaymentRepository(debts: [
      _debt(invoiceId: 'inv-1', remainingAmountFils: 40000, createdAtMillis: 100),
      _debt(invoiceId: 'inv-2', remainingAmountFils: 25000, createdAtMillis: 3600000),
    ]);
    await _pump(tester, payments: payments);

    expect(find.text('دفعة إلى Supplier'), findsOneWidget);
    // Each option shows the fallback label, the creation date and the balance.
    expect(find.text('فاتورة بدون رقم'), findsNWidgets(2));
    expect(find.textContaining(_dateOf(100)), findsOneWidget);
    expect(find.textContaining(_dateOf(3600000)), findsOneWidget);
    expect(find.textContaining('المتبقي: 40.00 د.أ'), findsOneWidget);
    expect(find.textContaining('المتبقي: 25.00 د.أ'), findsOneWidget);
    // The internal id is never surfaced as the label.
    expect(find.text('فاتورة inv-1'), findsNothing);
    expect(find.text('كاش الصندوق'), findsOneWidget);
    expect(find.text('كاش خارج الصندوق'), findsOneWidget);
    // Selecting exposes the allocation field for that invoice only.
    expect(find.text('المبلغ المسدّد لهذه الفاتورة (د.أ)'), findsNothing);
    await _selectAt(tester, 0);
    expect(find.text('المبلغ المسدّد لهذه الفاتورة (د.أ)'), findsOneWidget);
  });

  testWidgets('shows the supplier invoice number when it exists', (
    tester,
  ) async {
    final payments = _FakePaymentRepository(debts: [
      _debt(invoiceId: 'inv-1', remainingAmountFils: 40000),
    ]);
    await _pump(
      tester,
      payments: payments,
      invoices: _FakeInvoiceRepository(numbers: {'inv-1': 'SN-777'}),
    );

    expect(find.text('SN-777'), findsOneWidget);
    expect(find.text('فاتورة بدون رقم'), findsNothing);
  });

  testWidgets('saves an invoice without a supplier number using its internal id', (
    tester,
  ) async {
    final payments = _FakePaymentRepository(debts: [
      _debt(invoiceId: 'inv-1', remainingAmountFils: 40000),
    ]);
    await _pump(tester, payments: payments);

    expect(find.text('فاتورة بدون رقم'), findsOneWidget);
    await _fill(tester, amount: '40.00', allocations: {0: '40.00'});
    await _tapSave(tester);
    await tester.pumpAndSettle();

    expect(payments.createCalls, hasLength(1));
    final call = payments.createCalls.single;
    expect(call.allocationCount, 1);
    expect(call.allocationInvoiceIds[0], 'inv-1');
    expect(call.allocationAmountFils[0], 40000);
  });

  testWidgets('saves two invoices that have no supplier numbers', (
    tester,
  ) async {
    final payments = _FakePaymentRepository(debts: [
      _debt(invoiceId: 'inv-a', remainingAmountFils: 40000, createdAtMillis: 100),
      _debt(invoiceId: 'inv-b', remainingAmountFils: 25000, createdAtMillis: 900),
    ]);
    await _pump(tester, payments: payments);

    // Two invoices, both without a number, distinguished by date and balance.
    expect(find.text('فاتورة بدون رقم'), findsNWidgets(2));
    expect(find.textContaining('المتبقي: 40.00 د.أ'), findsOneWidget);
    expect(find.textContaining('المتبقي: 25.00 د.أ'), findsOneWidget);

    await _fill(tester, amount: '65.00', allocations: {0: '40.00', 1: '25.00'});
    await _tapSave(tester);
    await tester.pumpAndSettle();

    final call = payments.createCalls.single;
    expect(call.amountFils, 65000);
    expect(call.allocationCount, 2);
    expect(call.allocationInvoiceIds[0], 'inv-a');
    expect(call.allocationInvoiceIds[1], 'inv-b');
    expect(call.allocationAmountFils[0], 40000);
    expect(call.allocationAmountFils[1], 25000);
  });

  testWidgets('uses internal invoice ids even when a supplier number exists', (
    tester,
  ) async {
    final payments = _FakePaymentRepository(debts: [
      _debt(invoiceId: 'inv-1', remainingAmountFils: 40000),
    ]);
    await _pump(
      tester,
      payments: payments,
      invoices: _FakeInvoiceRepository(numbers: {'inv-1': 'SN-777'}),
    );

    await _fill(tester, amount: '40.00', allocations: {0: '40.00'});
    await _tapSave(tester);
    await tester.pumpAndSettle();

    final call = payments.createCalls.single;
    expect(call.allocationInvoiceIds[0], 'inv-1');
    expect(call.allocationInvoiceIds[0], isNot('SN-777'));
  });

  testWidgets('shows an empty state when there are no open debts', (
    tester,
  ) async {
    await _pump(tester, payments: _FakePaymentRepository(debts: []));
    expect(find.text('لا توجد ديون متبقية لهذا المورد.'), findsOneWidget);
  });

  testWidgets('shows a load error and retries', (tester) async {
    final payments = _FakePaymentRepository(debts: [
      _debt(invoiceId: 'inv-1', remainingAmountFils: 40000),
    ])
      ..debtsError = StateError('temporary');
    await _pump(tester, payments: payments);
    expect(find.text('تعذر تحميل ديون المورد.'), findsOneWidget);

    await tester.tap(find.text('إعادة المحاولة'));
    await tester.pumpAndSettle();
    expect(find.text('فاتورة بدون رقم'), findsOneWidget);
  });

  testWidgets('shows live payment, allocated and remaining totals', (
    tester,
  ) async {
    final payments = _FakePaymentRepository(debts: [
      _debt(invoiceId: 'inv-1', remainingAmountFils: 40000),
      _debt(invoiceId: 'inv-2', remainingAmountFils: 25000, createdAtMillis: 200),
    ]);
    await _pump(tester, payments: payments);

    await _fill(
      tester,
      amount: '65.00',
      allocations: {0: '40.00', 1: '25.00'},
    );

    // The total payment amount is distinct from the per-invoice allocated
    // amount, and the caption spells out how the two relate.
    expect(find.text('إجمالي مبلغ الدفعة'), findsOneWidget);
    expect(find.text('65.00 د.أ'), findsWidgets);
    expect(find.text('إجمالي المسدّد للفواتير'), findsOneWidget);
    expect(find.text('المتبقي من الدفعة'), findsOneWidget);
    expect(find.text('0.00 د.أ'), findsOneWidget);
    expect(
      find.text(
        'يُخصم «المسدّد للفواتير» من كل فاتورة على حدة، حسب المبلغ المسدّد لها.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('blocks save when allocations do not sum to the amount', (
    tester,
  ) async {
    final payments = _FakePaymentRepository(debts: [
      _debt(invoiceId: 'inv-1', remainingAmountFils: 40000),
      _debt(invoiceId: 'inv-2', remainingAmountFils: 25000, createdAtMillis: 200),
    ]);
    await _pump(tester, payments: payments);

    await _fill(
      tester,
      amount: '65.00',
      allocations: {0: '40.00', 1: '20.00'},
    );
    await _tapSave(tester);
    await tester.pumpAndSettle();

    expect(payments.createCalls, isEmpty);
  });

  testWidgets('blocks save when an allocation exceeds the balance', (
    tester,
  ) async {
    final payments = _FakePaymentRepository(debts: [
      _debt(invoiceId: 'inv-1', remainingAmountFils: 40000),
    ]);
    await _pump(tester, payments: payments);

    await _fill(tester, amount: '45.00', allocations: {0: '45.00'});
    await _tapSave(tester);
    await tester.pumpAndSettle();

    expect(payments.createCalls, isEmpty);
  });

  testWidgets('blocks save when nothing is selected', (tester) async {
    final payments = _FakePaymentRepository(debts: [
      _debt(invoiceId: 'inv-1', remainingAmountFils: 40000),
    ]);
    await _pump(tester, payments: payments);

    await tester.enterText(
      find.widgetWithText(TextFormField, 'إجمالي مبلغ الدفعة (د.أ)'),
      '40.00',
    );
    await tester.pump();
    await _tapSave(tester);
    await tester.pumpAndSettle();

    expect(payments.createCalls, isEmpty);
    expect(find.text('اختر فاتورة واحدة على الأقل.'), findsOneWidget);
  });

  testWidgets('prevents selecting more than five invoices', (tester) async {
    final payments = _FakePaymentRepository(
      debts: [
        for (var i = 1; i <= 6; i++)
          _debt(
            invoiceId: 'inv-$i',
            remainingAmountFils: 10000,
            createdAtMillis: i * 100,
          ),
      ],
    );
    await _pump(tester, payments: payments);

    for (var i = 0; i < 5; i++) {
      await _selectAt(tester, i);
    }
    // The sixth selection is refused with a clear message.
    await _selectAt(tester, 5);
    await tester.pumpAndSettle();

    expect(find.text('الحد الأقصى 5 فواتير في الدفعة الواحدة.'), findsOneWidget);
    final tiles = tester
        .widgetList<CheckboxListTile>(find.byType(CheckboxListTile))
        .toList();
    expect(tiles.where((tile) => tile.value == true), hasLength(5));
    expect(tiles[5].value, isFalse);
  });

  testWidgets('saves a single-invoice payment with the exact arguments', (
    tester,
  ) async {
    final payments = _FakePaymentRepository(debts: [
      _debt(invoiceId: 'inv-1', remainingAmountFils: 40000),
    ]);
    await _pump(tester, payments: payments);

    await _fill(tester, amount: '40.00', allocations: {0: '40.00'});
    await _tapSave(tester);
    await tester.pumpAndSettle();

    expect(payments.createCalls, hasLength(1));
    final call = payments.createCalls.single;
    expect(call.amountFils, 40000);
    expect(call.source, SupplierPaymentSource.shopCash);
    expect(call.allocationCount, 1);
    expect(call.allocationInvoiceIds[0], 'inv-1');
    expect(call.allocationAmountFils[0], 40000);
    expect(call.allocationInvoiceIds[1], isNull);
    expect(call.allocationAmountFils[1], isNull);
    expect(call.createdBy, 'u1');
    expect(call.operationId, 'op-1');
  });

  testWidgets('saves a multi-invoice payment mapping allocations to slots', (
    tester,
  ) async {
    final payments = _FakePaymentRepository(debts: [
      _debt(invoiceId: 'inv-1', remainingAmountFils: 40000),
      _debt(invoiceId: 'inv-2', remainingAmountFils: 25000, createdAtMillis: 200),
      _debt(invoiceId: 'inv-3', remainingAmountFils: 10000, createdAtMillis: 300),
    ]);
    await _pump(tester, payments: payments);

    // Leave the middle invoice unselected to check slot packing.
    await _fill(
      tester,
      amount: '50.00',
      allocations: {0: '40.00', 2: '10.00'},
    );
    await _tapSave(tester);
    await tester.pumpAndSettle();

    final call = payments.createCalls.single;
    expect(call.amountFils, 50000);
    expect(call.allocationCount, 2);
    expect(call.allocationInvoiceIds[0], 'inv-1');
    expect(call.allocationAmountFils[0], 40000);
    expect(call.allocationInvoiceIds[1], 'inv-3');
    expect(call.allocationAmountFils[1], 10000);
    expect(call.allocationInvoiceIds[2], isNull);
    expect(call.allocationAmountFils[2], isNull);
  });

  testWidgets('uses outside cash when the source is switched', (tester) async {
    final payments = _FakePaymentRepository(debts: [
      _debt(invoiceId: 'inv-1', remainingAmountFils: 40000),
    ]);
    await _pump(tester, payments: payments);

    await _fill(tester, amount: '40.00', allocations: {0: '40.00'});
    await tester.tap(find.text('كاش خارج الصندوق'));
    await tester.pump();
    await _tapSave(tester);
    await tester.pumpAndSettle();

    expect(
      payments.createCalls.single.source,
      SupplierPaymentSource.outsideCash,
    );
  });

  testWidgets('shows a failure snackbar and allows retry after an error', (
    tester,
  ) async {
    final payments = _FakePaymentRepository(debts: [
      _debt(invoiceId: 'inv-1', remainingAmountFils: 40000),
    ])
      // A genuinely transient failure, which is the only case that may mention
      // the connection.
      ..createError = FirebaseException(
        plugin: 'cloud_firestore',
        code: 'unavailable',
        message: 'client is offline',
      );
    await _pump(tester, payments: payments);

    await _fill(tester, amount: '40.00', allocations: {0: '40.00'});
    await _tapSave(tester);
    await tester.pumpAndSettle();

    expect(
      find.text(
        'تعذر حفظ الدفعة. تحقق من الاتصال وحاول مرة أخرى. '
        '(رمز التشخيص: SP-TXN-unavailable)',
      ),
      findsOneWidget,
    );
    expect(find.text('حفظ الدفعة'), findsOneWidget);

    // Retry reuses the same operationId.
    await _tapSave(tester);
    await tester.pumpAndSettle();
    expect(payments.createCalls, hasLength(2));
    expect(payments.newIdCalls, 1);
    expect(
      payments.createCalls[0].operationId,
      payments.createCalls[1].operationId,
    );
  });

  testWidgets('shows a permission message instead of a connection message', (
    tester,
  ) async {
    final payments = _FakePaymentRepository(debts: [
      _debt(invoiceId: 'inv-1', remainingAmountFils: 40000),
    ])
      // Firestore rules rejected the write: the user is not a financial store
      // member. Blaming the connection here would hide the real cause.
      ..createError = FirebaseException(
        plugin: 'cloud_firestore',
        code: 'permission-denied',
        message: 'Missing or insufficient permissions.',
      );
    await _pump(tester, payments: payments);

    await _fill(tester, amount: '40.00', allocations: {0: '40.00'});
    await _tapSave(tester);
    await tester.pumpAndSettle();

    expect(
      find.text(
        'لا تملك صلاحية حفظ دفعات الموردين في هذا المتجر. راجع إدارة المتجر. '
        '(رمز التشخيص: SP-TXN-permission-denied)',
      ),
      findsOneWidget,
    );
    expect(
      find.text('تعذر حفظ الدفعة. تحقق من الاتصال وحاول مرة أخرى.'),
      findsNothing,
    );
  });

  testWidgets('shows a data-conflict message when the debt changed under us', (
    tester,
  ) async {
    final payments = _FakePaymentRepository(debts: [
      _debt(invoiceId: 'inv-1', remainingAmountFils: 40000),
    ])
      // The repository throws ArgumentError from phase 2 when the debt is no
      // longer OPEN or its remaining balance no longer covers the allocation.
      ..createError = ArgumentError(
        'Allocation amount 40000 exceeds remaining debt 0 for invoice inv-1.',
      );
    await _pump(tester, payments: payments);

    await _fill(tester, amount: '40.00', allocations: {0: '40.00'});
    await _tapSave(tester);
    await tester.pumpAndSettle();

    expect(
      find.text(
        'تغيّرت بيانات الفاتورة أثناء الحفظ. '
        'أعد تحميل قائمة الديون ثم أعد المحاولة. '
        '(رمز التشخيص: SP-TXN-ArgumentError)',
      ),
      findsOneWidget,
    );
    expect(
      find.text('تعذر حفظ الدفعة. تحقق من الاتصال وحاول مرة أخرى.'),
      findsNothing,
    );
  });

  testWidgets('reports a renamed supplier only when the names really differ', (
    tester,
  ) async {
    final payments = _FakePaymentRepository(debts: [
      _debt(invoiceId: 'inv-1', remainingAmountFils: 40000),
    ])
      // Phase 2 was refused and the re-read showed the company name stored on
      // the debt no longer matches the current supplier name.
      ..createError = FirebaseException(
        plugin: 'cloud_firestore',
        code: 'permission-denied',
      )
      ..createConflict = SupplierPaymentConflictReason.companyNameMismatch;
    await _pump(tester, payments: payments);

    await _fill(tester, amount: '40.00', allocations: {0: '40.00'});
    await _tapSave(tester);
    await tester.pumpAndSettle();

    expect(
      find.text(
        'بيانات المورد الحالي لا تطابق الفواتير المسجّلة لها. '
        'لا يمكن تسجيل الدفعة حتى تتطابق البيانات؛ راجع إدارة المتجر.',
      ),
      findsOneWidget,
    );
    // A real conflict must not be reported as a permissions problem.
    expect(find.textContaining('لا تملك صلاحية'), findsNothing);
    expect(find.textContaining('تعذر حفظ الدفعة'), findsNothing);
  });

  testWidgets('reports a cancelled invoice instead of a permissions problem', (
    tester,
  ) async {
    final payments = _FakePaymentRepository(debts: [
      _debt(invoiceId: 'inv-1', remainingAmountFils: 40000),
    ])
      ..createError = FirebaseException(
        plugin: 'cloud_firestore',
        code: 'permission-denied',
      )
      ..createConflict = SupplierPaymentConflictReason.invoiceNotActive;
    await _pump(tester, payments: payments);

    await _fill(tester, amount: '40.00', allocations: {0: '40.00'});
    await _tapSave(tester);
    await tester.pumpAndSettle();

    expect(
      find.text(
        'أحد الفواتير المختارة أصبح ملغى. '
        'أعد تحميل قائمة الديون ثم أعد المحاولة.',
      ),
      findsOneWidget,
    );
    expect(find.textContaining('لا تملك صلاحية'), findsNothing);
    expect(find.textContaining('لا تطابق الفواتير'), findsNothing);
  });

  testWidgets('reports a balance conflict instead of a permissions problem', (
    tester,
  ) async {
    final payments = _FakePaymentRepository(debts: [
      _debt(invoiceId: 'inv-1', remainingAmountFils: 40000),
    ])
      ..createError = FirebaseException(
        plugin: 'cloud_firestore',
        code: 'permission-denied',
      )
      ..createConflict = SupplierPaymentConflictReason.allocationExceedsRemaining;
    await _pump(tester, payments: payments);

    await _fill(tester, amount: '40.00', allocations: {0: '40.00'});
    await _tapSave(tester);
    await tester.pumpAndSettle();

    expect(
      find.text(
        'المبلغ المخصّص يتجاوز الرصيد المتبقي للفاتورة. '
        'أعد تحميل قائمة الديون ثم أعد المحاولة.',
      ),
      findsOneWidget,
    );
    expect(find.textContaining('لا تملك صلاحية'), findsNothing);
    expect(find.textContaining('لا تطابق الفواتير'), findsNothing);
  });

  testWidgets('keeps an honest general message when no cause is established', (
    tester,
  ) async {
    final payments = _FakePaymentRepository(debts: [
      _debt(invoiceId: 'inv-1', remainingAmountFils: 40000),
    ])
      // Phase 2 refused, but every re-read precondition still holds, so no
      // precise cause may be claimed.
      ..createError = FirebaseException(
        plugin: 'cloud_firestore',
        code: 'permission-denied',
      );
    await _pump(tester, payments: payments);

    await _fill(tester, amount: '40.00', allocations: {0: '40.00'});
    await _tapSave(tester);
    await tester.pumpAndSettle();

    expect(
      find.text(
        'لا تملك صلاحية حفظ دفعات الموردين في هذا المتجر. راجع إدارة المتجر. '
        '(رمز التشخيص: SP-TXN-permission-denied)',
      ),
      findsOneWidget,
    );
    expect(find.textContaining('لا تطابق الفواتير'), findsNothing);
    expect(find.textContaining('أصبح ملغى'), findsNothing);
  });

  testWidgets('shows the already-exists message when the payment is a duplicate', (
    tester,
  ) async {
    final payments = _FakePaymentRepository(debts: [
      _debt(invoiceId: 'inv-1', remainingAmountFils: 40000),
    ])
      ..throwAlreadyExists = true;
    await _pump(tester, payments: payments);

    await _fill(tester, amount: '40.00', allocations: {0: '40.00'});
    await _tapSave(tester);
    await tester.pumpAndSettle();

    expect(
      find.text('تم تسجيل هذه الدفعة مسبقاً؛ لم تُنشأ دفعة جديدة.'),
      findsOneWidget,
    );
  });

  testWidgets('blocks double-press so only one payment is created', (
    tester,
  ) async {
    final payments = _FakePaymentRepository(debts: [
      _debt(invoiceId: 'inv-1', remainingAmountFils: 40000),
    ])
      ..createGate = Completer<void>();
    await _pump(tester, payments: payments);

    await _fill(tester, amount: '40.00', allocations: {0: '40.00'});
    final saveButton = find.byType(FilledButton);
    await tester.tap(saveButton, warnIfMissed: false);
    await tester.pump();
    // Tap again while the first save is still in flight.
    await tester.tap(saveButton, warnIfMissed: false);
    await tester.pump();

    payments.createGate!.complete();
    await tester.pumpAndSettle();

    expect(payments.createCalls, hasLength(1));
    expect(payments.newIdCalls, 1);
  });
}
