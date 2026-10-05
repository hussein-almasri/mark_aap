import 'package:cloud_firestore/cloud_firestore.dart';

import '../../core/utils/join_code.dart';

abstract interface class EmployeeJoinCodeLookup {
  Future<String?> findStoreIdForClaim(String normalizedCode);
  Future<bool> storeExists(String storeId);
}

class FirestoreEmployeeJoinCodeLookup implements EmployeeJoinCodeLookup {
  FirestoreEmployeeJoinCodeLookup({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  @override
  Future<String?> findStoreIdForClaim(String normalizedCode) async {
    final snapshot = await _firestore
        .collection('storeJoinCodes')
        .doc(normalizedCode)
        .get();
    if (!snapshot.exists) return null;
    return snapshot.data()?['storeId'] as String?;
  }

  @override
  Future<bool> storeExists(String storeId) async =>
      (await _firestore.collection('stores').doc(storeId).get()).exists;
}

enum EmployeeJoinCodeStatus { valid, invalidCode, missingStore }

class EmployeeJoinCodeResult {
  const EmployeeJoinCodeResult(this.status, {this.storeId});

  final EmployeeJoinCodeStatus status;
  final String? storeId;
}

class EmployeeJoinCodeValidator {
  EmployeeJoinCodeValidator({EmployeeJoinCodeLookup? lookup})
    : _lookup = lookup ?? FirestoreEmployeeJoinCodeLookup();

  final EmployeeJoinCodeLookup _lookup;

  Future<EmployeeJoinCodeResult> validate(String rawCode) async {
    if (!JoinCode.isValidFormat(rawCode)) {
      return const EmployeeJoinCodeResult(EmployeeJoinCodeStatus.invalidCode);
    }

    final normalizedCode = JoinCode.normalize(rawCode);
    final storeId = await _lookup.findStoreIdForClaim(normalizedCode);
    if (storeId == null || storeId.isEmpty) {
      return const EmployeeJoinCodeResult(EmployeeJoinCodeStatus.invalidCode);
    }

    if (!await _lookup.storeExists(storeId)) {
      return const EmployeeJoinCodeResult(EmployeeJoinCodeStatus.missingStore);
    }

    return EmployeeJoinCodeResult(
      EmployeeJoinCodeStatus.valid,
      storeId: storeId,
    );
  }
}
