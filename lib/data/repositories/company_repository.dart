import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/company_model.dart';

class CompanyAlreadyExistsException implements Exception {
  const CompanyAlreadyExistsException();
}

class CompanyRepository {
  CompanyRepository({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> _companies(String storeId) =>
      _firestore.collection('stores').doc(storeId).collection('companies');

  CollectionReference<Map<String, dynamic>> _nameKeys(String storeId) =>
      _firestore
          .collection('stores')
          .doc(storeId)
          .collection('companyNameKeys');

  static String normalizeName(String name) => name.trim().toLowerCase();

  static String nameKey(String name) =>
      'c_${base64Url.encode(utf8.encode(normalizeName(name))).replaceAll('=', '')}';

  Future<List<CompanyModel>> listCompanies(String storeId) async {
    final snapshot = await _companies(storeId).orderBy('name').get();
    return snapshot.docs.map(CompanyModel.fromDocument).toList();
  }

  Future<List<CompanyModel>> listActiveCompanies(String storeId) async {
    final snapshot = await _companies(storeId)
        .where('isActive', isEqualTo: true)
        .orderBy('name')
        .get();
    return snapshot.docs.map(CompanyModel.fromDocument).toList();
  }

  Future<CompanyModel?> getCompany(String storeId, String companyId) async {
    final document = await _companies(storeId).doc(companyId).get();
    return document.exists ? CompanyModel.fromDocument(document) : null;
  }

  Future<String> createCompany({
    required String storeId,
    required String name,
    String? phone,
  }) async {
    final cleanName = _validatedName(name);
    final cleanPhone = _cleanPhone(phone);
    final companyRef = _companies(storeId).doc();
    final claimRef = _nameKeys(storeId).doc(nameKey(cleanName));

    await _firestore.runTransaction((transaction) async {
      final existingClaim = await transaction.get(claimRef);
      if (existingClaim.exists) {
        throw const CompanyAlreadyExistsException();
      }

      final timestamp = FieldValue.serverTimestamp();
      transaction.set(companyRef, {
        'name': cleanName,
        if (cleanPhone != null) 'phone': cleanPhone,
        'isActive': true,
        'createdAt': timestamp,
        'updatedAt': timestamp,
      });
      transaction.set(claimRef, {
        'companyId': companyRef.id,
        'normalizedName': normalizeName(cleanName),
      });
    });

    return companyRef.id;
  }

  Future<void> updateCompany({
    required String storeId,
    required String companyId,
    required String name,
    String? phone,
    required bool isActive,
  }) async {
    final cleanName = _validatedName(name);
    final cleanPhone = _cleanPhone(phone);
    final companyRef = _companies(storeId).doc(companyId);

    await _firestore.runTransaction((transaction) async {
      final companyDocument = await transaction.get(companyRef);
      if (!companyDocument.exists) {
        throw StateError('Company not found.');
      }
      final company = CompanyModel.fromDocument(companyDocument);
      final oldName = company.name;
      final oldKey = nameKey(oldName);
      final newKey = nameKey(cleanName);
      final oldClaimRef = _nameKeys(storeId).doc(oldKey);
      final oldClaim = await transaction.get(oldClaimRef);

      if (!oldClaim.exists ||
          oldClaim.data()?['companyId'] != companyId ||
          oldClaim.data()?['normalizedName'] != normalizeName(oldName)) {
        throw StateError('Company name claim is inconsistent.');
      }

      if (oldKey != newKey) {
        final newClaimRef = _nameKeys(storeId).doc(newKey);
        final newClaim = await transaction.get(newClaimRef);
        if (newClaim.exists) {
          throw const CompanyAlreadyExistsException();
        }

        transaction.set(newClaimRef, {
          'companyId': companyId,
          'normalizedName': normalizeName(cleanName),
        });
        transaction.delete(oldClaimRef);
      }

      transaction.update(companyRef, {
        'name': cleanName,
        if (cleanPhone == null)
          'phone': FieldValue.delete()
        else
          'phone': cleanPhone,
        'isActive': isActive,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    });
  }

  Future<void> setCompanyActive({
    required String storeId,
    required String companyId,
    required bool isActive,
  }) async {
    final companyRef = _companies(storeId).doc(companyId);
    await _firestore.runTransaction((transaction) async {
      final company = await transaction.get(companyRef);
      if (!company.exists) {
        throw StateError('Company not found.');
      }
      if (company.data()?['isActive'] == isActive) return;

      transaction.update(companyRef, {
        'isActive': isActive,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    });
  }

  String _validatedName(String name) {
    final cleanName = name.trim();
    if (cleanName.isEmpty || cleanName.length > 120) {
      throw const FormatException('Enter a company name up to 120 characters.');
    }
    return cleanName;
  }

  String? _cleanPhone(String? phone) {
    final cleanPhone = phone?.trim();
    return cleanPhone == null || cleanPhone.isEmpty ? null : cleanPhone;
  }
}
