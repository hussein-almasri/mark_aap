import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart'
    show CollectionReference, Timestamp;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mark_aap/data/models/supplier_debt_model.dart';
import 'package:mark_aap/data/models/supplier_payment_model.dart';
import 'package:mark_aap/data/models/user_model.dart';
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
  Completer<void>? createGate;
  bool throwAlreadyExists = false;

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
      throw error;
    }
    return operationId;
  }
}

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

Future<void> _pump(
  WidgetTester tester, {
  required _FakePaymentRepository payments,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: SupplierPaymentFormScreen(
        user: _user,
        companyId: 'company-1',
        companyName: 'Supplier',
        paymentRepository: payments,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// Enters the payment amount and the per-debt allocation amounts.
Future<void> _enterAmounts(
  WidgetTester tester, {
  required String amount,
  required List<String> allocations,
}) async {
  final amountField = find.widgetWithText(TextFormField, 'مبلغ الدفعة (د.أ)');
  await tester.enterText(amountField, amount);
  final allocationFields = find.byType(TextFormField);
  // Skip the amount field (index 0) and notes (last); allocations are between.
  for (var i = 0; i < allocations.length; i++) {
    await tester.enterText(allocationFields.at(i + 1), allocations[i]);
  }
  await tester.pump();
}

Future<void> _tapSave(WidgetTester tester) async {
  await tester.tap(find.byType(FilledButton));
  await tester.pump();
}

void main() {
  testWidgets('loads open debts and shows the payment form', (tester) async {
    final payments = _FakePaymentRepository(debts: [
      _debt(invoiceId: 'inv-1', remainingAmountFils: 40000),
      _debt(invoiceId: 'inv-2', remainingAmountFils: 25000, createdAtMillis: 200),
    ]);
    await _pump(tester, payments: payments);

    expect(find.text('دفعة إلى Supplier'), findsOneWidget);
    expect(find.text('فاتورة inv-1'), findsOneWidget);
    expect(find.text('فاتورة inv-2'), findsOneWidget);
    expect(find.text('كاش الصندوق'), findsOneWidget);
    expect(find.text('كاش خارج الصندوق'), findsOneWidget);
    expect(find.text('المتبقي: 40.00 د.أ'), findsOneWidget);
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
    expect(find.text('فاتورة inv-1'), findsOneWidget);
  });

  testWidgets('shows live payment, allocated and remaining totals', (
    tester,
  ) async {
    final payments = _FakePaymentRepository(debts: [
      _debt(invoiceId: 'inv-1', remainingAmountFils: 40000),
      _debt(invoiceId: 'inv-2', remainingAmountFils: 25000, createdAtMillis: 200),
    ]);
    await _pump(tester, payments: payments);

    await _enterAmounts(
      tester,
      amount: '65.00',
      allocations: ['40.00', '25.00'],
    );

    expect(find.text('مبلغ الدفعة'), findsOneWidget);
    expect(find.text('65.00 د.أ'), findsWidgets);
    expect(find.text('مجموع المخصص'), findsOneWidget);
    expect(find.text('المتبقي'), findsOneWidget);
    // Remaining (amount - allocated) is zero, shown as 0.00.
    expect(find.text('0.00 د.أ'), findsOneWidget);
  });

  testWidgets('blocks save when allocations do not sum to the amount', (
    tester,
  ) async {
    final payments = _FakePaymentRepository(debts: [
      _debt(invoiceId: 'inv-1', remainingAmountFils: 40000),
      _debt(invoiceId: 'inv-2', remainingAmountFils: 25000, createdAtMillis: 200),
    ]);
    await _pump(tester, payments: payments);

    await _enterAmounts(
      tester,
      amount: '65.00',
      allocations: ['40.00', '20.00'],
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

    await _enterAmounts(tester, amount: '45.00', allocations: ['45.00']);
    await _tapSave(tester);
    await tester.pumpAndSettle();

    expect(payments.createCalls, isEmpty);
  });

  testWidgets('saves a single-invoice payment with the exact arguments', (
    tester,
  ) async {
    final payments = _FakePaymentRepository(debts: [
      _debt(invoiceId: 'inv-1', remainingAmountFils: 40000),
    ]);
    await _pump(tester, payments: payments);

    await _enterAmounts(tester, amount: '40.00', allocations: ['40.00']);
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

    // Leave the middle debt unallocated (blank) to check slot packing.
    await _enterAmounts(
      tester,
      amount: '50.00',
      allocations: ['40.00', '', '10.00'],
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

    await _enterAmounts(tester, amount: '40.00', allocations: ['40.00']);
    await tester.tap(find.text('كاش خارج الصندوق'));
    await tester.pump();
    await _tapSave(tester);
    await tester.pumpAndSettle();

    expect(payments.createCalls.single.source, SupplierPaymentSource.outsideCash);
  });

  testWidgets('shows a failure snackbar and allows retry after an error', (
    tester,
  ) async {
    final payments = _FakePaymentRepository(debts: [
      _debt(invoiceId: 'inv-1', remainingAmountFils: 40000),
    ])
      ..createError = StateError('temporary');
    await _pump(tester, payments: payments);

    await _enterAmounts(tester, amount: '40.00', allocations: ['40.00']);
    await _tapSave(tester);
    await tester.pumpAndSettle();

    expect(
      find.text('تعذر حفظ الدفعة. تحقق من الاتصال وحاول مرة أخرى.'),
      findsOneWidget,
    );
    expect(find.text('حفظ الدفعة'), findsOneWidget);

    // Retry reuses the same operationId.
    await _tapSave(tester);
    await tester.pumpAndSettle();
    expect(payments.createCalls, hasLength(2));
    expect(payments.newIdCalls, 1);
    expect(payments.createCalls[0].operationId, payments.createCalls[1].operationId);
  });

  testWidgets('shows the already-exists message when the payment is a duplicate', (
    tester,
  ) async {
    final payments = _FakePaymentRepository(debts: [
      _debt(invoiceId: 'inv-1', remainingAmountFils: 40000),
    ])
      ..throwAlreadyExists = true;
    await _pump(tester, payments: payments);

    await _enterAmounts(tester, amount: '40.00', allocations: ['40.00']);
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

    await _enterAmounts(tester, amount: '40.00', allocations: ['40.00']);
    final saveButton = find.byType(FilledButton);
    await tester.tap(saveButton);
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
