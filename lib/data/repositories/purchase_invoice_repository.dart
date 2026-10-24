import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/purchase_invoice_model.dart';

class InvoiceAlreadyExistsException implements Exception {
  const InvoiceAlreadyExistsException();
  @override
  String toString() => 'InvoiceAlreadyExistsException';
}

class InvoiceAlreadyCancelledException implements Exception {
  const InvoiceAlreadyCancelledException();
  @override
  String toString() => 'InvoiceAlreadyCancelledException';
}

class InvoiceNotFoundException implements Exception {
  const InvoiceNotFoundException();
  @override
  String toString() => 'InvoiceNotFoundException';
}

class InvoiceNotActiveException implements Exception {
  const InvoiceNotActiveException();
  @override
  String toString() => 'InvoiceNotActiveException';
}

class PurchaseInvoiceRepository {
  PurchaseInvoiceRepository({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  // Collection references - public for internal test access
  CollectionReference<Map<String, dynamic>> purchaseInvoices(String storeId) =>
      _firestore.collection('stores').doc(storeId).collection('purchaseInvoices');

  CollectionReference<Map<String, dynamic>> supplierDebts(String storeId) =>
      _firestore.collection('stores').doc(storeId).collection('supplierDebts');

  CollectionReference<Map<String, dynamic>> cashWithdrawals(String storeId) =>
      _firestore.collection('stores').doc(storeId).collection('cashWithdrawals');

  CollectionReference<Map<String, dynamic>> operations(String storeId) =>
      _firestore.collection('stores').doc(storeId).collection('operations');

  /// Mints a fresh operation id locally (no network round-trip).
  ///
  /// Callers mint one id per *logical* create so retrying the same submission
  /// reuses the same id (idempotent) while a new submission gets a new id.
  /// Mirrors `CustomerTransactionRepository.newTransactionId`.
  String newOperationId(String storeId) => operations(storeId).doc().id;

  Future<PurchaseInvoiceModel> getInvoice(String storeId, String invoiceId) async {
    final snapshot = await purchaseInvoices(storeId).doc(invoiceId).get();
    return PurchaseInvoiceModel.fromDocument(snapshot);
  }

  Future<List<PurchaseInvoiceModel>> listInvoices(String storeId) async {
    final snapshot = await purchaseInvoices(storeId).orderBy('createdAt').get();
    return snapshot.docs.map(PurchaseInvoiceModel.fromDocument).toList();
  }

  /// Creates a purchase invoice using the two-phase pattern the Firestore rules
  /// require:
  ///
  ///  1. Write the [operations] record with status `PROCESSING`
  ///     (`validOperationCreate` demands PROCESSING on create).
  ///  2. In one atomic transaction, write the invoice + optional supplier debt
  ///     + optional automatic cash withdrawal and flip the operation to
  ///     `COMPLETED` (`validOperationCompletion` only allows PROCESSING→COMPLETED
  ///     and cross-checks the invoice via `getAfter`).
  ///
  /// A single `runTransaction` that created the operation as COMPLETED directly
  /// is rejected by the rules, hence the split.
  ///
  /// Idempotency / retry safety: every document ID is derived from [operationId]
  /// (invoice = operationId, debt = operationId, withdrawal = `invoice_` +
  /// operationId, operation = operationId). Re-running with the same
  /// [operationId] therefore overwrites the same documents instead of creating
  /// duplicates. If the operation is already `COMPLETED` we throw
  /// [InvoiceAlreadyExistsException] (no re-execution); if it is still
  /// `PROCESSING` (a previous attempt died between phase 1 and phase 2) we
  /// resume phase 2 only.
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
  }) async {
    // Validate component sum matches total at model level
    if (shopCashAmountFils + outsideCashAmountFils + supplierDebtAmountFils !=
        totalAmountFils) {
      throw ArgumentError('Invoice payment components must equal its total.');
    }
    if (totalAmountFils <= 0) {
      throw ArgumentError('Total invoice amount must be greater than zero.');
    }

    final operationRef = operations(storeId).doc(operationId);
    final invoiceRef = purchaseInvoices(storeId).doc(operationId);

    // ----- Idempotency gate (outside any transaction) -----
    final existingOperation = await operationRef.get();
    if (existingOperation.exists) {
      final status = existingOperation.data()?['status'];
      if (status == 'COMPLETED') {
        // Fully created already - do NOT re-execute the financial workflow.
        throw const InvoiceAlreadyExistsException();
      }
      // status == 'PROCESSING' (or a prior FAILED): a previous attempt did not
      // finish phase 2. Resume by running phase 2 below - it is deterministic
      // for this operationId so it cannot create duplicates.
    } else {
      // ----- Phase 1: create the operation record as PROCESSING -----
      await operationRef.set({
        'operationId': operationId,
        'type': 'CREATE_PURCHASE_INVOICE',
        'createdBy': createdBy,
        'createdAt': FieldValue.serverTimestamp(),
        'status': 'PROCESSING',
        'retryCount': 0,
        'invoiceId': operationId,
        if (photoIds.isNotEmpty) 'photoIds': photoIds,
      });
    }

    // ----- Phase 2: atomic invoice + debt? + withdrawal? + operation→COMPLETED -----
    await _firestore.runTransaction((Transaction transaction) async {
      // Guard against a concurrent completion racing this retry.
      final opSnapshot = await transaction.get(operationRef);
      if (!opSnapshot.exists) {
        // Phase 1 write not observed - treat as already handled upstream.
        throw const InvoiceAlreadyExistsException();
      }
      final opStatus = opSnapshot.data()?['status'];
      if (opStatus == 'COMPLETED') {
        throw const InvoiceAlreadyExistsException();
      }

      // 1. Purchase invoice document
      transaction.set(invoiceRef, {
        'companyId': companyId,
        'companyName': companyName,
        if (supplierInvoiceNumber != null)
          'supplierInvoiceNumber': supplierInvoiceNumber,
        'totalAmountFils': totalAmountFils,
        'shopCashAmountFils': shopCashAmountFils,
        'outsideCashAmountFils': outsideCashAmountFils,
        'supplierDebtAmountFils': supplierDebtAmountFils,
        // Only write notes when present: the rules reject a null `notes` key.
        if (notes != null) 'notes': notes,
        'status': 'ACTIVE',
        'createdAt': FieldValue.serverTimestamp(),
        'createdBy': createdBy,
        'operationId': operationId,
        'photoIds': photoIds,
      });

      // 2. Supplier debt document - ONLY when a debt exists. The rules require
      //    !existsAfter(debtRef) when supplierDebtAmountFils == 0, so we must
      //    not write a zero-amount debt.
      if (supplierDebtAmountFils > 0) {
        final debtRef = supplierDebts(storeId).doc(operationId);
        transaction.set(debtRef, {
          'invoiceId': operationId,
          'companyId': companyId,
          'companyName': companyName,
          'originalAmountFils': supplierDebtAmountFils,
          'remainingAmountFils': supplierDebtAmountFils,
          'status': 'OPEN',
          'createdAt': FieldValue.serverTimestamp(),
          'createdBy': createdBy,
          'operationId': operationId,
          'lastOperationId': operationId,
        });
      }

      // 3. Automatic cash withdrawal - ONLY when shopCash > 0. Keys must be
      //    EXACTLY [amountFils, type, invoiceId, createdAt, createdBy, status]
      //    per validInvoiceWithdrawalCreate. Deliberately no `source` field.
      if (shopCashAmountFils > 0) {
        final withdrawalRef = cashWithdrawals(storeId).doc('invoice_$operationId');
        transaction.set(withdrawalRef, {
          'amountFils': shopCashAmountFils,
          'type': 'PURCHASE_INVOICE',
          'invoiceId': operationId,
          'createdAt': FieldValue.serverTimestamp(),
          'createdBy': createdBy,
          'status': 'ACTIVE',
        });
      }

      // 4. Flip the operation to COMPLETED. Rules only allow the `status` field
      //    to change, and only from PROCESSING.
      transaction.update(operationRef, {'status': 'COMPLETED'});
    });

    // ----- Return the invoice ID -----
    return operationId;
  }

