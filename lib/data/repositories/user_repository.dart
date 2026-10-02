import 'package:cloud_firestore/cloud_firestore.dart';

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

  Future<DocumentSnapshot<Map<String, dynamic>>> getUserProfile({
    required String storeId,
    required String uid,
  }) async {
    return _firestore
        .collection('stores')
        .doc(storeId)
        .collection('users')
        .doc(uid)
        .get();
  }
}