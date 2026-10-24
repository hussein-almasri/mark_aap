import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mark_aap/data/models/cash_box_models.dart';
import 'package:mark_aap/data/models/cash_deposit_model.dart';
import 'package:mark_aap/data/models/cash_withdrawal_model.dart';

CashWithdrawalModel _withdrawal({
  required String id,
  required int amountFils,
  CashWithdrawalType type = CashWithdrawalType.shopExpense,
  String? invoiceId,
  String? supplierPaymentId,
  CashWithdrawalStatus status = CashWithdrawalStatus.active,
  int createdAtMillis = 0,
}) =>
    CashWithdrawalModel(
      withdrawalId: id,
      amountFils: amountFils,
      type: invoiceId != null || supplierPaymentId != null
          ? CashWithdrawalType.purchaseInvoice
          : type,
      createdAt: Timestamp.fromMillisecondsSinceEpoch(createdAtMillis),
      createdBy: 'admin-1',
      status: status,
      invoiceId: invoiceId,
      supplierPaymentId: supplierPaymentId,
      cancelledAt: status == CashWithdrawalStatus.cancelled
          ? Timestamp.fromMillisecondsSinceEpoch(createdAtMillis + 1)
          : null,
      cancelledBy: status == CashWithdrawalStatus.cancelled ? 'admin-1' : null,
      cancellationReason:
          status == CashWithdrawalStatus.cancelled ? 'Reversed' : null,
      cancellationOperationId:
          status == CashWithdrawalStatus.cancelled ? 'cancel-$id' : null,
    );

CashDepositModel _deposit({
  required String id,
  required int amountFils,
  int createdAtMillis = 0,
}) =>
    CashDepositModel(
      depositId: id,
      amountFils: amountFils,
      note: 'note',
      createdAt: Timestamp.fromMillisecondsSinceEpoch(createdAtMillis),
      createdBy: 'admin-1',
      status: CashDepositStatus.active,
      operationId: id,
    );

OpeningBalanceModel _opening(int fils) => OpeningBalanceModel(
  openingBalanceFils: fils,
  createdAt: Timestamp.fromMillisecondsSinceEpoch(0),
  createdBy: 'admin-1',
  operationId: 'set-opening-1',
);

