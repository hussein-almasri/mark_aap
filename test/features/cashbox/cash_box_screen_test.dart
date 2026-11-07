import 'package:cloud_firestore/cloud_firestore.dart'
    show CollectionReference, Timestamp;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mark_aap/data/models/cash_box_models.dart';
import 'package:mark_aap/data/models/cash_deposit_model.dart';
import 'package:mark_aap/data/models/cash_withdrawal_model.dart';
import 'package:mark_aap/data/models/user_model.dart';
import 'package:mark_aap/data/repositories/cash_box_repository.dart';
import 'package:mark_aap/data/repositories/cash_withdrawal_repository.dart';
import 'package:mark_aap/features/cashbox/cash_box_screen.dart';

class _FakeCashBoxRepository implements CashBoxRepository {
  _FakeCashBoxRepository({this.snapshot, this.error});

  CashBoxSnapshot? snapshot;
  Object? error;
  final depositCalls = <Map<String, dynamic>>[];
  final setOpeningCalls = <Map<String, dynamic>>[];
  final amendOpeningCalls = <Map<String, dynamic>>[];

  @override
  CollectionReference<Map<String, dynamic>> cashBox(String storeId) =>
      throw UnimplementedError();

  @override
  CollectionReference<Map<String, dynamic>> cashDeposits(String storeId) =>
      throw UnimplementedError();

  @override
  CollectionReference<Map<String, dynamic>> operations(String storeId) =>
      throw UnimplementedError();

  @override
  Future<OpeningBalanceModel?> getOpeningBalance(String storeId) async =>
      snapshot?.openingBalance;

  @override
  Future<List<CashDepositModel>> listDeposits(String storeId) async =>
      snapshot?.deposits ?? const [];

  @override
  Future<CashBoxSnapshot> loadCashBox(String storeId) async {
    final capturedError = error;
    if (capturedError != null) throw capturedError;
    return snapshot ??
        CashBoxSnapshot.fromDocuments(
          openingBalance: null,
          deposits: const [],
          withdrawals: const [],
        );
  }

  @override
  Future<void> setOpeningBalance({
    required String storeId,
    required int openingBalanceFils,
    required String operationId,
    required String createdBy,
  }) async {
    setOpeningCalls.add({
      'storeId': storeId,
      'openingBalanceFils': openingBalanceFils,
      'operationId': operationId,
      'createdBy': createdBy,
    });
  }

  @override
  Future<void> amendOpeningBalance({
    required String storeId,
    required int openingBalanceFils,
    required String operationId,
    required String amendedBy,
    required String reason,
  }) async {
    amendOpeningCalls.add({
      'storeId': storeId,
      'openingBalanceFils': openingBalanceFils,
      'operationId': operationId,
      'amendedBy': amendedBy,
      'reason': reason,
    });
  }

  @override
  Future<String> createDeposit({
    required String storeId,
    required int amountFils,
    required String note,
    required String operationId,
    required String createdBy,
  }) async {
    depositCalls.add({
      'storeId': storeId,
      'amountFils': amountFils,
      'note': note,
      'operationId': operationId,
      'createdBy': createdBy,
    });
    return operationId;
  }
}

class _FakeCashWithdrawalRepository implements CashWithdrawalRepository {
  _FakeCashWithdrawalRepository(this.cashBox);

  final _FakeCashBoxRepository cashBox;
  final createCalls = <Map<String, dynamic>>[];
  final cancelCalls = <Map<String, dynamic>>[];
  Object? createError;
  Object? cancelError;

  @override
  CollectionReference<Map<String, dynamic>> cashWithdrawals(String storeId) =>
      throw UnimplementedError();

  @override
  CollectionReference<Map<String, dynamic>> operations(String storeId) =>
      throw UnimplementedError();

  @override
  String newOperationId(String storeId) => 'withdrawal-operation-1';

  @override
  String newWithdrawalId(String storeId) => 'withdrawal-1';

  @override
  Future<CashWithdrawalModel> getWithdrawal(
    String storeId,
    String withdrawalId,
  ) => throw UnimplementedError();

  @override
  Future<List<CashWithdrawalModel>> listWithdrawals(String storeId) =>
      throw UnimplementedError();

