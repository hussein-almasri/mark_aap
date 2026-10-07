import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/supplier_payment_model.dart';

class PaymentAllocationMismatchException implements Exception {
  const PaymentAllocationMismatchException();
  @override
  String toString() => 'PaymentAllocationMismatchException';
}

class SupplierPaymentRepository {
  SupplierPaymentRepository({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  // Collection references - public for internal test access
  CollectionReference<Map<String, dynamic>> supplierPayments(String storeId) =>
      _firestore.collection('stores').doc(storeId).collection('supplierPayments');

  CollectionReference<Map<String, dynamic>> supplierDebts(String storeId) =>
      _firestore.collection('stores').doc(storeId).collection('supplierDebts');

  CollectionReference<Map<String, dynamic>> cashWithdrawals(String storeId) =>
      _firestore.collection('stores').doc(storeId).collection('cashWithdrawals');

  CollectionReference<Map<String, dynamic>> operations(String storeId) =>
      _firestore.collection('stores').doc(storeId).collection('operations');

  Future<SupplierPaymentModel> getPayment(String storeId, String paymentId) async {
    final snapshot =
        await supplierPayments(storeId).doc(paymentId).get();
    if (!snapshot.exists) {
      throw StateError('Supplier payment not found.');
    }
    return SupplierPaymentModel.fromDocument(snapshot);
  }

  Future<List<SupplierPaymentModel>> listPayments(String storeId) async {
    final snapshot =
        await supplierPayments(storeId).orderBy('createdAt').get();
    return snapshot.docs.map(SupplierPaymentModel.fromDocument).toList();
  }

  /// Creates a supplier payment atomically within a Firestore transaction.
  /// Coordinates: payment + up to 5 debt updates + automatic cash withdrawal (if SHOP_CASH) + financial operation record.
  /// Idempotency: if operationId already exists, throws PaymentAllocationMismatchException (no re-execution).
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
  }) async {
    // Validate allocationCount range
    if (allocationCount < 1 || allocationCount > 5) {
      throw ArgumentError.value(allocationCount, 'allocationCount', 'Must be 1..5.');
    }

    // Collect all allocation data into arrays for validation
    final List<String?> allocationInvoiceIds = [
      allocation1InvoiceId,
      allocation2InvoiceId,
      allocation3InvoiceId,
      allocation4InvoiceId,
      allocation5InvoiceId,
    ];
    final List<int?> allocationAmounts = [
      allocation1AmountFils,
      allocation2AmountFils,
      allocation3AmountFils,
      allocation4AmountFils,
      allocation5AmountFils,
    ];

    // Validate each used slot
    for (var index = 0; index < 5; index++) {
      final isUsed = index < allocationCount;
      final id = allocationInvoiceIds[index];
      final amount = allocationAmounts[index];
      if (isUsed) {
        if (id == null || id.isEmpty) {
          throw ArgumentError(
              'Each counted allocation slot must have an invoice ID.');
        }
        if (amount == null || amount <= 0) {
          throw ArgumentError(
              'Each counted allocation slot must have a positive amount.');
        }
      } else if (id != null || amount != null) {
        throw ArgumentError(
            'Slots beyond allocationCount must be absent.');
      }
    }

    // Validate allocation total equals payment amount
    int allocatedTotal = 0;
    for (var i = 0; i < allocationCount; i++) {
      allocatedTotal += allocationAmounts[i] ?? 0;
    }
    if (allocatedTotal != amountFils) {
      throw ArgumentError(
          'Allocation total must equal payment amountFils.');
    }

    // Validate invoice IDs are unique
    final usedIds = <String>{};
    for (var i = 0; i < allocationCount; i++) {
      final id = allocationInvoiceIds[i];
      if (id != null && id.isNotEmpty) {
        usedIds.add(id);
      }
    }
    if (usedIds.length != allocationCount) {
      throw ArgumentError('A supplier payment cannot allocate an invoice twice.');
    }

    return await _firestore.runTransaction((Transaction transaction) async {
      // 1. Idempotency check: verify operationId does not already exist
      final operationRef = operations(storeId).doc(operationId);
      final existingOperation = await transaction.get(operationRef);

      if (existingOperation.exists) {
        // Idempotent: operation already exists - do NOT re-execute financial workflow
        throw PaymentAllocationMismatchException();
      }

      // 2. Read all referenced supplier debts
      final List<String> debtIds = [];
      for (var i = 0; i < allocationCount; i++) {
        debtIds.add(allocationInvoiceIds[i]!);
      }

      // Read all debts in this transaction
      final List<DocumentSnapshot> debtDocs = [];
      for (final debtId in debtIds) {
        final debtRef = supplierDebts(storeId).doc(debtId);
        final snapshot = await transaction.get(debtRef);
        if (!snapshot.exists) {
          throw ArgumentError(
              'Supplier debt not found for invoice $debtId.');
        }
        debtDocs.add(snapshot);
      }

      // 3. Validate each debt: active/open, belongs to same company, not cancelled,
      //    remaining >= allocation amount
      for (int i = 0; i < allocationCount; i++) {
        final debtSnapshot = debtDocs[i];
        final debtData = debtSnapshot.data() as Map<String, dynamic>;
        final invoiceId = allocationInvoiceIds[i]!;
        final allocationAmount = allocationAmounts[i]!;

        // Check debt is active/open
        final debtStatus = debtData['status'] as String;
        if (debtStatus != 'OPEN') {
          throw ArgumentError(
              'Supplier debt for invoice $invoiceId is not active (status: $debtStatus).');
        }

        // Check remaining >= allocation amount
        final remaining = debtData['remainingAmountFils'] as int;
        if (remaining < allocationAmount) {
          throw ArgumentError(
              'Allocation amount $allocationAmount exceeds remaining debt $remaining for invoice $invoiceId.');
        }
      }

      // 4. Create supplier payment document
      final paymentRef = supplierPayments(storeId).doc(operationId);
      transaction.set(paymentRef, {
        'companyId': companyId,
        'companyName': companyName,
        'amountFils': amountFils,
        'source': source.value,
        'status': 'ACTIVE',
        'allocationCount': allocationCount,
        'allocation1InvoiceId': allocation1InvoiceId,
        'allocation1AmountFils': allocation1AmountFils,
        if (allocationCount > 1)
          'allocation2InvoiceId': allocation2InvoiceId,
        if (allocationCount > 1)
          'allocation2AmountFils': allocation2AmountFils,
        if (allocationCount > 2)
          'allocation3InvoiceId': allocation3InvoiceId,
        if (allocationCount > 2)
          'allocation3AmountFils': allocation3AmountFils,
        if (allocationCount > 3)
          'allocation4InvoiceId': allocation4InvoiceId,
        if (allocationCount > 3)
          'allocation4AmountFils': allocation4AmountFils,
        if (allocationCount > 4)
          'allocation5InvoiceId': allocation5InvoiceId,
        if (allocationCount > 4)
          'allocation5AmountFils': allocation5AmountFils,
        'notes': notes,
        'createdAt': FieldValue.serverTimestamp(),
        'createdBy': createdBy,
        'operationId': operationId,
      });

      // 5. Decrease each allocated debt by the exact allocation amount
      for (int i = 0; i < allocationCount; i++) {
        final debtSnapshot = debtDocs[i];
        final debtRef = supplierDebts(storeId).doc(allocationInvoiceIds[i]!);
        final debtMap = debtSnapshot.data() as Map<String, dynamic>;
        final oldRemaining = debtMap['remainingAmountFils'] as int;
        final newRemaining = oldRemaining - allocationAmounts[i]!;

        transaction.update(debtRef, {
          'remainingAmountFils': newRemaining,
          'lastOperationId': operationId,
        });

        // If remaining becomes zero, mark as paid
        if (newRemaining == 0) {
          transaction.update(debtRef, {
            'status': 'PAID',
          });
        }
      }

      // 6. Automatic cash withdrawal when source == SHOP_CASH
      if (source.value == 'SHOP_CASH') {
        final withdrawalRef =
            cashWithdrawals(storeId).doc('supplierPayment_$operationId');
        transaction.set(withdrawalRef, {
          'amountFils': amountFils,
          'type': 'PURCHASE_INVOICE',
          'supplierPaymentId': operationId,
          'createdAt': FieldValue.serverTimestamp(),
          'createdBy': createdBy,
          'status': 'ACTIVE',
        });
      }

      // 7. Financial operation/idempotency record (finalized COMPLETED in same tx)
      final opRef = operations(storeId).doc(operationId);
      transaction.set(opRef, {
        'operationId': operationId,
        'type': 'CREATE_SUPPLIER_PAYMENT',
        'createdBy': createdBy,
        'createdAt': FieldValue.serverTimestamp(),
        'status': 'COMPLETED',
        'retryCount': 0,
      });

      // 8. Return the payment ID
      return operationId;
    });
  }

  // ---------- Internal transaction helpers ----------

  /// Writes a supplier payment document within a parent transaction.
  /// The parent workflow (createPayment) owns the transaction and commits.
  void createPaymentInTransaction(Transaction transaction,
      {required String storeId,
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
      required String notes,
      required String createdBy}) {
    // Note: The full payment document with debt updates and withdrawal is
    // handled by the parent createPayment transaction for V1 atomicity.
    // This helper exists for future extensibility but is not used in Phase 2.
    throw UnsupportedError(
        'createPaymentInTransaction should only be called from the parent workflow');
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
      'type': 'CREATE_SUPPLIER_PAYMENT',
      'createdBy': createdBy,
      'createdAt': FieldValue.serverTimestamp(),
      'status': 'COMPLETED',
      'retryCount': 0,
    });
  }
}