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

  @override
  String toString() => 'InsufficientBalanceException: payment exceeds balance.';
}

class CustomerBalanceNotInitializedException implements Exception {
  const CustomerBalanceNotInitializedException();

  @override
  String toString() =>
      'CustomerBalanceNotInitializedException: existing transactions require balance initialization.';
}

class CustomerDebtCancellationBlockedException implements Exception {
  const CustomerDebtCancellationBlockedException();

  @override
  String toString() =>
      'CustomerDebtCancellationBlockedException: cancel related payments first.';
}

class _CustomerBalance {
  const _CustomerBalance({required this.balanceFils, required this.revision});

  final int balanceFils;
  final int revision;
}

class CustomerTransactionRepository {
  CustomerTransactionRepository({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> _transactions(
    String storeId,
    String customerId,
  ) => _firestore
      .collection('stores')
      .doc(storeId)
      .collection('customers')
      .doc(customerId)
      .collection('transactions');

  CollectionReference<Map<String, dynamic>> _customers(String storeId) =>
      _firestore.collection('stores').doc(storeId).collection('customers');

  DocumentReference<Map<String, dynamic>> _balance(
    String storeId,
    String customerId,
  ) =>
      _customers(storeId).doc(customerId).collection('balances').doc('current');

  Future<void> _ensureMissingBalanceHasNoHistory(
    String storeId,
    String customerId,
  ) async {
    final balance = await _balance(storeId, customerId).get();
    if (balance.exists) return;

    final existingTransactions = await _transactions(
      storeId,
      customerId,
    ).limit(1).get();
    if (existingTransactions.docs.isNotEmpty) {
      throw const CustomerBalanceNotInitializedException();
    }
  }

  Future<_CustomerBalance> _readBalance(
    Transaction transaction,
    DocumentReference<Map<String, dynamic>> balanceRef,
  ) async {
    final snapshot = await transaction.get(balanceRef);
    if (!snapshot.exists) {
      return const _CustomerBalance(balanceFils: 0, revision: 0);
    }

    return _parseBalance(snapshot.data()!);
  }

  _CustomerBalance _parseBalance(Map<String, dynamic> data) {
    final balanceFils = data['balanceFils'];
    final previousBalanceFils = data['previousBalanceFils'];
    final revision = data['revision'];
    final lastTransactionId = data['lastTransactionId'];
    final lastAction = data['lastAction'];
    if (balanceFils is! int ||
        balanceFils < 0 ||
        previousBalanceFils is! int ||
        previousBalanceFils < 0 ||
        revision is! int ||
        revision <= 0 ||
        lastTransactionId is! String ||
        lastTransactionId.isEmpty ||
        lastAction is! String ||
        !const {
          'CREATE_DEBT',
          'CREATE_PAYMENT',
          'CANCEL_DEBT',
          'CANCEL_PAYMENT',
        }.contains(lastAction)) {
      throw StateError('Customer balance document has invalid fields.');
    }
    return _CustomerBalance(balanceFils: balanceFils, revision: revision);
  }

  Future<void> _cancelTransaction({
    required String storeId,
    required String customerId,
    required String transactionId,
    required String cancelledBy,
    required String cancellationReason,
  }) async {
    final transactionRef = _transactions(
      storeId,
      customerId,
    ).doc(transactionId);
    final balanceRef = _balance(storeId, customerId);

    await _firestore.runTransaction((transaction) async {
      final transactionDocument = await transaction.get(transactionRef);
      if (!transactionDocument.exists) {
        throw CustomerTransactionNotFoundException();
      }
      final balanceDocument = await transaction.get(balanceRef);
      if (!balanceDocument.exists) {
        throw const CustomerBalanceNotInitializedException();
      }

      final model = CustomerTransactionModel.fromDocument(transactionDocument);
      if (model.status != CustomerTransactionStatus.active) {
        throw StateError('Only active transactions can be cancelled.');
      }
      if (model.cancelledAt != null ||
          model.cancelledBy != null ||
          model.cancellationReason != null) {
        throw StateError(
          'Active transaction must have no cancellation metadata.',
        );
      }

      final balance = _parseBalance(balanceDocument.data()!);
      final isDebt = model.type == CustomerTransactionType.debt;
      final newBalance = isDebt
          ? balance.balanceFils - model.amountFils
          : balance.balanceFils + model.amountFils;
      if (newBalance < 0) {
        throw const CustomerDebtCancellationBlockedException();
      }

      transaction.update(transactionRef, {
        'status': 'CANCELLED',
        'cancelledAt': FieldValue.serverTimestamp(),
        'cancelledBy': cancelledBy,
        'cancellationReason': cancellationReason,
      });
      transaction.set(
        balanceRef,
        _nextBalance(
          balanceFils: newBalance,
          previousBalanceFils: balance.balanceFils,
          revision: balance.revision + 1,
          transactionId: transactionId,
          action: isDebt ? 'CANCEL_DEBT' : 'CANCEL_PAYMENT',
        ),
      );
    });
  }

  Map<String, Object> _nextBalance({
    required int balanceFils,
    required int previousBalanceFils,
    required int revision,
    required String transactionId,
    required String action,
  }) => {
    'balanceFils': balanceFils,
    'previousBalanceFils': previousBalanceFils,
    'revision': revision,
    'lastTransactionId': transactionId,
    'lastAction': action,
  };

  /// Mints a fresh transaction id locally (no network round-trip).
  ///
  /// Callers should mint one id per *logical* operation (e.g. one confirmed
  /// form submission) and pass it to [createDebt]/[createPayment]. Retrying
  /// the same operation with the same id is idempotent: it will not post a
  /// second financial effect. A genuinely new operation must mint a new id.
  String newTransactionId(String storeId, String customerId) =>
      _transactions(storeId, customerId).doc().id;

  /// True when [existing] is the same logical operation as the one being
  /// retried, i.e. replaying it would not change the financial effect.
  static bool _isSameOperation(
    Map<String, dynamic>? existing, {
    required String type,
    required int amountFils,
    required String createdBy,
  }) {
    if (existing == null) return false;
    return existing['type'] == type &&
        existing['amountFils'] == amountFils &&
        existing['createdBy'] == createdBy;
  }

  /// Normalises a caller-supplied note: blank/whitespace-only input is stored
  /// as `null` so documents never carry empty strings.
  static String? _cleanNote(String? note) {
    if (note == null) return null;
    final trimmed = note.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  /// Reads the current document for a caller-supplied [transactionId], if any.
  ///
  /// Deliberately a collection query rather than a single-document read:
  /// the `get` rule for transactions dereferences `resource.data`, which is
  /// `null` for a document that does not exist yet, so a single-doc read is
  /// denied for non-admin callers. A query is governed by the `list` rule,
  /// which both roles satisfy for an active customer. The `set` inside the
  /// transaction is still rejected by the `create` rule if the document
  /// already exists, so this check exists only to keep retries clean.
  Future<Map<String, dynamic>?> _readExistingTransaction(
    String storeId,
    String customerId,
    String transactionId,
  ) async {
    final snapshot = await _transactions(
      storeId,
      customerId,
    ).where(FieldPath.documentId, isEqualTo: transactionId).limit(1).get();
    if (snapshot.docs.isEmpty) return null;
    return snapshot.docs.first.data();
  }

  Stream<List<CustomerTransactionModel>> watchTransactions(
    String storeId,
    String customerId,
  ) {
    return _transactions(storeId, customerId)
        .orderBy('createdAt')
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .map((doc) => CustomerTransactionModel.fromDocument(doc))
              .toList(),
        );
  }

  Future<String> createDebt({
    required String storeId,
    required String customerId,
    required int amountFils,
    required String createdBy,
    String? transactionId,
    String? note,
  }) async {
    final customerDoc = await _customers(storeId).doc(customerId).get();
    if (!customerDoc.exists) {
      throw CustomerTransactionNotFoundException();
    }
    final customer = CustomerModel.fromDocument(customerDoc);

    final timestamp = FieldValue.serverTimestamp();

    // The customer transaction document itself is the durable operation
    // record. No separate stores/{storeId}/operations document is written:
    // that collection is reserved for multi-document invoice/payment
    // coordination and does not accept customer operation types.
    if (!customer.debtEnabled) {
      throw StateError(
        'Customer debt is disabled. Admin may enable debt or override rules.',
      );
    }

    if (amountFils <= 0) {
      throw ArgumentError.value(amountFils, 'amountFils', 'Must be > 0.');
    }

    final debtRef = transactionId == null
        ? _transactions(storeId, customerId).doc()
        : _transactions(storeId, customerId).doc(transactionId);

    // Idempotency pre-check, run OUTSIDE the transaction and as a collection
    // query. See _readExistingTransaction for why this cannot be a
    // transaction.get() on the target ref: it would be denied for employees.
    if (transactionId != null) {
      final existing = await _readExistingTransaction(
        storeId,
        customerId,
        transactionId,
      );
      if (existing != null) {
        if (_isSameOperation(
          existing,
          type: 'DEBT',
          amountFils: amountFils,
          createdBy: createdBy,
        )) {
          // Idempotent replay: the debt is already recorded. Report success
          // without touching Firestore.
          return debtRef.id;
        }
        // Same id but a different operation: refuse explicitly rather than
        // silently creating or overwriting a second financial record.
        throw const CustomerTransactionAlreadyExistsException();
      }
    }

    await _ensureMissingBalanceHasNoHistory(storeId, customerId);
    final balanceRef = _balance(storeId, customerId);

    return _firestore.runTransaction((transaction) async {
      final balance = await _readBalance(transaction, balanceRef);
      // NOTE: the cancellation fields (cancelledAt/cancelledBy/
      // cancellationReason) are intentionally ABSENT here. A brand-new
      // transaction has no cancellation metadata, and FieldValue.delete() is
      // not allowed in Transaction.set() without merge:true — it throws
      // invalid-argument and broke every save. Cancellation metadata is added
      // later, only via adminCancelTransaction's update().
      transaction.set(debtRef, {
        'type': 'DEBT',
        'amountFils': amountFils,
        'createdAt': timestamp,
        'createdBy': createdBy,
        'status': 'ACTIVE',
        'note': _cleanNote(note),
      });
      transaction.set(
        balanceRef,
        _nextBalance(
          balanceFils: balance.balanceFils + amountFils,
          previousBalanceFils: balance.balanceFils,
          revision: balance.revision + 1,
          transactionId: debtRef.id,
          action: 'CREATE_DEBT',
        ),
      );

      return debtRef.id;
    });
  }

  Future<String> createPayment({
    required String storeId,
    required String customerId,
    required int amountFils,
    required String createdBy,
    String? transactionId,
    String? note,
  }) async {
    final customerDoc = await _customers(storeId).doc(customerId).get();
    if (!customerDoc.exists) {
      throw CustomerTransactionNotFoundException();
    }

    final timestamp = FieldValue.serverTimestamp();

    if (amountFils <= 0) {
      throw ArgumentError.value(amountFils, 'amountFils', 'Must be > 0.');
    }

    // Payment is allowed even when debtEnabled == false.
    // Balance validation is enforced by Firestore Rules.
    final paymentRef = transactionId == null
        ? _transactions(storeId, customerId).doc()
        : _transactions(storeId, customerId).doc(transactionId);

    // Same idempotent-replay guard as createDebt: a retried payment with a
    // stable id must not debit the customer twice. Runs outside the
    // transaction for the same rules-safety reason.
    if (transactionId != null) {
      final existing = await _readExistingTransaction(
        storeId,
        customerId,
        transactionId,
      );
      if (existing != null) {
        if (_isSameOperation(
          existing,
          type: 'PAYMENT',
          amountFils: amountFils,
          createdBy: createdBy,
        )) {
          return paymentRef.id;
        }
        throw const CustomerTransactionAlreadyExistsException();
      }
    }

    await _ensureMissingBalanceHasNoHistory(storeId, customerId);
    final balanceRef = _balance(storeId, customerId);

    return _firestore.runTransaction((transaction) async {
      final balance = await _readBalance(transaction, balanceRef);
      if (amountFils > balance.balanceFils) {
        throw const InsufficientBalanceException();
      }

      // Same as createDebt: cancellation fields are intentionally absent;
      // FieldValue.delete() is invalid in Transaction.set() without merge.
      transaction.set(paymentRef, {
        'type': 'PAYMENT',
        'amountFils': amountFils,
        'createdAt': timestamp,
        'createdBy': createdBy,
        'status': 'ACTIVE',
        'note': _cleanNote(note),
      });
      transaction.set(
        balanceRef,
        _nextBalance(
          balanceFils: balance.balanceFils - amountFils,
          previousBalanceFils: balance.balanceFils,
          revision: balance.revision + 1,
          transactionId: paymentRef.id,
          action: 'CREATE_PAYMENT',
        ),
      );

      return paymentRef.id;
    });
  }

  Future<CustomerTransactionModel> getTransaction(
    String storeId,
    String customerId,
    String transactionId,
  ) async {
    // Outside transaction: doc.get() returns Future<DocumentSnapshot>, need await
    final document = await _transactions(
      storeId,
      customerId,
    ).doc(transactionId).get();
    if (!document.exists) {
      throw CustomerTransactionNotFoundException();
    }
    return CustomerTransactionModel.fromDocument(document);
  }

  Future<List<CustomerTransactionModel>> listTransactions(
    String storeId,
    String customerId,
  ) async {
    // Outside transaction: collection.get() returns Future<QuerySnapshot>, need await
    final snapshot = await _transactions(
      storeId,
      customerId,
    ).orderBy('createdAt').get();
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

  Future<int> calculateBalanceAsync(String storeId, String customerId) async {
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
  }) => _cancelTransaction(
    storeId: storeId,
    customerId: customerId,
    transactionId: transactionId,
    cancelledBy: cancelledBy,
    cancellationReason: cancellationReason,
  );

  Future<void> adminCancelTransaction({
    required String storeId,
    required String customerId,
    required String transactionId,
    required String cancelledBy,
    required String cancellationReason,
  }) => _cancelTransaction(
    storeId: storeId,
    customerId: customerId,
    transactionId: transactionId,
    cancelledBy: cancelledBy,
    cancellationReason: cancellationReason,
  );
}
