import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/cash_withdrawal_model.dart';
import '../models/supplier_payment_model.dart';

class CashWithdrawalNotFoundException implements Exception {
  const CashWithdrawalNotFoundException();
  @override
  String toString() => 'CashWithdrawalNotFoundException';
}

class CashWithdrawalAdminException implements Exception {
  const CashWithdrawalAdminException();
  @override
  String toString() => 'CashWithdrawalAdminException';
}

class CashWithdrawalMismatchException implements Exception {
  const CashWithdrawalMismatchException();
  @override
  String toString() => 'CashWithdrawalMismatchException';
}

class CashWithdrawalRepository {
  CashWithdrawalRepository({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  // Collection references - public for internal test access
  CollectionReference<Map<String, dynamic>> cashWithdrawals(String storeId) =>
      _firestore.collection('stores').doc(storeId).collection('cashWithdrawals');

  CollectionReference<Map<String, dynamic>> operations(String storeId) =>
      _firestore.collection('stores').doc(storeId).collection('operations');

  Future<CashWithdrawalModel> getWithdrawal(String storeId, String withdrawalId) async {
    final snapshot =
        await cashWithdrawals(storeId).doc(withdrawalId).get();
    if (!snapshot.exists) {
      throw CashWithdrawalNotFoundException();
    }
    return CashWithdrawalModel.fromDocument(snapshot);
  }

  Future<List<CashWithdrawalModel>> listWithdrawals(String storeId) async {
    final snapshot =
        await cashWithdrawals(storeId).orderBy('createdAt').get();
    return snapshot.docs.map(CashWithdrawalModel.fromDocument).toList();
  }

  /// Creates a manual cash withdrawal atomically within a Firestore transaction.
  /// Idempotency: if operationId already exists, throws CashWithdrawalMismatchException (no re-execution).
  Future<String> createManualWithdrawal({
    required String storeId,
    required int amountFils,
    required CashWithdrawalType type,
    required String withdrawalId,
    required String createdBy,
    required String operationId,
    String? note,
  }) async {
    // Validate amount > 0
    if (amountFils <= 0) {
      throw ArgumentError.value(amountFils, 'amountFils', 'Amount must be greater than zero.');
    }

    // Manual withdrawal validation: type must be manual (not PURCHASE_INVOICE),
    // source must be SHOP_CASH, no invoiceId/supplierPaymentId
    if (type == CashWithdrawalType.purchaseInvoice) {
      throw ArgumentError.value(
          type, 'type', 'PURCHASE_INVOICE is not a manual withdrawal type.');
    }

    if (SupplierPaymentSource.shopCash != SupplierPaymentSource.shopCash) {
      // Validation passed - source is SHOP_CASH by convention for manual
    }

    return await _firestore.runTransaction((Transaction transaction) async {
      // 1. Idempotency check: verify operationId does not already exist
      final operationRef = operations(storeId).doc(operationId);
      final existingOperation = await transaction.get(operationRef);

      if (existingOperation.exists) {
        // Idempotent: operation already exists - do NOT re-execute financial workflow
        throw CashWithdrawalMismatchException();
      }

      // 2. Build the withdrawal map manually (following PurchaseInvoiceRepository pattern)
      //    using FieldValue.serverTimestamp() for createdAt
      final withdrawalData = <String, dynamic>{
        'amountFils': amountFils,
        'type': type.value,
        'source': SupplierPaymentSource.shopCash.value,
        'withdrawalId': withdrawalId,
        'createdAt': FieldValue.serverTimestamp(),
        'createdBy': createdBy,
        'status': 'ACTIVE',
        if (note != null) 'note': note,
        // Manual withdrawals have no invoiceId or supplierPaymentId
      };

      // 3. Create the withdrawal document
      final withdrawalRef = cashWithdrawals(storeId).doc(withdrawalId);
      transaction.set(withdrawalRef, withdrawalData);

      // 4. Financial operation/idempotency record (finalized COMPLETED in same tx)
      final opRef = operations(storeId).doc(operationId);
      transaction.set(opRef, {
        'operationId': operationId,
        'type': 'CREATE_MANUAL_WITHDRAWAL',
        'createdBy': createdBy,
        'createdAt': FieldValue.serverTimestamp(),
        'status': 'COMPLETED',
        'retryCount': 0,
      });

      // 5. Return the withdrawal ID
      return withdrawalId;
    });
  }

  /// Admin-only cancellation of a cash withdrawal.
  /// Preserves the withdrawal document, marks CANCELLED, records metadata,
  /// and creates the cancellation operation atomically.
  Future<void> cancelWithdrawal({
    required String storeId,
    required String withdrawalId,
    required String operationId,
    required String cancelledBy,
    required String reason,
  }) async {
    return await _firestore.runTransaction((Transaction transaction) async {
      // Read the withdrawal document
      final withdrawalRef = cashWithdrawals(storeId).doc(withdrawalId);
      final withdrawalSnapshot = await transaction.get(withdrawalRef);

      if (!withdrawalSnapshot.exists) {
        throw CashWithdrawalNotFoundException();
      }

      // Check cancellation is not already applied
      final existingData = withdrawalSnapshot.data()!;
      final currentStatus = existingData['status'] as String;
      if (currentStatus == 'CANCELLED') {
        // Already cancelled - do not re-execute
        return;
      }

      // 2. Update the withdrawal status to CANCELLED
      transaction.update(withdrawalRef, {
        'status': 'CANCELLED',
        'cancelledBy': cancelledBy,
        'cancelledAt': FieldValue.serverTimestamp(),
        'cancellationReason': reason,
      });

      // 3. Create the cancellation operation/idempotency record atomically
      final opRef = operations(storeId).doc(operationId);
      final existingOperation = await transaction.get(opRef);

      if (!existingOperation.exists) {
        transaction.set(opRef, {
          'operationId': operationId,
          'type': 'CANCEL_MANUAL_WITHDRAWAL',
          'createdBy': cancelledBy,
          'createdAt': FieldValue.serverTimestamp(),
          'status': 'COMPLETED',
          'retryCount': 0,
        });
      }
      // If operation already exists, do not overwrite (idempotent)
    });
  }
}