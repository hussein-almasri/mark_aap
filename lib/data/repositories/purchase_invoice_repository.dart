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

  /// Creates a purchase invoice atomically within a Firestore transaction.
  /// Coordinates: invoice + supplier debt + automatic cash withdrawal (if shopCash > 0) + financial operation record.
  /// Idempotency: if operationId already exists, throws InvoiceAlreadyExistsException (no re-execution).
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
      throw ArgumentError(
          'Invoice payment components must equal its total.');
    }
    if (totalAmountFils <= 0) {
      throw ArgumentError('Total invoice amount must be greater than zero.');
    }

    return await _firestore.runTransaction((Transaction transaction) async {
      // 1. Idempotency check: verify operationId does not already exist
      final operationRef = operations(storeId).doc(operationId);
      final existingOperation = await transaction.get(operationRef);

      if (existingOperation.exists) {
        // Idempotent: operation already exists - do NOT re-execute financial workflow
        throw InvoiceAlreadyExistsException();
      }

      // 2. Write purchase invoice document
      final invoiceRef = purchaseInvoices(storeId).doc(operationId);
      transaction.set(invoiceRef, {
        'companyId': companyId,
        'companyName': companyName,
        if (supplierInvoiceNumber != null)
          'supplierInvoiceNumber': supplierInvoiceNumber,
        'totalAmountFils': totalAmountFils,
        'shopCashAmountFils': shopCashAmountFils,
        'outsideCashAmountFils': outsideCashAmountFils,
        'supplierDebtAmountFils': supplierDebtAmountFils,
        'notes': notes,
        'status': 'ACTIVE',
        'createdAt': FieldValue.serverTimestamp(),
        'createdBy': createdBy,
        'operationId': operationId,
        'photoIds': photoIds,
      });

      // 3. Write supplier debt document (debtId = invoiceId = operationId)
      final originalAmountFils = supplierDebtAmountFils;
      final remainingAmountFils = originalAmountFils;
      final debtRef = supplierDebts(storeId).doc(operationId);
      transaction.set(debtRef, {
        'invoiceId': operationId,
        'companyId': companyId,
        'companyName': companyName,
        'originalAmountFils': originalAmountFils,
        'remainingAmountFils': remainingAmountFils,
        'status': 'OPEN',
        'createdAt': FieldValue.serverTimestamp(),
        'createdBy': createdBy,
        'operationId': operationId,
        'lastOperationId': operationId,
      });

      // 4. Automatic cash withdrawal when shopCash > 0
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

      // 5. Financial operation/idempotency record (finalized COMPLETED in same tx)
      // In V1: operation record is finalized within the same atomic workflow, no separate completion transaction.
      final opRef = operations(storeId).doc(operationId);
      transaction.set(opRef, {
        'operationId': operationId,
        'type': 'CREATE_PURCHASE_INVOICE',
        'createdBy': createdBy,
        'createdAt': FieldValue.serverTimestamp(),
        'status': 'COMPLETED',
        'retryCount': 0,
      });

      // 6. Return the invoice ID
      return operationId;
    });
  }

  // ---------- Internal transaction helpers ----------

  /// Writes a purchase invoice document within a parent transaction.
  /// The parent workflow (createInvoice) owns the transaction and commits.
  void createInvoiceInTransaction(Transaction transaction,
      {required String storeId,
      required String companyId,
      required String companyName,
      required String? supplierInvoiceNumber,
      required int totalAmountFils,
      required int shopCashAmountFils,
      required int outsideCashAmountFils,
      required int supplierDebtAmountFils,
      required String createdBy,
      required List<String> photoIds}) {
    final invoiceRef =
        purchaseInvoices(storeId).doc(totalAmountFils.toString());
    transaction.set(invoiceRef, {
      'companyId': companyId,
      'companyName': companyName,
      if (supplierInvoiceNumber != null)
        'supplierInvoiceNumber': supplierInvoiceNumber,
      'totalAmountFils': totalAmountFils,
      'shopCashAmountFils': shopCashAmountFils,
      'outsideCashAmountFils': outsideCashAmountFils,
      'supplierDebtAmountFils': supplierDebtAmountFils,
      'notes': null,
      'status': 'ACTIVE',
      'createdAt': FieldValue.serverTimestamp(),
      'createdBy': createdBy,
      'operationId': totalAmountFils.hashCode.toString(),
      'photoIds': photoIds,
    });
  }

  /// Writes a supplier debt document within a parent transaction.
  /// The parent workflow owns the transaction and commits.
  void createDebtInTransaction(Transaction transaction,
      {required String storeId,
      required String companyId,
      required String companyName,
      required int originalAmountFils,
      required int remainingAmountFils,
      required String createdBy}) {
    final debtRef =
        supplierDebts(storeId).doc(originalAmountFils.toString());
    transaction.set(debtRef, {
      'invoiceId': originalAmountFils.toString(),
      'companyId': companyId,
      'companyName': companyName,
      'originalAmountFils': originalAmountFils,
      'remainingAmountFils': remainingAmountFils,
      'status': 'OPEN',
      'createdAt': FieldValue.serverTimestamp(),
      'createdBy': createdBy,
      'operationId': originalAmountFils.toString(),
      'lastOperationId': originalAmountFils.toString(),
    });
  }

  /// Writes an automatic cash withdrawal (linked to purchase invoice)
  /// within a parent transaction. Only called when shopCash > 0.
  void createAutomaticWithdrawalInTransaction(Transaction transaction,
      {required String storeId,
      required int amountFils,
      required String createdBy}) {
    final withdrawalRef =
        cashWithdrawals(storeId).doc('invoice_$amountFils');
    transaction.set(withdrawalRef, {
      'amountFils': amountFils,
      'type': 'PURCHASE_INVOICE',
      'invoiceId': amountFils.toString(),
      'createdAt': FieldValue.serverTimestamp(),
      'createdBy': createdBy,
      'status': 'ACTIVE',
    });
  }

  /// Writes a financial operation/idempotency record within a parent transaction.
  /// The parent workflow owns the transaction and commits.
  /// Status is finalized as COMPLETED in V1 (same atomic workflow, no separate completion transaction).
  void createOperationInTransaction(Transaction transaction,
      {required String storeId,
      required String operationId,
      required String createdBy}) {
    final operationRef = operations(storeId).doc(operationId);
    transaction.set(operationRef, {
      'operationId': operationId,
      'type': 'CREATE_PURCHASE_INVOICE',
      'createdBy': createdBy,
      'createdAt': FieldValue.serverTimestamp(),
      'status': 'COMPLETED',
      'retryCount': 0,
    });
  }
}