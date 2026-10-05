import 'dart:developer' as developer;

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

  void _logListFailure({
    required String stage,
    required String storeId,
    String? employeeUid,
    required Object error,
    required StackTrace stackTrace,
  }) {
    final firebaseDetails = error is FirebaseException
        ? ' code=${error.code} message=${error.message} plugin=${error.plugin}'
        : '';
    developer.log(
      'EmployeeRepository.listEmployees stage=$stage '
      'storeId=$storeId'
      '${employeeUid == null ? '' : ' employeeUid=$employeeUid'} '
      'type=${error.runtimeType}$firebaseDetails',
      name: 'EmployeeRepository',
      error: error,
      stackTrace: stackTrace,
    );
  }

  Future<List<EmployeeSummary>> listEmployees(String storeId) async {
    late final QuerySnapshot<Map<String, dynamic>> memberships;
    try {
      memberships = await _storeUsers(
        storeId,
      ).where('role', isEqualTo: 'EMPLOYEE').get();
    } catch (error, stackTrace) {
      _logListFailure(
        stage: 'membership-query stores/$storeId/users',
        storeId: storeId,
        error: error,
        stackTrace: stackTrace,
      );
      rethrow;
    }

    return Future.wait(
      memberships.docs.map((membership) async {
        final membershipData = membership.data();
        final uid = membershipData['uid'] as String?;
        if (uid == null || uid.isEmpty) {
          final error = StateError('Employee membership has no UID.');
          _logListFailure(
            stage: 'membership-data stores/$storeId/users/${membership.id}',
            storeId: storeId,
            error: error,
            stackTrace: StackTrace.current,
          );
          throw error;
        }
        if (membershipData['role'] != 'EMPLOYEE') {
          final error = StateError('Employee membership has an invalid role.');
          _logListFailure(
            stage: 'membership-data stores/$storeId/users/$uid',
            storeId: storeId,
            employeeUid: uid,
            error: error,
            stackTrace: StackTrace.current,
          );
          throw error;
        }
        final isActive = membershipData['isActive'] as bool?;
        if (isActive == null) {
          final error = StateError('Employee membership has no active status.');
          _logListFailure(
            stage: 'membership-data stores/$storeId/users/$uid',
            storeId: storeId,
            employeeUid: uid,
            error: error,
            stackTrace: StackTrace.current,
          );
          throw error;
        }

        late final DocumentSnapshot<Map<String, dynamic>> profile;
        try {
          profile = await _users.doc(uid).get();
        } catch (error, stackTrace) {
          _logListFailure(
            stage: 'profile-read users/$uid',
            storeId: storeId,
            employeeUid: uid,
            error: error,
            stackTrace: stackTrace,
          );
          rethrow;
        }
        final profileData = profile.data();
        if (profileData == null) {
          final error = StateError('Employee profile not found for $uid.');
          _logListFailure(
            stage: 'profile-data users/$uid',
            storeId: storeId,
            employeeUid: uid,
            error: error,
            stackTrace: StackTrace.current,
          );
          throw error;
        }
        final name = profileData['displayName'] as String?;
        final email = profileData['email'] as String?;
        if (name == null || email == null) {
          final error = StateError(
            'Employee profile is missing name or email.',
          );
          _logListFailure(
            stage: 'profile-data users/$uid',
            storeId: storeId,
            employeeUid: uid,
            error: error,
            stackTrace: StackTrace.current,
          );
          throw error;
        }

        return EmployeeSummary(
          uid: uid,
          name: name,
          email: email,
          isActive: isActive,
        );
      }),
    );
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
