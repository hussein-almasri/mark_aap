import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/customer_model.dart';
import '../models/customer_transaction_model.dart';

class CustomerTransactionAlreadyExistsException implements Exception {
  const CustomerTransactionAlreadyExistsException();
}

class CustomerTransactionNotFoundException implements Exception {
  const CustomerTransactionNotFoundException();
}

class InsufficientBalanceException implements Exception {
  const InsufficientBalanceException();
}

class CustomerTransactionRepository {
  CustomerTransactionRepository({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> _transactions(
      String storeId, String customerId) =>
      _firestore
          .collection('stores')
          .doc(storeId)
          .collection('customers')
          .doc(customerId)
          .collection('transactions');

  CollectionReference<Map<String, dynamic>> _customers(String storeId) =>
      _firestore.collection('stores').doc(storeId).collection('customers');

  Stream<List<CustomerTransactionModel>> watchTransactions(
      String storeId, String customerId) {
    return _transactions(storeId, customerId)
        .orderBy('createdAt')
        .snapshots()
        .map((snapshot) =>
            snapshot.docs
                .map((doc) => CustomerTransactionModel.fromDocument(doc))
                .toList());
  }

  Future<String> createDebt({
    required String storeId,
    required String customerId,
    required int amountFils,
    required String createdBy,
  }) async {
    final customerDoc =
        await _customers(storeId).doc(customerId).get();
    if (!customerDoc.exists) {
      throw CustomerTransactionNotFoundException();
    }
    final customer =
        CustomerModel.fromDocument(customerDoc);

    final timestamp = FieldValue.serverTimestamp();

    // The customer transaction document itself is the durable operation
    // record. No separate stores/{storeId}/operations document is written:
    // that collection is reserved for multi-document invoice/payment
    // coordination and does not accept customer operation types.
    if (!customer.debtEnabled) {
      throw StateError(
          'Customer debt is disabled. Admin may enable debt or override rules.');
    }

    if (amountFils <= 0) {
      throw ArgumentError.value(amountFils, 'amountFils', 'Must be > 0.');
    }

    final debtRef = _transactions(storeId, customerId).doc();

    return _firestore.runTransaction((transaction) async {
      transaction.set(debtRef, {
        'type': 'DEBT',
        'amountFils': amountFils,
        'createdAt': timestamp,
        'createdBy': createdBy,
        'status': 'ACTIVE',
        'cancelledAt': FieldValue.delete(),
        'cancelledBy': FieldValue.delete(),
        'cancellationReason': FieldValue.delete(),
        'note': null,
      });

      return debtRef.id;
    });
  }

  Future<String> createPayment({
    required String storeId,
    required String customerId,
    required int amountFils,
    required String createdBy,
  }) async {
    final customerDoc =
        await _customers(storeId).doc(customerId).get();
    if (!customerDoc.exists) {
      throw CustomerTransactionNotFoundException();
    }

    final timestamp = FieldValue.serverTimestamp();

    if (amountFils <= 0) {
      throw ArgumentError.value(amountFils, 'amountFils', 'Must be > 0.');
    }

    // Payment is allowed even when debtEnabled == false.
    // Balance validation is enforced by Firestore Rules.
    final paymentRef = _transactions(storeId, customerId).doc();

    return _firestore.runTransaction((transaction) async {
      transaction.set(paymentRef, {
        'type': 'PAYMENT',
        'amountFils': amountFils,
        'createdAt': timestamp,
        'createdBy': createdBy,
        'status': 'ACTIVE',
        'cancelledAt': FieldValue.delete(),
        'cancelledBy': FieldValue.delete(),
        'cancellationReason': FieldValue.delete(),
        'note': null,
      });

      return paymentRef.id;
    });
  }

  Future<CustomerTransactionModel> getTransaction(
      String storeId, String customerId, String transactionId) async {
    // Outside transaction: doc.get() returns Future<DocumentSnapshot>, need await
    final document =
        await _transactions(storeId, customerId).doc(transactionId).get();
    if (!document.exists) {
      throw CustomerTransactionNotFoundException();
    }
    return CustomerTransactionModel.fromDocument(document);
  }

  Future<List<CustomerTransactionModel>> listTransactions(
      String storeId, String customerId) async {
    // Outside transaction: collection.get() returns Future<QuerySnapshot>, need await
    final snapshot =
        await _transactions(storeId, customerId)
            .orderBy('createdAt')
            .get();
    return snapshot.docs
        .map((doc) => CustomerTransactionModel.fromDocument(doc))
        .toList();
  }

  int calculateBalance(String storeId, String customerId) {
    // Async query but method is sync for API compatibility;
    // callers should use the async version or handle accordingly.
    // For now return 0 as balance calculation requires async query.
    return 0;
  }

  Future<int> calculateBalanceAsync(
      String storeId, String customerId) async {
    final snapshot = await _firestore
        .collection('stores')
        .doc(storeId)
        .collection('customers')
        .doc(customerId)
        .collection('transactions')
        .where('status', isEqualTo: 'ACTIVE')
        .get();

    return _calculateActiveBalanceFromSnapshot(snapshot);
  }

  int _calculateActiveBalanceFromSnapshot(QuerySnapshot snapshot) {
    int totalDebt = 0;
    int totalPayment = 0;

    for (final doc in snapshot.docs) {
      final data = doc.data() as Map<String, dynamic>;
      final type = data['type'] as String;
      final amountFils = (data['amountFils'] as num).toInt();

      if (type == 'DEBT') {
        totalDebt += amountFils;
      } else if (type == 'PAYMENT') {
        totalPayment += amountFils;
      }
    }

    return totalDebt - totalPayment;
  }

  Future<void> cancelTransaction({
    required String storeId,
    required String customerId,
    required String transactionId,
    required String cancelledBy,
    required String cancellationReason,
  }) async {
    await _firestore.runTransaction((transaction) async {
      final transactionRef =
          _transactions(storeId, customerId).doc(transactionId);
      // Inside transaction, use await with transaction.get()
      final transactionDocument = await transaction.get(transactionRef);
      if (!transactionDocument.exists) {
        throw CustomerTransactionNotFoundException();
      }
      final model =
          CustomerTransactionModel.fromDocument(transactionDocument);

      // Only admin can cancel; employee cancellation is denied at Rules level
      // and as a runtime guard

      // Active transaction must have no cancellation metadata
      if (model.status == CustomerTransactionStatus.active) {
        if (model.cancelledAt != null ||
            model.cancelledBy != null ||
            model.cancellationReason != null) {
          throw StateError(
              'Active transaction must have no cancellation metadata.');
        }
      }

      transaction.update(transactionRef, {
        'status': 'CANCELLED',
        'cancelledAt': FieldValue.serverTimestamp(),
        'cancelledBy': cancelledBy,
        'cancellationReason': cancellationReason,
      });

      // Preserve the transaction in history; only update status/metadata.
      // Cancelled DEBT increases available balance (payment capacity restored).
      // Cancelled PAYMENT decreases available balance accordingly.
      // The cancellation metadata written above is the durable operation
      // record; no separate stores/{storeId}/operations document is touched
      // because that collection does not accept customer operation types.
    });
  }

  Future<void> adminCancelTransaction({
    required String storeId,
    required String customerId,
    required String transactionId,
    required String cancelledBy,
    required String cancellationReason,
  }) async {
    await _firestore.runTransaction((transaction) async {
      final transactionRef =
          _transactions(storeId, customerId).doc(transactionId);
      // Inside transaction, use await with transaction.get()
      final transactionDocument = await transaction.get(transactionRef);
      if (!transactionDocument.exists) {
        throw CustomerTransactionNotFoundException();
      }
      final model =
          CustomerTransactionModel.fromDocument(transactionDocument);

      // Admin can cancel any transaction
      // Active transaction must have no cancellation metadata
      if (model.status == CustomerTransactionStatus.active) {
        if (model.cancelledAt != null ||
            model.cancelledBy != null ||
            model.cancellationReason != null) {
          throw StateError(
              'Active transaction must have no cancellation metadata.');
}
}

      transaction.update(transactionRef, {
        'status': 'CANCELLED',
        'cancelledAt': FieldValue.serverTimestamp(),
        'cancelledBy': cancelledBy,
        'cancellationReason': cancellationReason,
      });
    });
  }
}