  /// Validates a cancellation reason the same way the Firestore rules do
  /// (see validInvoiceCancellation): trimmed, non-empty and at most 500
  /// characters. Public so the contract can be pinned by tests.
  static String validateCancellationReason(String reason) {
    final trimmed = reason.trim();
    if (reason != trimmed || trimmed.isEmpty || trimmed.length > 500) {
      throw ArgumentError.value(
        reason,
        'reason',
        'Reason must be trimmed, non-empty and at most 500 characters.',
      );
    }
    return trimmed;
  }

  /// Cancels a purchase invoice, reversing everything it created, in the
  /// same two-phase shape as [createInvoice]:
  ///
  ///  1. Write the [operations] record with status `PROCESSING`
  ///     (`validOperationCreate` demands PROCESSING for
  ///     `CANCEL_PURCHASE_INVOICE`).
  ///  2. In one atomic transaction: flip the invoice to `CANCELLED`, cancel
  ///     its supplier debt (when one exists), cancel its automatic shop-cash
  ///     withdrawal (when one exists), and flip the operation to `COMPLETED`.
  ///
  /// The withdrawal is only touched when the invoice paid part of its value
  /// from the shop cash (`shopCashAmountFils > 0`); an invoice without one
  /// cancels cleanly. The rules cross-check that the withdrawal belongs to
  /// this invoice and that its amount matches the shop-cash amount, so a
  /// foreign or inconsistent withdrawal makes the whole transaction fail -
  /// there is no half-cancelled state.
  Future<void> cancelInvoice({
    required String storeId,
    required String invoiceId,
    required String operationId,
    required String cancelledBy,
    required String reason,
  }) async {
    validateCancellationReason(reason);

    final operationRef = operations(storeId).doc(operationId);
    final invoiceRef = purchaseInvoices(storeId).doc(invoiceId);

    // ----- Idempotency gate (outside any transaction) -----
    final existingOperation = await operationRef.get();
    if (existingOperation.exists) {
      if (existingOperation.data()?['status'] == 'COMPLETED') {
        throw const InvoiceAlreadyCancelledException();
      }
      // status == 'PROCESSING': a previous attempt did not finish phase 2.
      // Resume phase 2 only - it is deterministic for this operationId.
    } else {
      // ----- Phase 1: create the cancellation operation as PROCESSING -----
      await operationRef.set({
        'operationId': operationId,
        'type': 'CANCEL_PURCHASE_INVOICE',
        'createdBy': cancelledBy,
        'createdAt': FieldValue.serverTimestamp(),
        'status': 'PROCESSING',
        'retryCount': 0,
        'invoiceId': invoiceId,
      });
    }

    // ----- Phase 2: atomic invoice + debt? + withdrawal? + operation -----
    await _firestore.runTransaction((Transaction transaction) async {
      // Guard against a concurrent completion racing this retry.
      final invoiceSnapshot = await transaction.get(invoiceRef);
      if (!invoiceSnapshot.exists) {
        throw const InvoiceNotFoundException();
      }
      final invoiceData = invoiceSnapshot.data()!;
      final currentStatus = invoiceData['status'] as String?;
      if (currentStatus == 'CANCELLED') {
        throw const InvoiceAlreadyCancelledException();
      }
      if (currentStatus != 'ACTIVE') {
        throw const InvoiceNotActiveException();
      }

      final opSnapshot = await transaction.get(operationRef);
      if (opSnapshot.exists && opSnapshot.data()?['status'] == 'COMPLETED') {
        throw const InvoiceAlreadyCancelledException();
      }

      // 1. Purchase invoice: flip to CANCELLED with its audit trail. The
      //    rules allow exactly these five fields to change.
      transaction.update(invoiceRef, {
        'status': 'CANCELLED',
        'cancelledAt': FieldValue.serverTimestamp(),
        'cancelledBy': cancelledBy,
        'cancellationReason': reason,
        'cancellationOperationId': operationId,
      });

      // 2. Supplier debt - only when one exists. Zero-amount invoices never
      //    wrote a debt document, so there is nothing to cancel.
      final supplierDebtAmountFils =
          invoiceData['supplierDebtAmountFils'] as int? ?? 0;
      if (supplierDebtAmountFils > 0) {
        transaction.update(supplierDebts(storeId).doc(invoiceId), {
          'status': 'CANCELLED',
          'lastOperationId': operationId,
        });
      }

      // 3. Automatic cash withdrawal - only when the invoice paid from the
      //    shop cash. Only its status flips; the rules verify it belongs to
      //    this invoice (`invoice_invoiceId`) and matches the amount.
      final shopCashAmountFils =
          invoiceData['shopCashAmountFils'] as int? ?? 0;
      if (shopCashAmountFils > 0) {
        transaction.update(
          cashWithdrawals(storeId).doc('invoice_$invoiceId'),
          {'status': 'CANCELLED'},
        );
      }

      // 4. Flip the cancellation operation to COMPLETED.
      transaction.update(operationRef, {'status': 'COMPLETED'});
    });
  }
}
