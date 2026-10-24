import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/cash_box_models.dart';
import '../models/cash_deposit_model.dart';
import '../models/cash_withdrawal_model.dart';
import 'cash_withdrawal_repository.dart';

class CashBoxMismatchException implements Exception {
  const CashBoxMismatchException();
  @override
  String toString() => 'CashBoxMismatchException';
}

class CashBoxOpeningBalanceAlreadySetException implements Exception {
  const CashBoxOpeningBalanceAlreadySetException();
  @override
  String toString() => 'CashBoxOpeningBalanceAlreadySetException';
}

class CashBoxOpeningBalanceNotSetException implements Exception {
  const CashBoxOpeningBalanceNotSetException();
  @override
  String toString() => 'CashBoxOpeningBalanceNotSetException';
}

/// Reads and writes the shop cash box: the singleton opening balance, the
/// cash deposits, and the computed balance
/// (`opening + ACTIVE deposits - ACTIVE withdrawals`).
///
/// All writes follow the one-transaction pattern of
/// `CashWithdrawalRepository.createManualWithdrawal`: the business document
/// and its `COMPLETED` operation are written together so the Firestore rules
/// can cross-check both sides through `getAfter`, and a retried operationId
/// is refused before any document moves.
class CashBoxRepository {
  CashBoxRepository({
    FirebaseFirestore? firestore,
    CashWithdrawalRepository? withdrawalRepository,
  }) : _firestore = firestore ?? FirebaseFirestore.instance,
       _withdrawalRepository =
           withdrawalRepository ?? CashWithdrawalRepository(firestore: firestore);

  final FirebaseFirestore _firestore;
  final CashWithdrawalRepository _withdrawalRepository;

  CollectionReference<Map<String, dynamic>> cashBox(String storeId) =>
      _firestore.collection('stores').doc(storeId).collection('cashBox');

  CollectionReference<Map<String, dynamic>> cashDeposits(String storeId) =>
      _firestore
          .collection('stores')
          .doc(storeId)
          .collection('cashDeposits');

  CollectionReference<Map<String, dynamic>> operations(String storeId) =>
      _firestore.collection('stores').doc(storeId).collection('operations');

  /// Same contract as the Firestore rules (`validCashReason`): trimmed,
  /// non-empty and at most 500 characters.
  static String validateCashReason(String value) {
    final trimmed = value.trim();
    if (value != trimmed || trimmed.isEmpty || trimmed.length > 500) {
      throw ArgumentError.value(
        value,
        'reason',
        'Must be trimmed, non-empty and at most 500 characters.',
      );
    }
    return trimmed;
  }

  /// Deposits must be a positive integer number of فلس; the opening balance
  /// may also be exactly zero (an empty box).
  static int validateAmountFils(int amountFils, {required bool allowZero}) {
    final minimum = allowZero ? 0 : 1;
    if (amountFils < minimum) {
      throw ArgumentError.value(
        amountFils,
        'amountFils',
        allowZero
            ? 'Must be zero or positive.'
            : 'Must be greater than zero.',
      );
    }
    return amountFils;
  }

  Future<OpeningBalanceModel?> getOpeningBalance(String storeId) async {
    final snapshot = await cashBox(storeId).doc('openingBalance').get();
    if (!snapshot.exists) return null;
    return OpeningBalanceModel.fromDocument(snapshot);
  }

  Future<List<CashDepositModel>> listDeposits(String storeId) async {
    final snapshot =
        await cashDeposits(storeId).orderBy('createdAt').get();
    return snapshot.docs.map(CashDepositModel.fromDocument).toList();
  }

