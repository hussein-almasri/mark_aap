import 'package:cloud_firestore/cloud_firestore.dart';

import '../../core/utils/join_code.dart';

abstract interface class EmployeeJoinCodeLookup {
  Future<String?> claimStoreId(String normalizedCode);
}

class FirestoreEmployeeJoinCodeLookup implements EmployeeJoinCodeLookup {
  FirestoreEmployeeJoinCodeLookup({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  @override
  Future<String?> claimStoreId(String normalizedCode) async {
    final snapshot = await _firestore
        .collection('storeJoinCodes')
        .doc(normalizedCode)
        .get();
    return snapshot.data()?['storeId'] as String?;
  }
}

enum EmployeeJoinCodeStatus { valid, invalidCode }

class EmployeeJoinCodeResult {
  const EmployeeJoinCodeResult(this.status, {this.storeId, this.joinCodeId});

  final EmployeeJoinCodeStatus status;
  final String? storeId;
  final String? joinCodeId;
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
    final storeId = await _lookup.claimStoreId(normalizedCode);
    if (storeId == null || storeId.isEmpty) {
      return const EmployeeJoinCodeResult(EmployeeJoinCodeStatus.invalidCode);
    }

    return EmployeeJoinCodeResult(
      EmployeeJoinCodeStatus.valid,
      storeId: storeId,
      joinCodeId: normalizedCode,
    );
  }
}