  @override
  Future<String> createManualWithdrawal({
    required String storeId,
    required int amountFils,
    required CashWithdrawalType type,
    required String withdrawalId,
    required String createdBy,
    required String operationId,
    String? note,
  }) async {
    if (createError case final error?) throw error;
    createCalls.add({
      'storeId': storeId,
      'amountFils': amountFils,
      'type': type,
      'withdrawalId': withdrawalId,
      'createdBy': createdBy,
      'operationId': operationId,
      'note': note,
    });
    final snapshot = cashBox.snapshot!;
    final withdrawals = [
      ...snapshot.withdrawals,
      CashWithdrawalModel(
        withdrawalId: withdrawalId,
        amountFils: amountFils,
        type: type,
        createdAt: Timestamp.fromMillisecondsSinceEpoch(3000),
        createdBy: createdBy,
        status: CashWithdrawalStatus.active,
        note: note,
        operationId: operationId,
      ),
    ];
    cashBox.snapshot = CashBoxSnapshot.fromDocuments(
      openingBalance: snapshot.openingBalance,
      deposits: snapshot.deposits,
      withdrawals: withdrawals,
    );
    return withdrawalId;
  }

  @override
  Future<void> cancelWithdrawal({
    required String storeId,
    required String withdrawalId,
    required String operationId,
    required String cancelledBy,
    required String reason,
  }) async {
    if (cancelError case final error?) throw error;
    cancelCalls.add({
      'storeId': storeId,
      'withdrawalId': withdrawalId,
      'operationId': operationId,
      'cancelledBy': cancelledBy,
      'reason': reason,
    });
    final snapshot = cashBox.snapshot!;
    final withdrawals = snapshot.withdrawals.map((withdrawal) {
      if (withdrawal.withdrawalId != withdrawalId) return withdrawal;
      return CashWithdrawalModel.fromData(
        withdrawalId: withdrawal.withdrawalId,
        data: {
          ...withdrawal.toData(),
          'status': 'CANCELLED',
          'cancelledAt': Timestamp.fromMillisecondsSinceEpoch(4000),
          'cancelledBy': cancelledBy,
          'cancellationReason': reason,
          'cancellationOperationId': operationId,
        },
      );
    }).toList();
    cashBox.snapshot = CashBoxSnapshot.fromDocuments(
      openingBalance: snapshot.openingBalance,
      deposits: snapshot.deposits,
      withdrawals: withdrawals,
    );
  }
}

const _admin = UserModel(
  uid: 'admin-1',
  storeId: 'store-1',
  name: 'Admin',
  email: 'admin@example.com',
  role: 'ADMIN',
  isActive: true,
);

const _employee = UserModel(
  uid: 'employee-1',
  storeId: 'store-1',
  name: 'Employee',
  email: 'employee@example.com',
  role: 'EMPLOYEE',
  isActive: true,
);

CashBoxSnapshot _snapshotWithBalance() {
  final opening = OpeningBalanceModel(
    openingBalanceFils: 100000,
    createdAt: Timestamp.fromMillisecondsSinceEpoch(0),
    createdBy: 'admin-1',
    operationId: 'set-opening-1',
  );
  final deposit = CashDepositModel(
    depositId: 'deposit-1',
    amountFils: 20000,
    note: 'Refill',
    createdAt: Timestamp.fromMillisecondsSinceEpoch(1000),
    createdBy: 'admin-1',
    status: CashDepositStatus.active,
    operationId: 'deposit-1',
  );
  final withdrawal = CashWithdrawalModel(
    withdrawalId: 'manual-1',
    amountFils: 5000,
    type: CashWithdrawalType.shopExpense,
    createdAt: Timestamp.fromMillisecondsSinceEpoch(2000),
    createdBy: 'admin-1',
    status: CashWithdrawalStatus.active,
    operationId: 'manual-operation-1',
    note: 'محروقات',
  );
  return CashBoxSnapshot.fromDocuments(
    openingBalance: opening,
    deposits: [deposit],
    withdrawals: [withdrawal],
  );
}

Widget _screen(
  UserModel user,
  CashBoxRepository repository, {
  CashWithdrawalRepository? withdrawalRepository,
}) => MaterialApp(
  home: CashBoxScreen(
    user: user,
    repository: repository,
    withdrawalRepository: withdrawalRepository,
  ),
);