void main() {
  group('CashBoxSummary.compute', () {
    test(
      'computes opening + active deposits - active withdrawals across all '
      'withdrawal kinds',
      () {
        final summary = CashBoxSummary.compute(
          openingBalance: _opening(100000),
          deposits: [
            _deposit(id: 'deposit-1', amountFils: 50000),
            _deposit(id: 'deposit-2', amountFils: 25000, createdAtMillis: 1),
          ],
          withdrawals: [
            // Manual withdrawal.
            _withdrawal(id: 'manual-1', amountFils: 10000, createdAtMillis: 2),
            // Invoice shop-cash part.
            _withdrawal(
              id: 'invoice_inv-1',
              amountFils: 30000,
              invoiceId: 'inv-1',
              createdAtMillis: 3,
            ),
            // Supplier-payment shop-cash part.
            _withdrawal(
              id: 'supplierPayment_pay-1',
              amountFils: 5000,
              supplierPaymentId: 'pay-1',
              createdAtMillis: 4,
            ),
          ],
        );

        expect(summary.openingBalanceFils, 100000);
        expect(summary.totalDepositsFils, 75000);
        expect(summary.totalWithdrawalsFils, 45000);
        expect(summary.currentBalanceFils, 130000);
        expect(summary.movements.length, 5);
      },
    );

    test('excludes cancelled withdrawals and keeps cancelled out of totals', () {
      final summary = CashBoxSummary.compute(
        openingBalance: _opening(10000),
        deposits: [_deposit(id: 'deposit-1', amountFils: 2000)],
        withdrawals: [
          _withdrawal(id: 'manual-1', amountFils: 3000),
          _withdrawal(
            id: 'manual-2',
            amountFils: 9000,
            status: CashWithdrawalStatus.cancelled,
          ),
          _withdrawal(
            id: 'invoice_inv-1',
            amountFils: 4000,
            invoiceId: 'inv-1',
            status: CashWithdrawalStatus.cancelled,
          ),
        ],
      );

      expect(summary.totalWithdrawalsFils, 3000);
      expect(summary.currentBalanceFils, 9000);
      expect(
        summary.movements.map((movement) => movement.id).toList(),
        ['deposit-1', 'manual-1'],
      );
    });

    test('refuses two active withdrawals claiming the same invoice', () {
      // The deterministic `invoice_{invoiceId}` document id plus the model
      // check below are what prevent a second active document for one
      // invoice; compute keeps a second defensive guard as well.
      expect(
        () => _withdrawal(id: 'invoice_inv-1_twin', amountFils: 1, invoiceId: 'inv-1'),
        throwsArgumentError,
      );
    });

    test('refuses two active withdrawals claiming the same payment', () {
      expect(
        () => _withdrawal(
          id: 'supplierPayment_pay-1_twin',
          amountFils: 1,
          supplierPaymentId: 'pay-1',
        ),
        throwsArgumentError,
      );
    });

    test('refuses a deposit that is not ACTIVE (impossible through the app)',
        () {
      expect(
        () => CashDepositModel.fromData(depositId: 'deposit-1', data: {
          'amountFils': 1000,
          'note': 'note',
          'createdAt': Timestamp.fromMillisecondsSinceEpoch(0),
          'createdBy': 'admin-1',
          'status': 'CANCELLED',
          'operationId': 'deposit-1',
        }),
        throwsFormatException,
      );
    });

    test('sorts movements newest first', () {
      final summary = CashBoxSummary.compute(
        openingBalance: _opening(0),
        deposits: [
          _deposit(id: 'deposit-old', amountFils: 1, createdAtMillis: 1000),
          _deposit(id: 'deposit-new', amountFils: 1, createdAtMillis: 2000),
        ],
        withdrawals: [
          _withdrawal(id: 'manual-mid', amountFils: 1, createdAtMillis: 1500),
        ],
      );
      expect(
        summary.movements.map((movement) => movement.id).toList(),
        ['deposit-new', 'manual-mid', 'deposit-old'],
      );
    });

    test('a negative current balance is kept as-is (no silent clamping)', () {
      final summary = CashBoxSummary.compute(
        openingBalance: _opening(1000),
        deposits: const [],
        withdrawals: [_withdrawal(id: 'manual-1', amountFils: 5000)],
      );
      expect(summary.currentBalanceFils, -4000);
    });
  });

  group('CashBoxSnapshot.fromDocuments', () {
    test('summary is null when the opening balance is missing', () {
      final snapshot = CashBoxSnapshot.fromDocuments(
        openingBalance: null,
        deposits: [_deposit(id: 'deposit-1', amountFils: 1000)],
        withdrawals: [_withdrawal(id: 'manual-1', amountFils: 500)],
      );
      expect(snapshot.summary, isNull);
      expect(snapshot.deposits, hasLength(1));
    });

    test('summary is computed when the opening balance exists', () {
      final snapshot = CashBoxSnapshot.fromDocuments(
        openingBalance: _opening(2000),
        deposits: [_deposit(id: 'deposit-1', amountFils: 1000)],
        withdrawals: [_withdrawal(id: 'manual-1', amountFils: 500)],
      );
      expect(snapshot.summary!.currentBalanceFils, 2500);
    });
  });

  group('OpeningBalanceModel', () {
    test('rejects a negative opening balance', () {
      expect(
        () => OpeningBalanceModel(
          openingBalanceFils: -1,
          createdAt: Timestamp.fromMillisecondsSinceEpoch(0),
          createdBy: 'admin-1',
          operationId: 'set-opening-1',
        ),
        throwsArgumentError,
      );
    });

    test('accepts zero', () {
      final opening = OpeningBalanceModel(
        openingBalanceFils: 0,
        createdAt: Timestamp.fromMillisecondsSinceEpoch(0),
        createdBy: 'admin-1',
        operationId: 'set-opening-1',
      );
      expect(opening.openingBalanceFils, 0);
      expect(opening.wasAmended, isFalse);
    });

    test('requires the complete amendment set', () {
      expect(
        () => OpeningBalanceModel(
          openingBalanceFils: 100,
          createdAt: Timestamp.fromMillisecondsSinceEpoch(0),
          createdBy: 'admin-1',
          operationId: 'set-opening-1',
          amendedBy: 'admin-1',
        ),
        throwsArgumentError,
      );
    });

    test('accepts a complete amendment', () {
      final opening = OpeningBalanceModel(
        openingBalanceFils: 100,
        createdAt: Timestamp.fromMillisecondsSinceEpoch(0),
        createdBy: 'admin-1',
        operationId: 'set-opening-1',
        amendedAt: Timestamp.fromMillisecondsSinceEpoch(1),
        amendedBy: 'admin-1',
        amendedReason: 'Corrected count',
        lastOperationId: 'amend-opening-1',
      );
      expect(opening.wasAmended, isTrue);
    });
  });
}
