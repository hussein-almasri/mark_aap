import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/user_model.dart';

class UserRepository {
  UserRepository({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> get _users =>
      _firestore.collection('users');

  CollectionReference<Map<String, dynamic>> _storeUsers(
    String storeId,
  ) {
    return _firestore
        .collection('stores')
        .doc(storeId)
        .collection('users');
  }

  void addUserProfilesToBatch({
    required WriteBatch batch,
    required String storeId,
    required String uid,
    required String name,
    required String email,
    required String role,
  }) {
    final userData = {
      'storeId': storeId,
      'name': name.trim(),
      'email': email.trim(),
      'role': role,
      'isActive': true,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    };

    batch.set(_storeUsers(storeId).doc(uid), userData);
    batch.set(_users.doc(uid), userData);
  }

  Future<UserModel?> getUserByUid({
    required String uid,
  }) async {
    final document = await _users.doc(uid).get();

    return _userModelFromDocument(document, uid: uid);
  }

  Stream<UserModel?> watchUserByUid({
    required String uid,
  }) {
    return _users
        .doc(uid)
        .snapshots()
        .map((document) => _userModelFromDocument(document, uid: uid));
  }

  UserModel? _userModelFromDocument(
    DocumentSnapshot<Map<String, dynamic>> document, {
    required String uid,
  }) {

    if (!document.exists) {
      return null;
    }

    final data = document.data();

    if (data == null) {
      return null;
    }

    return UserModel(
      uid: uid,
      storeId: data['storeId'] as String? ?? '',
      name: data['name'] as String? ?? '',
      email: data['email'] as String? ?? '',
      role: data['role'] as String? ?? '',
      isActive: data['isActive'] as bool? ?? false,
    );
  }

  Future<UserModel?> getUserProfile({
    required String storeId,
    required String uid,
  }) async {
    final document = await _storeUsers(storeId).doc(uid).get();

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
  
  Future<UserModel?> migrateLegacyUser({
    required String uid,
  }) async {
    final storesSnapshot = await _firestore.collection('stores').get();

    for (final storeDocument in storesSnapshot.docs) {
      final userDocument = await storeDocument.reference
          .collection('users')
          .doc(uid)
          .get();

      if (!userDocument.exists) {
        continue;
      }

      final data = userDocument.data();

      if (data == null) {
        return null;
      }

      final userModel = UserModel(
        uid: uid,
        storeId: data['storeId'] as String? ?? storeDocument.id,
        name: data['name'] as String? ?? '',
        email: data['email'] as String? ?? '',
        role: data['role'] as String? ?? '',
        isActive: data['isActive'] as bool? ?? false,
      );

      await _users.doc(uid).set({
        'storeId': userModel.storeId,
        'name': userModel.name,
        'email': userModel.email,
        'role': userModel.role,
        'isActive': userModel.isActive,
        'createdAt': data['createdAt'] ?? FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      return userModel;
    }

    return null;
  }
}