void main() {
  testWidgets('shows the computed balance, totals and ledger rows', (
    tester,
  ) async {
    final repo = _FakeCashBoxRepository(snapshot: _snapshotWithBalance());
    await tester.pumpWidget(_screen(_admin, repo));
    await tester.pumpAndSettle();

    // current = 100.000 + 20.000 - 5.000 = 115.000 fils = 115.00 د.أ
    expect(find.text('115.00 د.أ'), findsOneWidget);
    expect(find.text('20.00 د.أ'), findsOneWidget);
    expect(find.text('5.00 د.أ'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('+20.00 د.أ'), 250);
    expect(find.text('+20.00 د.أ'), findsOneWidget);
    expect(find.text('-5.00 د.أ'), findsOneWidget);
    expect(find.text('إيداع نقدي'), findsOneWidget);
    expect(find.text('مصروف محل'), findsOneWidget);
  });

  testWidgets('admin sees the deposit and opening-balance actions', (
    tester,
  ) async {
    final repo = _FakeCashBoxRepository(snapshot: _snapshotWithBalance());
    await tester.pumpWidget(_screen(_admin, repo));
    await tester.pumpAndSettle();

    expect(find.text('تسجيل إيداع نقدي'), findsOneWidget);
    expect(find.text('تعديل مُدقَّق'), findsOneWidget);
    expect(find.text('تسجيل سحب نقدي'), findsOneWidget);
    await tester.scrollUntilVisible(find.byTooltip('إلغاء السحب النقدي'), 250);
    expect(find.byTooltip('إلغاء السحب النقدي'), findsOneWidget);
  });

  testWidgets('employee sees the ledger but no admin actions', (tester) async {
    final repo = _FakeCashBoxRepository(snapshot: _snapshotWithBalance());
    await tester.pumpWidget(_screen(_employee, repo));
    await tester.pumpAndSettle();

    expect(find.text('115.00 د.أ'), findsOneWidget);
    expect(find.text('تسجيل إيداع نقدي'), findsNothing);
    expect(find.text('تسجيل سحب نقدي'), findsNothing);
    expect(find.text('تعديل مُدقَّق'), findsNothing);
    expect(find.text('تعيين الرصيد الافتتاحي'), findsNothing);
    expect(find.byTooltip('إلغاء السحب النقدي'), findsNothing);
  });

  testWidgets('prompts the admin when the opening balance is missing', (
    tester,
  ) async {
    final repo = _FakeCashBoxRepository();
    await tester.pumpWidget(_screen(_admin, repo));
    await tester.pumpAndSettle();

    expect(find.text('الرصيد الافتتاحي للصندوق غير محدد بعد.'), findsOneWidget);
    expect(find.text('تعيين الرصيد الافتتاحي'), findsOneWidget);
    expect(find.text('115.00 د.أ'), findsNothing);
  });

  testWidgets('shows a clear error instead of a partial balance', (
    tester,
  ) async {
    final repo = _FakeCashBoxRepository(
      error: const CashBoxDataException(
        'Two active withdrawals claim invoice inv-1.',
      ),
    );
    await tester.pumpWidget(_screen(_admin, repo));
    await tester.pumpAndSettle();

    expect(find.text('تعذر حساب رصيد الصندوق'), findsOneWidget);
    expect(
      find.text('Two active withdrawals claim invoice inv-1.'),
      findsOneWidget,
    );
    expect(find.text('115.00 د.أ'), findsNothing);
  });

  testWidgets('records a deposit through the repository', (tester) async {
    final repo = _FakeCashBoxRepository(snapshot: _snapshotWithBalance());
    await tester.pumpWidget(_screen(_admin, repo));
    await tester.pumpAndSettle();

    await tester.tap(find.text('تسجيل إيداع نقدي'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).at(0), '10.00');
    await tester.enterText(find.byType(TextField).at(1), 'إيداع يومي');
    await tester.tap(find.text('حفظ'));
    await tester.pumpAndSettle();

    expect(repo.depositCalls, hasLength(1));
    expect(repo.depositCalls.single['amountFils'], 10000);
    expect(repo.depositCalls.single['note'], 'إيداع يومي');
    expect(repo.depositCalls.single['createdBy'], 'admin-1');
  });

  testWidgets('creates a manual withdrawal with a positive amount and note', (
    tester,
  ) async {
    final cashBox = _FakeCashBoxRepository(snapshot: _snapshotWithBalance());
    final withdrawals = _FakeCashWithdrawalRepository(cashBox);
    await tester.pumpWidget(
      _screen(_admin, cashBox, withdrawalRepository: withdrawals),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('تسجيل سحب نقدي'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('حفظ'));
    await tester.pumpAndSettle();
    expect(find.text('المبلغ مطلوب.'), findsOneWidget);
    expect(find.text('سبب السحب مطلوب.'), findsOneWidget);
    expect(withdrawals.createCalls, isEmpty);

    await tester.enterText(find.byType(TextField).at(0), '0');
    await tester.enterText(find.byType(TextField).at(1), 'فاتورة كهرباء');
    await tester.tap(find.text('حفظ'));
    await tester.pumpAndSettle();
    expect(find.text('يجب أن يكون أكبر من صفر.'), findsOneWidget);
    expect(withdrawals.createCalls, isEmpty);

    await tester.enterText(find.byType(TextField).at(0), '10.00');
    await tester.tap(find.text('حفظ'));
    await tester.pumpAndSettle();

    expect(withdrawals.createCalls, hasLength(1));
    expect(withdrawals.createCalls.single['storeId'], 'store-1');
    expect(withdrawals.createCalls.single['amountFils'], 10000);
    expect(
      withdrawals.createCalls.single['type'],
      CashWithdrawalType.shopExpense,
    );
    expect(withdrawals.createCalls.single['note'], 'فاتورة كهرباء');
    expect(withdrawals.createCalls.single['createdBy'], 'admin-1');
    expect(find.text('105.00 د.أ'), findsOneWidget);
    expect(find.text('-10.00 د.أ'), findsOneWidget);
  });

  testWidgets('admin cancels only a manual withdrawal and restores balance', (
    tester,
  ) async {
    final cashBox = _FakeCashBoxRepository(snapshot: _snapshotWithBalance());
    final withdrawals = _FakeCashWithdrawalRepository(cashBox);
    await tester.pumpWidget(
      _screen(_admin, cashBox, withdrawalRepository: withdrawals),
    );
    await tester.pumpAndSettle();

    expect(find.text('115.00 د.أ'), findsOneWidget);
    await tester.scrollUntilVisible(find.byTooltip('إلغاء السحب النقدي'), 250);
    await tester.tap(find.byTooltip('إلغاء السحب النقدي'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('تأكيد الإلغاء'));
    await tester.pumpAndSettle();
    expect(find.text('سبب الإلغاء مطلوب.'), findsOneWidget);
    expect(withdrawals.cancelCalls, isEmpty);

    await tester.enterText(find.byType(TextField), 'تم إدخاله بالخطأ');
    await tester.tap(find.text('تأكيد الإلغاء'));
    await tester.pumpAndSettle();

    expect(withdrawals.cancelCalls, [
      {
        'storeId': 'store-1',
        'withdrawalId': 'manual-1',
        'operationId': 'withdrawal-operation-1',
        'cancelledBy': 'admin-1',
        'reason': 'تم إدخاله بالخطأ',
      },
    ]);
    expect(
      cashBox.snapshot!.withdrawals.single.status,
      CashWithdrawalStatus.cancelled,
    );
    expect(find.text('120.00 د.أ'), findsOneWidget);
    expect(find.byTooltip('إلغاء السحب النقدي'), findsNothing);
  });

  testWidgets('does not offer cancellation for invoice-linked withdrawals', (
    tester,
  ) async {
    final snapshot = _snapshotWithBalance();
    final snapshotWithInvoice = CashBoxSnapshot.fromDocuments(
      openingBalance: snapshot.openingBalance,
      deposits: snapshot.deposits,
      withdrawals: [
        ...snapshot.withdrawals,
        CashWithdrawalModel(
          withdrawalId: 'invoice_inv-1',
          amountFils: 1000,
          type: CashWithdrawalType.purchaseInvoice,
          invoiceId: 'inv-1',
          createdAt: Timestamp.fromMillisecondsSinceEpoch(3000),
          createdBy: 'admin-1',
          status: CashWithdrawalStatus.active,
        ),
      ],
    );
    final cashBox = _FakeCashBoxRepository(snapshot: snapshotWithInvoice);
    await tester.pumpWidget(_screen(_admin, cashBox));
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(find.byTooltip('إلغاء السحب النقدي'), 250);
    expect(find.byTooltip('إلغاء السحب النقدي'), findsOneWidget);
  });

  testWidgets('sets the opening balance when none exists', (tester) async {
    final repo = _FakeCashBoxRepository();
    await tester.pumpWidget(_screen(_admin, repo));
    await tester.pumpAndSettle();

    await tester.tap(find.text('تعيين الرصيد الافتتاحي'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).at(0), '75.000');
    await tester.tap(find.text('حفظ'));
    await tester.pumpAndSettle();

    expect(repo.setOpeningCalls, hasLength(1));
    expect(repo.setOpeningCalls.single['openingBalanceFils'], 75000);
    expect(repo.amendOpeningCalls, isEmpty);
  });
}
