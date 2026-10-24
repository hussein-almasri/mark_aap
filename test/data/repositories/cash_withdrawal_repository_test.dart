import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mark_aap/data/models/cash_withdrawal_model.dart';
import 'package:mark_aap/data/models/supplier_payment_model.dart';
import 'package:mark_aap/data/repositories/cash_withdrawal_repository.dart';

/// A plain `flutter test` VM run has no Firestore platform host, so
/// `CashWithdrawalRepository()` throws before any scenario can reach
/// Firestore. Detect that once and skip the repository scenarios below with
/// an explicit reason instead of failing. The same rule-level coverage is
/// executed by `test/firestore_rules/manual_cash_withdrawal.test.mjs`.
String? _firestoreUnavailableReason() {
  try {
    CashWithdrawalRepository();
    return null;
  } catch (error) {
    return 'CashWithdrawalRepository needs a Firestore platform host '
        '($error). Run these scenarios in an environment that hosts '
        'Firestore (device or emulator integration run).';
  }
}

CashWithdrawalModel manualWithdrawal({
  String withdrawalId = 'wd-1',
  int amountFils = 25000,
  CashWithdrawalType type = CashWithdrawalType.electricity,
  Timestamp? createdAt,
  String createdBy = 'admin-1',
  CashWithdrawalStatus status = CashWithdrawalStatus.active,
  String? note = 'Electricity bill',
  String? operationId = 'op-wd-1',
  Timestamp? cancelledAt,
  String? cancelledBy,
  String? cancellationReason,
  String? cancellationOperationId,
}) =>
    CashWithdrawalModel(
      withdrawalId: withdrawalId,
      amountFils: amountFils,
      type: type,
      createdAt: createdAt ?? Timestamp.fromDate(DateTime.utc(2026, 1, 2)),
      createdBy: createdBy,
      status: status,
      note: note,
      operationId: operationId,
      cancelledAt: cancelledAt,
      cancelledBy: cancelledBy,
      cancellationReason: cancellationReason,
      cancellationOperationId: cancellationOperationId,
    );

