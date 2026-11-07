import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/cash_deposit_model.dart';
import '../models/cash_withdrawal_model.dart';
import '../models/financial_operation_model.dart';
import '../models/purchase_invoice_model.dart';
import '../models/supplier_payment_model.dart';

class FinancialOperationRepository {
  FinancialOperationRepository({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> operations(String storeId) =>
      _firestore.collection('stores').doc(storeId).collection('operations');

  CollectionReference<Map<String, dynamic>> _purchaseInvoices(
    String storeId,
  ) => _firestore
      .collection('stores')
      .doc(storeId)
      .collection('purchaseInvoices');

  CollectionReference<Map<String, dynamic>> _supplierPayments(
    String storeId,
  ) => _firestore
      .collection('stores')
      .doc(storeId)
      .collection('supplierPayments');

  CollectionReference<Map<String, dynamic>> _cashWithdrawals(
    String storeId,
  ) => _firestore
      .collection('stores')
      .doc(storeId)
      .collection('cashWithdrawals');

  CollectionReference<Map<String, dynamic>> _cashDeposits(String storeId) =>
      _firestore
          .collection('stores')
          .doc(storeId)
          .collection('cashDeposits');

  Future<List<FinancialOperationLogEntry>> listOperations({
    required String storeId,
    required bool isAdmin,
    required String currentUserId,
  }) async {
    Query<Map<String, dynamic>> query = operations(storeId);
    if (!isAdmin) {
      query = query.where('createdBy', isEqualTo: currentUserId);
    }

    final snapshot = await query.get();
    final operationModels = snapshot.docs
        .map(FinancialOperationModel.fromDocument)
        .toList();
    final relatedDocuments =
        <String, Future<DocumentSnapshot<Map<String, dynamic>>>>{};
    final entries = await Future.wait(
      operationModels.map(
        (operation) => _buildLogEntry(
          storeId: storeId,
          operation: operation,
          relatedDocuments: relatedDocuments,
        ),
      ),
    );
    entries.sort(
      (a, b) => b.operation.createdAt.compareTo(a.operation.createdAt),
    );
    return entries;
  }

  Future<FinancialOperationLogEntry> _buildLogEntry({
    required String storeId,
    required FinancialOperationModel operation,
    required Map<String, Future<DocumentSnapshot<Map<String, dynamic>>>>
    relatedDocuments,
  }) async {
    final details = await _loadRelatedDetails(
      storeId: storeId,
      operation: operation,
      relatedDocuments: relatedDocuments,
    );
    return FinancialOperationLogEntry(
      operation: operation,
      amountFils: operation.amountFils ?? details.amountFils,
      cancellationReason: details.cancellationReason,
    );
  }

  Future<({int? amountFils, String? cancellationReason})> _loadRelatedDetails({
    required String storeId,
    required FinancialOperationModel operation,
    required Map<String, Future<DocumentSnapshot<Map<String, dynamic>>>>
    relatedDocuments,
  }) async {
    if (operation.invoiceId case final invoiceId?) {
      final snapshot = await _getRelatedDocument(
        relatedDocuments,
        _purchaseInvoices(storeId).doc(invoiceId),
      );
      if (!snapshot.exists) return (amountFils: null, cancellationReason: null);
      final invoice = PurchaseInvoiceModel.fromDocument(snapshot);
      return (
        amountFils: invoice.totalAmountFils,
        cancellationReason: operation.type ==
                FinancialOperationType.cancelPurchaseInvoice
            ? invoice.cancellationReason
            : null,
      );
    }

    if (operation.paymentId case final paymentId?) {
      final snapshot = await _getRelatedDocument(
        relatedDocuments,
        _supplierPayments(storeId).doc(paymentId),
      );
      if (!snapshot.exists) return (amountFils: null, cancellationReason: null);
      final payment = SupplierPaymentModel.fromDocument(snapshot);
      return (
        amountFils: payment.amountFils,
        cancellationReason: operation.type ==
                FinancialOperationType.cancelSupplierPayment
            ? payment.cancellationReason
            : null,
      );
    }

    if (operation.withdrawalId case final withdrawalId?) {
      final snapshot = await _getRelatedDocument(
        relatedDocuments,
        _cashWithdrawals(storeId).doc(withdrawalId),
      );
      if (!snapshot.exists) return (amountFils: null, cancellationReason: null);
      final withdrawal = CashWithdrawalModel.fromDocument(snapshot);
      return (
        amountFils: withdrawal.amountFils,
        cancellationReason: operation.type ==
                FinancialOperationType.cancelManualWithdrawal
            ? withdrawal.cancellationReason
            : null,
      );
    }

    if (operation.depositId case final depositId?) {
      final snapshot = await _getRelatedDocument(
        relatedDocuments,
        _cashDeposits(storeId).doc(depositId),
      );
      if (!snapshot.exists) return (amountFils: null, cancellationReason: null);
      final deposit = CashDepositModel.fromDocument(snapshot);
      return (amountFils: deposit.amountFils, cancellationReason: null);
    }

    return (amountFils: null, cancellationReason: null);
  }

  Future<DocumentSnapshot<Map<String, dynamic>>> _getRelatedDocument(
    Map<String, Future<DocumentSnapshot<Map<String, dynamic>>>> cache,
    DocumentReference<Map<String, dynamic>> reference,
  ) => cache.putIfAbsent(reference.path, reference.get);
}
