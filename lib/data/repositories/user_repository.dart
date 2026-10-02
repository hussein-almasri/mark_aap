import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/user_model.dart';

class UserRepository {
  UserRepository({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  Future<void> createUserProfile({
    required String storeId,
    required String uid,
    required String name,
    required String email,
    required String role,
  }) async {
    await _firestore
        .collection('stores')
        .doc(storeId)
        .collection('users')
        .doc(uid)
        .set({
      'storeId': storeId,
      'name': name.trim(),
      'email': email.trim(),
      'role': role,
      'isActive': true,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<UserModel?> getUserProfile({
    required String storeId,
    required String uid,
  }) async {
    final document = await _firestore
        .collection('stores')
        .doc(storeId)
        .collection('users')
        .doc(uid)
        .get();

    if (!document.exists) {
      return null;
    }

    final data = document.data();

    if (data == null) {
      return null;
    }

    return UserModel(
      uid: uid,
      storeId: data['storeId'] as String? ?? storeId,
      name: data['name'] as String? ?? '',
      email: data['email'] as String? ?? '',
      role: data['role'] as String? ?? '',
      isActive: data['isActive'] as bool? ?? false,
    );
  }

  Future<String?> getStoreIdForUser({
    required String uid,
  }) async {
    final storesSnapshot = await _firestore.collection('stores').get();

    for (final storeDocument in storesSnapshot.docs) {
      final userDocument = await storeDocument.reference
          .collection('users')
          .doc(uid)
          .get();

      if (userDocument.exists) {
        final data = userDocument.data();

        return data?['storeId'] as String?;
      }
    }

    return null;
  }
}