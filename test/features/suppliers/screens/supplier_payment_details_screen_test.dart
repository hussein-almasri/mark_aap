import 'package:cloud_firestore/cloud_firestore.dart'
    show CollectionReference, Timestamp;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mark_aap/data/models/supplier_debt_model.dart';
import 'package:mark_aap/data/models/supplier_payment_model.dart';
import 'package:mark_aap/data/models/user_model.dart';
import 'package:mark_aap/data/repositories/supplier_payment_repository.dart';
import 'package:mark_aap/features/suppliers/screens/supplier_payment_details_screen.dart';

class _FakePaymentRepository implements SupplierPaymentRepository {
  _FakePaymentRepository({this.payment});

  SupplierPaymentModel? payment;
  Object? getError;

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
  CollectionReference<Map<String, dynamic>> purchaseInvoices(String storeId) =>
      throw UnimplementedError();

  @override
  String newOperationId(String storeId) => 'op-1';

  @override
  Future<SupplierPaymentModel> getPayment(String storeId, String paymentId) async {
    if (getError case final error?) {
      getError = null;
      throw error;
    }
    final value = payment;
    if (value == null) throw StateError('Supplier payment not found.');
    return value;
  }

  @override
  Future<List<SupplierPaymentModel>> listPayments(String storeId) async => [];

  @override
  Future<SupplierDebtModel> getDebt(String storeId, String invoiceId) =>
      throw UnimplementedError();

  @override
  Future<List<SupplierDebtModel>> listOpenDebtsForCompany(
    String storeId,
    String companyId,
  ) async =>
      [];

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

const _user = UserModel(
  uid: 'u1',
  storeId: 'store-1',
  name: 'User',
  email: 'u@example.com',
  role: 'ADMIN',
  isActive: true,
);

SupplierPaymentModel _multiAllocationPayment({
  SupplierPaymentSource source = SupplierPaymentSource.shopCash,
  SupplierPaymentStatus status = SupplierPaymentStatus.active,
}) => SupplierPaymentModel(
  paymentId: 'p-1',
  companyId: 'company-1',
  companyName: 'Supplier',
  amountFils: 65000,
  source: source,
  status: status,
  allocationCount: 3,
  allocation1InvoiceId: 'inv-1',
  allocation1AmountFils: 40000,
  allocation2InvoiceId: 'inv-2',
  allocation2AmountFils: 15000,
  allocation3InvoiceId: 'inv-3',
  allocation3AmountFils: 10000,
  createdAt: Timestamp.fromMillisecondsSinceEpoch(1000),
  createdBy: 'admin-1',
  operationId: 'p-1',
  notes: 'دفعة دورية',
  cancelledAt: status == SupplierPaymentStatus.cancelled
      ? Timestamp.fromMillisecondsSinceEpoch(2000)
      : null,
  cancelledBy: status == SupplierPaymentStatus.cancelled ? 'admin-1' : null,
  cancellationReason: status == SupplierPaymentStatus.cancelled
      ? 'إلغاء تجريبي'
      : null,
  cancellationOperationId: status == SupplierPaymentStatus.cancelled
      ? 'p-1'
      : null,
);

Future<void> _pump(
  WidgetTester tester, {
  required _FakePaymentRepository payments,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: SupplierPaymentDetailsScreen(
        user: _user,
        paymentId: 'p-1',
        repository: payments,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('shows the payment header with amount, source and date', (
    tester,
  ) async {
    await _pump(
      tester,
      payments: _FakePaymentRepository(payment: _multiAllocationPayment()),
    );

    expect(find.text('تفاصيل الدفعة'), findsOneWidget);
    expect(find.text('Supplier'), findsOneWidget);
    expect(find.text('65.00 د.أ'), findsWidgets);
    expect(find.textContaining('المصدر: كاش الصندوق'), findsOneWidget);
    expect(find.textContaining('التاريخ:'), findsOneWidget);
    expect(find.text('نشطة'), findsOneWidget);
  });

  testWidgets('shows each allocation with its invoice id and amount', (
    tester,
  ) async {
    await _pump(
      tester,
      payments: _FakePaymentRepository(payment: _multiAllocationPayment()),
    );

    expect(find.textContaining('توزيع الدفعة على الفواتير (3)'), findsOneWidget);
    expect(find.text('فاتورة inv-1'), findsOneWidget);
    expect(find.text('40.00 د.أ'), findsOneWidget);
    expect(find.text('فاتورة inv-2'), findsOneWidget);
    expect(find.text('15.00 د.أ'), findsOneWidget);
    expect(find.text('فاتورة inv-3'), findsOneWidget);
    expect(find.text('10.00 د.أ'), findsOneWidget);
    expect(find.text('إجمالي المخصص'), findsOneWidget);
  });

  testWidgets('shows outside cash source and cancelled status', (tester) async {
    await _pump(
      tester,
      payments: _FakePaymentRepository(
        payment: _multiAllocationPayment(
          source: SupplierPaymentSource.outsideCash,
          status: SupplierPaymentStatus.cancelled,
        ),
      ),
    );

    expect(find.textContaining('المصدر: كاش خارج الصندوق'), findsOneWidget);
    expect(find.text('ملغاة'), findsOneWidget);
  });

  testWidgets('shows the notes when present', (tester) async {
    await _pump(
      tester,
      payments: _FakePaymentRepository(payment: _multiAllocationPayment()),
    );

    expect(find.text('ملاحظات'), findsOneWidget);
    expect(find.text('دفعة دورية'), findsOneWidget);
  });

  testWidgets('shows a load error and retries', (tester) async {
    final payments = _FakePaymentRepository(payment: _multiAllocationPayment())
      ..getError = StateError('temporary');
    await _pump(tester, payments: payments);
    expect(find.text('تعذر تحميل الدفعة. حاول مرة أخرى'), findsOneWidget);

    await tester.tap(find.text('إعادة المحاولة'));
    await tester.pumpAndSettle();
    expect(find.text('تفاصيل الدفعة'), findsOneWidget);
    expect(find.text('Supplier'), findsWidgets);
  });

  testWidgets('shows a not-found message when the payment is missing', (
    tester,
  ) async {
    await _pump(tester, payments: _FakePaymentRepository(payment: null));

    expect(find.text('الدفعة غير موجودة'), findsOneWidget);
  });
}
