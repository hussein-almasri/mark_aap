import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/customer_model.dart';

class CustomerAlreadyExistsException implements Exception {
  const CustomerAlreadyExistsException();
}

class CustomerNotFoundException implements Exception {
  const CustomerNotFoundException();
}

class CustomerRepository {
  CustomerRepository({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> _customers(String storeId) =>
      _firestore.collection('stores').doc(storeId).collection('customers');

  CollectionReference<Map<String, dynamic>> _nameKeys(String storeId) =>
      _firestore
          .collection('stores')
          .doc(storeId)
          .collection('customerNameKeys');

  static String normalizeName(String name) => name.trim().toLowerCase();

  static String nameKey(String name) =>
      "c_${base64Url.encode(utf8.encode(normalizeName(name))).replaceAll('=', '')}";

  Stream<List<CustomerModel>> watchCustomers(String storeId) {
    return _customers(storeId)
        .where('isActive', isEqualTo: true)
        .orderBy('name')
        .snapshots()
        .map((snapshot) => snapshot.docs.map((doc) => CustomerModel.fromDocument(doc)).toList());
  }

  Stream<List<CustomerModel>> watchInactiveCustomers(String storeId) {
    return _customers(storeId)
        .orderBy('name')
        .snapshots()
        .map((snapshot) => snapshot.docs.map((doc) => CustomerModel.fromDocument(doc)).toList());
  }

  Future<List<CustomerModel>> listCustomers(String storeId) async {
    final snapshot = await _customers(storeId).orderBy('name').get();
    return snapshot.docs.map((doc) => CustomerModel.fromDocument(doc)).toList();
  }

  Future<List<CustomerModel>> listActiveCustomers(String storeId) async {
    final snapshot = await _customers(storeId)
        .where('isActive', isEqualTo: true)
        .get();
    return snapshot.docs.map((doc) => CustomerModel.fromDocument(doc)).toList();
  }

  Future<CustomerModel> getCustomer(String storeId, String customerId) async {
    final document = await _customers(storeId).doc(customerId).get();
    if (!document.exists) {
      throw CustomerNotFoundException();
    }
    return CustomerModel.fromDocument(document);
  }

  Future<String> createCustomer({
    required String storeId,
    required String name,
    String? phone,
    required bool debtEnabled,
    required String createdBy,
  }) async {
    final cleanName = name.trim();
    if (cleanName.isEmpty || cleanName.length > 120) {
      throw const FormatException('Enter a customer name up to 120 characters.');
    }
    final cleanPhone = phone?.trim();
    final timestamp = FieldValue.serverTimestamp();
    final normalizedName = normalizeName(cleanName);
    final key = nameKey(cleanName);
    final customerRef = _customers(storeId).doc();

    await _firestore.runTransaction((transaction) async {
      final nameClaim = await transaction.get(_nameKeys(storeId).doc(key));
      if (nameClaim.exists) {
        throw const CustomerAlreadyExistsException();
      }

      transaction.set(customerRef, {
        'name': cleanName,
        'phone': cleanPhone,
        'debtEnabled': debtEnabled,
        'isActive': true,
        'createdAt': timestamp,
        'updatedAt': timestamp,
        'createdBy': createdBy,
        'updatedBy': createdBy,
      });
      transaction.set(_nameKeys(storeId).doc(key), {
        'customerId': customerRef.id,
        'normalizedName': normalizedName,
      });
    });

    return customerRef.id;
  }

  Future<void> updateCustomer({
    required String storeId,
    required String customerId,
    required String name,
    String? phone,
    required bool debtEnabled,
    required String updatedBy,
  }) async {
    final cleanName = name.trim();
    if (cleanName.isEmpty || cleanName.length > 120) {
      throw const FormatException('Enter a customer name up to 120 characters.');
    }
    final cleanPhone = phone?.trim();
    final normalizedName = normalizeName(cleanName);
    final newKey = nameKey(cleanName);

    await _firestore.runTransaction((transaction) async {
      final customerRef = _customers(storeId).doc(customerId);
      final customerDocument = await transaction.get(customerRef);
      if (!customerDocument.exists) {
        throw CustomerNotFoundException();
      }
      final customer = CustomerModel.fromDocument(customerDocument);
      final oldName = customer.name;
      final oldKey = nameKey(oldName);
      final oldClaimRef = _nameKeys(storeId).doc(oldKey);
      final oldClaim = await transaction.get(oldClaimRef);

      if (!oldClaim.exists ||
          oldClaim.data()?['customerId'] != customerId ||
          oldClaim.data()?['normalizedName'] != normalizeName(oldName)) {
        throw StateError('Customer name claim is inconsistent.');
      }

      if (oldKey != newKey) {
        final newClaimRef = _nameKeys(storeId).doc(newKey);
        final newClaim = await transaction.get(newClaimRef);
        if (newClaim.exists) {
          throw const CustomerAlreadyExistsException();
        }
        transaction.set(newClaimRef, {
          'customerId': customerId,
          'normalizedName': normalizedName,
        });
        transaction.delete(oldClaimRef);
      }

      transaction.update(customerRef, {
        'name': cleanName,
        if (cleanPhone == null)
          'phone': FieldValue.delete()
        else
          'phone': cleanPhone,
        'debtEnabled': debtEnabled,
        'updatedAt': FieldValue.serverTimestamp(),
        'updatedBy': updatedBy,
      });
    });
  }

  Future<void> deactivateCustomer({
    required String storeId,
    required String customerId,
    required String updatedBy,
  }) async {
    await _firestore.runTransaction((transaction) async {
      final customerRef = _customers(storeId).doc(customerId);
      final customerDocument = await transaction.get(customerRef);
      if (!customerDocument.exists) {
        throw CustomerNotFoundException();
      }
      if (customerDocument.data()?['isActive'] == false) return;

      transaction.update(customerRef, {
        'isActive': false,
        'updatedAt': FieldValue.serverTimestamp(),
        'updatedBy': updatedBy,
      });
    });
  }

  Future<void> reactivateCustomer({
    required String storeId,
    required String customerId,
    required String updatedBy,
  }) async {
    await _firestore.runTransaction((transaction) async {
      final customerRef = _customers(storeId).doc(customerId);
      final customerDocument = await transaction.get(customerRef);
      if (!customerDocument.exists) {
        throw CustomerNotFoundException();
      }
      if (customerDocument.data()?['isActive'] == true) return;

      transaction.update(customerRef, {
        'isActive': true,
        'updatedAt': FieldValue.serverTimestamp(),
        'updatedBy': updatedBy,
      });
    });
  }
}