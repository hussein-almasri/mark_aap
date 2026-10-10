import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/purchase_invoice_model.dart';

class InvoiceAlreadyExistsException implements Exception {
  const InvoiceAlreadyExistsException();
  @override
  String toString() => 'InvoiceAlreadyExistsException';
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
}