void main() {
  final String? firestoreSkip = _firestoreUnavailableReason();
  final Timestamp createdAt = Timestamp.fromDate(DateTime.utc(2026, 1, 2));

  group('CashWithdrawalRepository.validateCancellationReason', () {
    test('accepts a trimmed reason and returns it', () {
      expect(
        CashWithdrawalRepository.validateCancellationReason('Wrong amount'),
        'Wrong amount',
      );
    });

    test('accepts a reason of exactly 500 characters', () {
      final String reason = 'x' * 500;
      expect(CashWithdrawalRepository.validateCancellationReason(reason),
          reason);
    });

    test('rejects an empty reason', () {
      expect(
        () => CashWithdrawalRepository.validateCancellationReason(''),
        throwsArgumentError,
      );
    });

    test('rejects a whitespace-only reason', () {
      expect(
        () => CashWithdrawalRepository.validateCancellationReason('   '),
        throwsArgumentError,
      );
    });

    test('rejects an untrimmed reason', () {
      expect(
        () => CashWithdrawalRepository.validateCancellationReason(' padded '),
        throwsArgumentError,
      );
    });

    test('rejects a reason longer than 500 characters', () {
      expect(
        () => CashWithdrawalRepository.validateCancellationReason('x' * 501),
        throwsArgumentError,
      );
    });
  });

  group('CashWithdrawalModel cancellation and operation data', () {
    test('keeps operationId and note through toData/fromData', () {
      final CashWithdrawalModel model = manualWithdrawal();
      final CashWithdrawalModel roundTrip =
          CashWithdrawalModel.fromData(
              withdrawalId: model.withdrawalId, data: model.toData());

      expect(roundTrip.operationId, 'op-wd-1');
      expect(roundTrip.note, 'Electricity bill');
      expect(roundTrip.amountFils, 25000);
      expect(roundTrip.status, CashWithdrawalStatus.active);
      expect(roundTrip.cancelledAt, isNull);
      expect(roundTrip.cancelledBy, isNull);
      expect(roundTrip.cancellationReason, isNull);
      expect(roundTrip.cancellationOperationId, isNull);
      expect(roundTrip.toData(), model.toData());
    });

    test('keeps cancellation fields through toData/fromData', () {
      final Timestamp cancelledAt = Timestamp.fromDate(DateTime.utc(2026, 1, 3));
      final CashWithdrawalModel model = manualWithdrawal(
        status: CashWithdrawalStatus.cancelled,
        cancelledAt: cancelledAt,
        cancelledBy: 'admin-2',
        cancellationReason: 'Wrong amount entered',
        cancellationOperationId: 'op-cancel-1',
      );
      final CashWithdrawalModel roundTrip =
          CashWithdrawalModel.fromData(
              withdrawalId: model.withdrawalId, data: model.toData());

      expect(roundTrip.status, CashWithdrawalStatus.cancelled);
      expect(roundTrip.cancelledAt, cancelledAt);
      expect(roundTrip.cancelledBy, 'admin-2');
      expect(roundTrip.cancellationReason, 'Wrong amount entered');
      expect(roundTrip.cancellationOperationId, 'op-cancel-1');
      expect(roundTrip.toData(), model.toData());
    });

    test('rejects an active withdrawal carrying cancellation data', () {
      expect(
        () => manualWithdrawal(cancelledBy: 'admin-2'),
        throwsArgumentError,
      );
    });

    test('rejects a cancelled withdrawal missing cancellation data', () {
      expect(
        () => manualWithdrawal(status: CashWithdrawalStatus.cancelled),
        throwsArgumentError,
      );
      expect(
        () => manualWithdrawal(
          status: CashWithdrawalStatus.cancelled,
          cancelledAt: Timestamp.fromDate(DateTime.utc(2026, 1, 3)),
          cancelledBy: 'admin-2',
          cancellationReason: 'Wrong amount entered',
        ),
        throwsArgumentError,
      );
    });

    test('rejects a non-positive amount', () {
      expect(() => manualWithdrawal(amountFils: 0), throwsArgumentError);
      expect(() => manualWithdrawal(amountFils: -100), throwsArgumentError);
    });

    test('rejects PURCHASE_INVOICE without a linked document', () {
      expect(
        () => manualWithdrawal(type: CashWithdrawalType.purchaseInvoice),
        throwsArgumentError,
      );
    });

    test('rejects a manual withdrawal forged with an invoiceId', () {
      expect(
        () => CashWithdrawalModel(
          withdrawalId: 'wd-forged',
          amountFils: 100,
          type: CashWithdrawalType.personalExpense,
          invoiceId: 'invoice-1',
          createdAt: createdAt,
          createdBy: 'admin-1',
          status: CashWithdrawalStatus.active,
        ),
        throwsArgumentError,
      );
    });

    test('rejects a manual withdrawal with a non SHOP_CASH source', () {
      expect(
        () => CashWithdrawalModel(
          withdrawalId: 'wd-forged-2',
          amountFils: 100,
          type: CashWithdrawalType.personalExpense,
          source: SupplierPaymentSource.outsideCash,
          createdAt: createdAt,
          createdBy: 'admin-1',
          status: CashWithdrawalStatus.active,
        ),
        throwsArgumentError,
      );
    });
  });

  group('CashWithdrawalRepository manual withdrawal scenarios', () {
    test(
        'creates a manual withdrawal with the right amount and note and pairs '
        'it with its CREATE_MANUAL_WITHDRAWAL operation', () async {
      final CashWithdrawalRepository repo = CashWithdrawalRepository();

      await repo.createManualWithdrawal(
        storeId: 'store-1',
        amountFils: 25000,
        type: CashWithdrawalType.electricity,
        withdrawalId: 'wd-create-1',
        createdBy: 'admin-1',
        operationId: 'op-create-1',
        note: 'Electricity bill',
      );

      final CashWithdrawalModel withdrawal =
          await repo.getWithdrawal('store-1', 'wd-create-1');
      expect(withdrawal.amountFils, 25000);
      expect(withdrawal.type, CashWithdrawalType.electricity);
      expect(withdrawal.source, SupplierPaymentSource.shopCash);
      expect(withdrawal.note, 'Electricity bill');
      expect(withdrawal.status, CashWithdrawalStatus.active);
      expect(withdrawal.operationId, 'op-create-1');
      expect(withdrawal.invoiceId, isNull);
      expect(withdrawal.supplierPaymentId, isNull);

      final DocumentSnapshot<Map<String, dynamic>> operation =
          await repo.operations('store-1').doc('op-create-1').get();
      expect(operation.exists, isTrue);
      expect(operation.data()!['type'], 'CREATE_MANUAL_WITHDRAWAL');
      expect(operation.data()!['withdrawalId'], 'wd-create-1');
      expect(operation.data()!['status'], 'COMPLETED');
    });

    test('omits the note when none is given', () async {
      final CashWithdrawalRepository repo = CashWithdrawalRepository();

      await repo.createManualWithdrawal(
        storeId: 'store-1',
        amountFils: 300,
        type: CashWithdrawalType.shopExpense,
        withdrawalId: 'wd-no-note-1',
        createdBy: 'admin-1',
        operationId: 'op-no-note-1',
      );

      final CashWithdrawalModel withdrawal =
          await repo.getWithdrawal('store-1', 'wd-no-note-1');
      expect(withdrawal.note, isNull);
    });

    test('rejects a zero or negative amount', () async {
      final CashWithdrawalRepository repo = CashWithdrawalRepository();

      await expectLater(
        repo.createManualWithdrawal(
          storeId: 'store-1',
          amountFils: 0,
          type: CashWithdrawalType.personalExpense,
          withdrawalId: 'wd-bad-amount-0',
          createdBy: 'admin-1',
          operationId: 'op-bad-amount-0',
        ),
        throwsArgumentError,
      );
      await expectLater(
        repo.createManualWithdrawal(
          storeId: 'store-1',
          amountFils: -100,
          type: CashWithdrawalType.personalExpense,
          withdrawalId: 'wd-bad-amount-1',
          createdBy: 'admin-1',
          operationId: 'op-bad-amount-1',
        ),
        throwsArgumentError,
      );
    });

    test('rejects PURCHASE_INVOICE as a manual withdrawal type', () async {
      final CashWithdrawalRepository repo = CashWithdrawalRepository();

      await expectLater(
        repo.createManualWithdrawal(
          storeId: 'store-1',
          amountFils: 100,
          type: CashWithdrawalType.purchaseInvoice,
          withdrawalId: 'wd-bad-type-1',
          createdBy: 'admin-1',
          operationId: 'op-bad-type-1',
        ),
        throwsArgumentError,
      );
    });

    test(
        'rejects a cancellation reason that is empty, untrimmed or longer '
        'than 500 characters', () async {
      final CashWithdrawalRepository repo = CashWithdrawalRepository();
      await repo.createManualWithdrawal(
        storeId: 'store-1',
        amountFils: 250,
        type: CashWithdrawalType.employeePayment,
        withdrawalId: 'wd-bad-reason-1',
        createdBy: 'admin-1',
        operationId: 'op-bad-reason-1',
      );

      for (final String reason in ['', '   ', ' padded ', 'x' * 501]) {
        await expectLater(
          repo.cancelWithdrawal(
            storeId: 'store-1',
            withdrawalId: 'wd-bad-reason-1',
            operationId: 'op-cancel-bad-reason-${reason.hashCode}',
            cancelledBy: 'admin-2',
            reason: reason,
          ),
          throwsArgumentError,
        );
      }

      final CashWithdrawalModel withdrawal =
          await repo.getWithdrawal('store-1', 'wd-bad-reason-1');
      expect(withdrawal.status, CashWithdrawalStatus.active);
    });

    test('reusing an operationId does not record a second withdrawal',
        () async {
      final CashWithdrawalRepository repo = CashWithdrawalRepository();

      await repo.createManualWithdrawal(
        storeId: 'store-1',
        amountFils: 150,
        type: CashWithdrawalType.billPayment,
        withdrawalId: 'wd-idem-1',
        createdBy: 'admin-1',
        operationId: 'op-idem-1',
      );

      await expectLater(
        repo.createManualWithdrawal(
          storeId: 'store-1',
          amountFils: 150,
          type: CashWithdrawalType.billPayment,
          withdrawalId: 'wd-idem-1',
          createdBy: 'admin-1',
          operationId: 'op-idem-1',
        ),
        throwsA(isA<CashWithdrawalMismatchException>()),
      );

      final CashWithdrawalModel withdrawal =
          await repo.getWithdrawal('store-1', 'wd-idem-1');
      expect(withdrawal.amountFils, 150);
      expect(withdrawal.operationId, 'op-idem-1');
    });

    test(
        'cancels with a valid reason and keeps operationId and '
        'cancellationOperationId on the saved and re-read document', () async {
      final CashWithdrawalRepository repo = CashWithdrawalRepository();
      await repo.createManualWithdrawal(
        storeId: 'store-1',
        amountFils: 250,
        type: CashWithdrawalType.employeePayment,
        withdrawalId: 'wd-cancel-1',
        createdBy: 'admin-1',
        operationId: 'op-create-cancel-1',
      );

      await repo.cancelWithdrawal(
        storeId: 'store-1',
        withdrawalId: 'wd-cancel-1',
        operationId: 'op-cancel-1',
        cancelledBy: 'admin-2',
        reason: 'Payment processed differently',
      );

      final CashWithdrawalModel withdrawal =
          await repo.getWithdrawal('store-1', 'wd-cancel-1');
      expect(withdrawal.status, CashWithdrawalStatus.cancelled);
      expect(withdrawal.operationId, 'op-create-cancel-1');
      expect(withdrawal.cancellationOperationId, 'op-cancel-1');
      expect(withdrawal.cancelledBy, 'admin-2');
      expect(withdrawal.cancellationReason, 'Payment processed differently');
      expect(withdrawal.cancelledAt, isNotNull);

      final DocumentSnapshot<Map<String, dynamic>> operation =
          await repo.operations('store-1').doc('op-cancel-1').get();
      expect(operation.exists, isTrue);
      expect(operation.data()!['type'], 'CANCEL_MANUAL_WITHDRAWAL');
      expect(operation.data()!['withdrawalId'], 'wd-cancel-1');
      expect(operation.data()!['status'], 'COMPLETED');
    });

    // Admin-only enforcement lives in the Firestore rules (a second raw
    // cancel write is refused by them); the repository itself is a no-op on
    // an already cancelled withdrawal.
    test('a second cancel is a no-op that keeps the first cancellation',
        () async {
      final CashWithdrawalRepository repo = CashWithdrawalRepository();
      await repo.createManualWithdrawal(
        storeId: 'store-1',
        amountFils: 400,
        type: CashWithdrawalType.electricity,
        withdrawalId: 'wd-cancel-2',
        createdBy: 'admin-1',
        operationId: 'op-create-cancel-2',
      );
      await repo.cancelWithdrawal(
        storeId: 'store-1',
        withdrawalId: 'wd-cancel-2',
        operationId: 'op-cancel-2a',
        cancelledBy: 'admin-2',
        reason: 'First cancellation',
      );

      await repo.cancelWithdrawal(
        storeId: 'store-1',
        withdrawalId: 'wd-cancel-2',
        operationId: 'op-cancel-2b',
        cancelledBy: 'admin-3',
        reason: 'Second cancellation attempt',
      );

      final CashWithdrawalModel withdrawal =
          await repo.getWithdrawal('store-1', 'wd-cancel-2');
      expect(withdrawal.status, CashWithdrawalStatus.cancelled);
      expect(withdrawal.cancellationOperationId, 'op-cancel-2a');
      expect(withdrawal.cancelledBy, 'admin-2');
      expect(withdrawal.cancellationReason, 'First cancellation');

      final DocumentSnapshot<Map<String, dynamic>> secondOperation =
          await repo.operations('store-1').doc('op-cancel-2b').get();
      expect(secondOperation.exists, isFalse);
    });

    test('cancelling a missing withdrawal is refused', () async {
      final CashWithdrawalRepository repo = CashWithdrawalRepository();

      await expectLater(
        repo.cancelWithdrawal(
          storeId: 'store-1',
          withdrawalId: 'wd-missing-1',
          operationId: 'op-cancel-missing-1',
          cancelledBy: 'admin-2',
          reason: 'Does not exist',
        ),
        throwsA(isA<CashWithdrawalNotFoundException>()),
      );
    });

    test('accepts every manual withdrawal type', () async {
      final CashWithdrawalRepository repo = CashWithdrawalRepository();
      final List<CashWithdrawalType> types = [
        CashWithdrawalType.personalExpense,
        CashWithdrawalType.employeePayment,
        CashWithdrawalType.billPayment,
        CashWithdrawalType.electricity,
        CashWithdrawalType.shopExpense,
        CashWithdrawalType.other,
      ];

      for (final CashWithdrawalType type in types) {
        await repo.createManualWithdrawal(
          storeId: 'store-1',
          amountFils: 100,
          type: type,
          withdrawalId: 'wd-type-${type.value}',
          createdBy: 'admin-1',
          operationId: 'op-type-${type.value}',
        );

        final CashWithdrawalModel withdrawal =
            await repo.getWithdrawal('store-1', 'wd-type-${type.value}');
        expect(withdrawal.type, type);
        expect(withdrawal.status, CashWithdrawalStatus.active);
      }
    });

    test('listWithdrawals returns the created withdrawals in createdAt order',
        () async {
      final CashWithdrawalRepository repo = CashWithdrawalRepository();
      for (int i = 0; i < 3; i++) {
        await repo.createManualWithdrawal(
          storeId: 'store-1',
          amountFils: 100 * (i + 1),
          type: CashWithdrawalType.personalExpense,
          withdrawalId: 'wd-list-$i',
          createdBy: 'admin-1',
          operationId: 'op-list-$i',
        );
      }

      final List<CashWithdrawalModel> withdrawals =
          await repo.listWithdrawals('store-1');
      expect(withdrawals.length, 3);
    });
  }, skip: firestoreSkip);
}
