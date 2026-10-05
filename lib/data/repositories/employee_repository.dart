import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/employee_summary.dart';

class EmployeeRepository {
  EmployeeRepository({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> _storeUsers(String storeId) =>
      _firestore.collection('stores').doc(storeId).collection('users');

  CollectionReference<Map<String, dynamic>> get _users =>
      _firestore.collection('users');

  CollectionReference<Map<String, dynamic>> _userMemberships(String uid) =>
      _users.doc(uid).collection('memberships');

  Future<List<EmployeeSummary>> listEmployees(String storeId) async {
    final memberships = await _storeUsers(
      storeId,
    ).where('role', isEqualTo: 'EMPLOYEE').get();

    return Future.wait(memberships.docs.map((membership) async {
      final membershipData = membership.data();
      final uid = membershipData['uid'] as String?;
      if (uid == null || uid.isEmpty) {
        throw StateError('Employee membership has no UID.');
      }
      if (membershipData['role'] != 'EMPLOYEE') {
        throw StateError('Employee membership has an invalid role.');
      }
      final isActive = membershipData['isActive'] as bool?;
      if (isActive == null) {
        throw StateError('Employee membership has no active status.');
      }

      final profile = await _users.doc(uid).get();
      final profileData = profile.data();
      if (profileData == null) {
        throw StateError('Employee profile not found for $uid.');
      }
      final name = profileData['displayName'] as String?;
      final email = profileData['email'] as String?;
      if (name == null || email == null) {
        throw StateError('Employee profile is missing name or email.');
      }

      return EmployeeSummary(
        uid: uid,
        name: name,
        email: email,
        isActive: isActive,
      );
    }));
  }

  Future<void> setEmployeeActive(
    String storeId,
    String employeeUid,
    bool isActive,
  ) async {
    final batch = _firestore.batch();
    batch.update(_storeUsers(storeId).doc(employeeUid), {
      'isActive': isActive,
    });
    batch.update(_userMemberships(employeeUid).doc(storeId), {
      'isActive': isActive,
    });
    await batch.commit();
  }
}
