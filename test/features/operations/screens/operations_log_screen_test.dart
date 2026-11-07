import 'package:cloud_firestore/cloud_firestore.dart'
    show CollectionReference, Timestamp, WriteBatch;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mark_aap/data/models/financial_operation_model.dart';
import 'package:mark_aap/data/models/user_model.dart';
import 'package:mark_aap/data/repositories/financial_operation_repository.dart';
import 'package:mark_aap/data/repositories/user_repository.dart';
import 'package:mark_aap/features/operations/screens/operations_log_screen.dart';

class _FakeOperationRepository implements FinancialOperationRepository {
  _FakeOperationRepository({required this.entries});

  final List<FinancialOperationLogEntry> entries;
  Object? listError;
  String? requestedStoreId;
  String? requestedUserId;
  bool? requestedAdminAccess;

  @override
  CollectionReference<Map<String, dynamic>> operations(String storeId) =>
      throw UnimplementedError();

  @override
  Future<List<FinancialOperationLogEntry>> listOperations({
    required String storeId,
    required bool isAdmin,
    required String currentUserId,
  }) async {
    requestedStoreId = storeId;
    requestedAdminAccess = isAdmin;
    requestedUserId = currentUserId;
    if (listError case final error?) {
      listError = null;
      throw error;
    }
    return entries;
  }
}

class _FakeUserRepository implements UserRepository {
  _FakeUserRepository(this.names);

  final Map<String, String?> names;

  @override
  Future<String?> getDisplayName({required String uid}) async => names[uid];

  @override
  void addUserAndMembershipsToBatch({
    required WriteBatch batch,
    required String storeId,
    required String uid,
    required String displayName,
    required String email,
    required String role,
  }) => throw UnimplementedError();

  @override
  Future<UserModel?> getCurrentUserSession({required String uid}) =>
      throw UnimplementedError();

  @override
  Future<UserModel?> getUserProfile({
    required String storeId,
    required String uid,
    Map<String, dynamic>? accountData,
  }) => throw UnimplementedError();
}

const _admin = UserModel(
  uid: 'admin-1',
  storeId: 'store-1',
  name: 'Admin User',
  email: 'admin@example.com',
  role: 'ADMIN',
  isActive: true,
);

const _employee = UserModel(
  uid: 'employee-1',
  storeId: 'store-1',
  name: 'Employee User',
  email: 'employee@example.com',
  role: 'EMPLOYEE',
  isActive: true,
);

FinancialOperationLogEntry _entry({
  required String operationId,
  required FinancialOperationType type,
  required int createdAtMillis,
  String createdBy = 'employee-1',
  int? amountFils,
  String? cancellationReason,
}) {
  final operation = FinancialOperationModel(
    operationId: operationId,
    type: type,
    createdBy: createdBy,
    createdAt: Timestamp.fromMillisecondsSinceEpoch(createdAtMillis),
    status: FinancialOperationStatus.completed,
    retryCount: 0,
    invoiceId: switch (type) {
      FinancialOperationType.createPurchaseInvoice => operationId,
      FinancialOperationType.cancelPurchaseInvoice => 'invoice-1',
      _ => null,
    },
    paymentId: switch (type) {
      FinancialOperationType.createSupplierPayment => operationId,
      FinancialOperationType.cancelSupplierPayment => 'payment-1',
      _ => null,
    },
    withdrawalId: switch (type) {
      FinancialOperationType.createManualWithdrawal => operationId,
      FinancialOperationType.cancelManualWithdrawal => 'withdrawal-1',
      _ => null,
    },
    depositId: type == FinancialOperationType.createCashDeposit
        ? operationId
        : null,
    cashBoxId: switch (type) {
      FinancialOperationType.setOpeningBalance ||
      FinancialOperationType.amendOpeningBalance => 'openingBalance',
      _ => null,
    },
  );
  return FinancialOperationLogEntry(
    operation: operation,
    amountFils: amountFils,
    cancellationReason: cancellationReason,
  );
}

