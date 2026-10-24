import 'package:cloud_firestore/cloud_firestore.dart'
    show CollectionReference, Timestamp;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mark_aap/data/models/supplier_debt_model.dart';
import 'package:mark_aap/data/models/supplier_payment_model.dart';
import 'package:mark_aap/data/models/user_model.dart';
import 'package:mark_aap/data/repositories/supplier_payment_repository.dart';
import 'package:mark_aap/features/suppliers/screens/supplier_payment_log_screen.dart';

class _FakePaymentRepository implements SupplierPaymentRepository {
  _FakePaymentRepository({this.payments = const []});

  List<SupplierPaymentModel> payments;
  Object? listError;

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
  Future<SupplierPaymentModel> getPayment(String storeId, String paymentId) =>
      throw UnimplementedError();

  @override
  Future<List<SupplierPaymentModel>> listPayments(String storeId) async {
    if (listError case final error?) {
      listError = null;
      throw error;
    }
    return payments;
  }

  @override
  Future<SupplierDebtModel> getDebt(String storeId, String invoiceId) =>
      throw UnimplementedError();

  @override
  Future<List<SupplierDebtModel>> listOpenDebtsForCompany(
    String storeId,
    String companyId,
  ) async => [];

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
  }) => throw UnimplementedError();

  @override
  Future<String> cancelPayment({
    required String storeId,
    required String paymentId,
    required String reason,
    required String cancelledBy,
  }) => throw UnimplementedError();
}

const _user = UserModel(
  uid: 'u1',
  storeId: 'store-1',
  name: 'User',
  email: 'u@example.com',
  role: 'ADMIN',
  isActive: true,
);

SupplierPaymentModel _payment({
  required String paymentId,
  required int amountFils,
  SupplierPaymentSource source = SupplierPaymentSource.shopCash,
  SupplierPaymentStatus status = SupplierPaymentStatus.active,
  int createdAtMillis = 0,
}) => SupplierPaymentModel(
  paymentId: paymentId,
  companyId: 'company-1',
  companyName: 'Supplier',
  amountFils: amountFils,
  source: source,
  status: status,
  allocationCount: 1,
  allocation1InvoiceId: 'inv-$paymentId',
  allocation1AmountFils: amountFils,
  createdAt: Timestamp.fromMillisecondsSinceEpoch(createdAtMillis),
  createdBy: 'admin-1',
  operationId: paymentId,
  cancelledAt: status == SupplierPaymentStatus.cancelled
      ? Timestamp.fromMillisecondsSinceEpoch(createdAtMillis)
      : null,
  cancelledBy: status == SupplierPaymentStatus.cancelled ? 'admin-1' : null,
  cancellationReason: status == SupplierPaymentStatus.cancelled
      ? 'إلغاء تجريبي'
      : null,
  cancellationOperationId: status == SupplierPaymentStatus.cancelled
      ? paymentId
      : null,
);

Future<void> _pump(
  WidgetTester tester, {
  required _FakePaymentRepository payments,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: SupplierPaymentLogScreen(user: _user, repository: payments),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('lists payments newest first with amount, source and date', (
    tester,
  ) async {
    final payments = _FakePaymentRepository(
      payments: [
        _payment(paymentId: 'p-old', amountFils: 10000, createdAtMillis: 100),
        _payment(
          paymentId: 'p-new',
          amountFils: 65000,
          source: SupplierPaymentSource.outsideCash,
          createdAtMillis: 900,
        ),
      ],
    );
    await _pump(tester, payments: payments);

    expect(find.text('سجل دفعات الموردين'), findsOneWidget);
    expect(find.text('Supplier'), findsNWidgets(2));
    expect(find.textContaining('10.00 د.أ'), findsOneWidget);
    expect(find.textContaining('65.00 د.أ'), findsOneWidget);
    expect(find.textContaining('كاش خارج الصندوق'), findsOneWidget);
    expect(find.text('نشطة'), findsNWidgets(2));
    // Newest (65.00) must be rendered above the older (10.00) one.
    final newest = tester.getTopLeft(find.textContaining('65.00 د.أ')).dy;
    final oldest = tester.getTopLeft(find.textContaining('10.00 د.أ')).dy;
    expect(oldest, greaterThan(newest));
  });

  testWidgets('shows a cancelled payment with its status label', (
    tester,
  ) async {
    final payments = _FakePaymentRepository(
      payments: [
        _payment(
          paymentId: 'p-cancelled',
          amountFils: 20000,
          status: SupplierPaymentStatus.cancelled,
        ),
      ],
    );
    await _pump(tester, payments: payments);

    expect(find.text('ملغاة'), findsOneWidget);
  });

  testWidgets('shows an empty state when there are no payments', (
    tester,
  ) async {
    await _pump(tester, payments: _FakePaymentRepository(payments: []));

    expect(find.text('لا توجد دفعات مسجلة بعد.'), findsOneWidget);
  });

  testWidgets('shows a load error and retries', (tester) async {
    final payments = _FakePaymentRepository(
      payments: [_payment(paymentId: 'p-1', amountFils: 30000)],
    )..listError = StateError('temporary');
    await _pump(tester, payments: payments);
    expect(find.text('تعذر تحميل سجل دفعات الموردين.'), findsOneWidget);

    await tester.tap(find.text('إعادة المحاولة'));
    await tester.pumpAndSettle();
    expect(find.textContaining('30.00 د.أ'), findsOneWidget);
  });
}
