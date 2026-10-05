import 'package:cloud_firestore/cloud_firestore.dart';

import '../../core/utils/join_code.dart';

abstract interface class EmployeeJoinCodeLookup {
  Future<bool> claimExists(String normalizedCode);
}

class FirestoreEmployeeJoinCodeLookup implements EmployeeJoinCodeLookup {
  FirestoreEmployeeJoinCodeLookup({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  @override
  Future<bool> claimExists(String normalizedCode) async {
    final snapshot = await _firestore
        .collection('storeJoinCodes')
        .doc(normalizedCode)
        .get();
    return snapshot.exists;
  }
}

enum EmployeeJoinCodeStatus { valid, invalidCode }

class EmployeeJoinCodeResult {
  const EmployeeJoinCodeResult(this.status);

  final EmployeeJoinCodeStatus status;
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
    if (!await _lookup.claimExists(normalizedCode)) {
      return const EmployeeJoinCodeResult(EmployeeJoinCodeStatus.invalidCode);
    }

    return const EmployeeJoinCodeResult(EmployeeJoinCodeStatus.valid);
  }
}