Future<void> _pump(
  WidgetTester tester, {
  required UserModel user,
  required _FakeOperationRepository repository,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: OperationsLogScreen(
        user: user,
        repository: repository,
        userRepository: _FakeUserRepository({
          'admin-1': 'Admin User',
          'employee-1': 'Employee User',
        }),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'shows newest operations with user, amount and cancellation details',
    (tester) async {
      final repository = _FakeOperationRepository(
        entries: [
          _entry(
            operationId: 'invoice-1',
            type: FinancialOperationType.createPurchaseInvoice,
            createdAtMillis: 1000,
            amountFils: 10000,
          ),
          _entry(
            operationId: 'cancel-invoice-1',
            type: FinancialOperationType.cancelPurchaseInvoice,
            createdAtMillis: 2000,
            createdBy: 'admin-1',
            amountFils: 10000,
            cancellationReason: 'تم إدخال الفاتورة مرتين',
          ),
        ],
      );
      await _pump(tester, user: _admin, repository: repository);

      expect(find.text('سجل العمليات'), findsOneWidget);
      expect(find.text('إلغاء فاتورة مشتريات'), findsOneWidget);
      expect(find.text('إنشاء فاتورة مشتريات'), findsOneWidget);
      expect(find.text('ألغى العملية: Admin User'), findsOneWidget);
      expect(find.text('المبلغ: 10.00 د.أ'), findsNWidgets(2));
      expect(find.text('تفاصيل الإلغاء'), findsOneWidget);
      expect(find.text('سبب الإلغاء: تم إدخال الفاتورة مرتين'), findsOneWidget);

      final newest = tester.getTopLeft(find.text('إلغاء فاتورة مشتريات')).dy;
      final oldest = tester.getTopLeft(find.text('إنشاء فاتورة مشتريات')).dy;
      expect(newest, lessThan(oldest));
      expect(find.byIcon(Icons.delete), findsNothing);
      expect(find.byIcon(Icons.edit), findsNothing);
    },
  );

  testWidgets('filters operations by type', (tester) async {
    final repository = _FakeOperationRepository(
      entries: [
        _entry(
          operationId: 'payment-1',
          type: FinancialOperationType.createSupplierPayment,
          createdAtMillis: 1000,
          amountFils: 5000,
        ),
        _entry(
          operationId: 'cancel-payment-1',
          type: FinancialOperationType.cancelSupplierPayment,
          createdAtMillis: 2000,
          amountFils: 5000,
          cancellationReason: 'تم التسجيل بالخطأ',
        ),
      ],
    );
    await _pump(tester, user: _admin, repository: repository);

    await tester.tap(
      find.byType(DropdownButtonFormField<FinancialOperationType?>),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('إلغاء دفعة مورد').last);
    await tester.pumpAndSettle();

    expect(find.text('إنشاء دفعة مورد'), findsNothing);
    expect(find.text('إلغاء دفعة مورد'), findsNWidgets(2));
    expect(find.text('مسح الفلاتر'), findsOneWidget);
  });

  testWidgets('requests only the signed-in employee operations', (
    tester,
  ) async {
    final repository = _FakeOperationRepository(
      entries: [
        _entry(
          operationId: 'employee-withdrawal',
          type: FinancialOperationType.createManualWithdrawal,
          createdAtMillis: 1000,
          amountFils: 7500,
        ),
      ],
    );
    await _pump(tester, user: _employee, repository: repository);

    expect(repository.requestedStoreId, 'store-1');
    expect(repository.requestedUserId, 'employee-1');
    expect(repository.requestedAdminAccess, false);
    expect(find.text('المستخدم: Employee User'), findsOneWidget);
  });

  testWidgets('shows an explicit load error and retries', (tester) async {
    final repository = _FakeOperationRepository(
      entries: [
        _entry(
          operationId: 'deposit-1',
          type: FinancialOperationType.createCashDeposit,
          createdAtMillis: 1000,
        ),
      ],
    )..listError = StateError('temporary');
    await _pump(tester, user: _admin, repository: repository);

    expect(find.text('تعذر تحميل سجل العمليات.'), findsOneWidget);
    await tester.tap(find.text('إعادة المحاولة'));
    await tester.pumpAndSettle();
    expect(find.text('إيداع نقدي'), findsOneWidget);
  });
}
