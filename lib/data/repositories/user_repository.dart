import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/user_model.dart';

class MultipleStoreMembershipsException implements Exception {
  const MultipleStoreMembershipsException();
}

class UserRepository {
  UserRepository({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> get _users =>
      _firestore.collection('users');

  CollectionReference<Map<String, dynamic>> _userMemberships(String uid) =>
      _users.doc(uid).collection('memberships');

  CollectionReference<Map<String, dynamic>> _storeUsers(String storeId) =>
      _firestore.collection('stores').doc(storeId).collection('users');

  void addUserAndMembershipsToBatch({
    required WriteBatch batch,
    required String storeId,
    required String uid,
    required String displayName,
    required String email,
    required String role,
  }) {
    final storeMembership = _storeUsers(storeId).doc(uid);
    batch.set(storeMembership, {
      'uid': uid,
      'role': role,
      'isActive': true,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });

    batch.set(_users.doc(uid), {
      'uid': uid,
      'email': email.trim(),
      'displayName': displayName.trim(),
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });

    batch.set(_userMemberships(uid).doc(storeId), {
      'storeId': storeId,
      'role': role,
      'isActive': true,
    });
  }

  Future<UserModel?> getCurrentUserSession({required String uid}) async {
    final userDocument = await _users.doc(uid).get();
    if (!userDocument.exists) {
      return null;
    }

    final userData = userDocument.data();
    if (userData == null) {
      return null;
    }

    final memberships = await _userMemberships(uid).get();
    if (memberships.docs.isEmpty) {
      return null;
    }
    if (memberships.docs.length > 1) {
      throw const MultipleStoreMembershipsException();
    }

    final membershipIndex = memberships.docs.single;
    final indexData = membershipIndex.data();
    final storeId = indexData['storeId'] as String? ?? membershipIndex.id;
    return getUserProfile(storeId: storeId, uid: uid, accountData: userData);
  }

  Future<UserModel?> getUserProfile({
    required String storeId,
    required String uid,
    Map<String, dynamic>? accountData,
  }) async {
    final resolvedAccountData =
        accountData ?? (await _users.doc(uid).get()).data();
    if (resolvedAccountData == null) {
      return null;
    }

    final membershipDocument = await _storeUsers(storeId).doc(uid).get();
    if (!membershipDocument.exists) {
      return null;
    }

    final membershipData = membershipDocument.data();
    if (membershipData == null) {
      return null;
    }

    final role = membershipData['role'] as String? ?? '';
    if (role != 'ADMIN' && role != 'EMPLOYEE') {
      return null;
    }

    return UserModel(
      uid: uid,
      storeId: storeId,
      name: resolvedAccountData['displayName'] as String? ?? '',
      email: resolvedAccountData['email'] as String? ?? '',
      role: role,
      isActive: membershipData['isActive'] as bool? ?? false,
    );
  }
}