  /// Sets the opening balance exactly once (admin-only in the rules).
  /// Idempotency: a reused operationId throws [CashBoxMismatchException];
  /// a second set throws [CashBoxOpeningBalanceAlreadySetException].
  Future<void> setOpeningBalance({
    required String storeId,
    required int openingBalanceFils,
    required String operationId,
    required String createdBy,
  }) async {
    validateAmountFils(openingBalanceFils, allowZero: true);

    await _firestore.runTransaction((Transaction transaction) async {
      final operationRef = operations(storeId).doc(operationId);
      final existingOperation = await transaction.get(operationRef);
      if (existingOperation.exists) {
        throw const CashBoxMismatchException();
      }

      final balanceRef = cashBox(storeId).doc('openingBalance');
      final existingBalance = await transaction.get(balanceRef);
      if (existingBalance.exists) {
        throw const CashBoxOpeningBalanceAlreadySetException();
      }

      transaction.set(balanceRef, {
        'openingBalanceFils': openingBalanceFils,
        'createdAt': FieldValue.serverTimestamp(),
        'createdBy': createdBy,
        'operationId': operationId,
      });
      transaction.set(operationRef, {
        'operationId': operationId,
        'type': 'SET_OPENING_BALANCE',
        'cashBoxId': 'openingBalance',
        'createdBy': createdBy,
        'createdAt': FieldValue.serverTimestamp(),
        'status': 'COMPLETED',
        'retryCount': 0,
      });
    });
  }

  /// Amends the opening balance through the explicit audited path: an admin
  /// only, a mandatory reason, and a paired AMEND_OPENING_BALANCE operation
  /// written in the same transaction.
  Future<void> amendOpeningBalance({
    required String storeId,
    required int openingBalanceFils,
    required String operationId,
    required String amendedBy,
    required String reason,
  }) async {
    validateAmountFils(openingBalanceFils, allowZero: true);
    validateCashReason(reason);

    await _firestore.runTransaction((Transaction transaction) async {
      final operationRef = operations(storeId).doc(operationId);
      final existingOperation = await transaction.get(operationRef);
      if (existingOperation.exists) {
        throw const CashBoxMismatchException();
      }

      final balanceRef = cashBox(storeId).doc('openingBalance');
      final existingBalance = await transaction.get(balanceRef);
      if (!existingBalance.exists) {
        throw const CashBoxOpeningBalanceNotSetException();
      }

      transaction.update(balanceRef, {
        'openingBalanceFils': openingBalanceFils,
        'amendedAt': FieldValue.serverTimestamp(),
        'amendedBy': amendedBy,
        'amendedReason': reason,
        'lastOperationId': operationId,
      });
      transaction.set(operationRef, {
        'operationId': operationId,
        'type': 'AMEND_OPENING_BALANCE',
        'cashBoxId': 'openingBalance',
        'createdBy': amendedBy,
        'createdAt': FieldValue.serverTimestamp(),
        'status': 'COMPLETED',
        'retryCount': 0,
      });
    });
  }

  /// Records a cash deposit (admin-only in the rules). The deposit document
  /// id equals [operationId] so a retried operation targets the same
  /// document and the idempotency gate refuses the re-execution.
  Future<String> createDeposit({
    required String storeId,
    required int amountFils,
    required String note,
    required String operationId,
    required String createdBy,
  }) async {
    validateAmountFils(amountFils, allowZero: false);
    validateCashReason(note);

    await _firestore.runTransaction((Transaction transaction) async {
      final operationRef = operations(storeId).doc(operationId);
      final existingOperation = await transaction.get(operationRef);
      if (existingOperation.exists) {
        throw const CashBoxMismatchException();
      }

      final depositRef = cashDeposits(storeId).doc(operationId);
      transaction.set(depositRef, {
        'amountFils': amountFils,
        'note': note,
        'createdAt': FieldValue.serverTimestamp(),
        'createdBy': createdBy,
        'status': 'ACTIVE',
        'operationId': operationId,
      });
      transaction.set(operationRef, {
        'operationId': operationId,
        'type': 'CREATE_CASH_DEPOSIT',
        'depositId': operationId,
        'createdBy': createdBy,
        'createdAt': FieldValue.serverTimestamp(),
        'status': 'COMPLETED',
        'retryCount': 0,
      });
    });
    return operationId;
  }

  /// Loads the full cash-box state in one shot. Any malformed document or
  /// inconsistent movement makes [CashBoxSummary.compute] throw
  /// [CashBoxDataException] - a partial balance is never returned.
  Future<CashBoxSnapshot> loadCashBox(String storeId) async {
    final results = await Future.wait([
      getOpeningBalance(storeId),
      listDeposits(storeId),
      _withdrawalRepository.listWithdrawals(storeId),
    ]);
    return CashBoxSnapshot.fromDocuments(
      openingBalance: results[0] as OpeningBalanceModel?,
      deposits: results[1] as List<CashDepositModel>,
      withdrawals: results[2] as List<CashWithdrawalModel>,
    );
  }
}
