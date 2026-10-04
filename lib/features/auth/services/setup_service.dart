import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class SetupService {
  SetupService({
    FirebaseAuth? firebaseAuth,
    FirebaseFirestore? firestore,
  }) : _firebaseAuth = firebaseAuth ?? FirebaseAuth.instance,
       _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseAuth _firebaseAuth;
  final FirebaseFirestore _firestore;

  Future<String> setupStore({
    required String storeName,
    required String ownerName,
    required String email,
    required String password,
  }) async {
    final credential = await _firebaseAuth.createUserWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );

    final user = credential.user;

    if (user == null) {
      throw StateError('User account was not created.');
    }

    // Temporary Spark-compatible decision: use the Auth UID as storeId.
    // A future trusted Cloud Function may generate independent store IDs.
    final uid = user.uid;
    final storeId = uid;

    try {
      final storeRef = _firestore.collection('stores').doc(storeId);
      final storeUserRef = storeRef.collection('users').doc(uid);
      final userRef = _firestore.collection('users').doc(uid);
      final membershipRef = userRef.collection('memberships').doc(storeId);
      final batch = _firestore.batch();

      batch.set(storeRef, {
        'name': storeName.trim(),
        'ownerUid': uid,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      batch.set(storeUserRef, {
        'uid': uid,
        'role': 'ADMIN',
        'isActive': true,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      batch.set(userRef, {
        'uid': uid,
        'email': user.email ?? email.trim(),
        'displayName': ownerName.trim(),
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      batch.set(membershipRef, {
        'storeId': storeId,
        'role': 'ADMIN',
        'isActive': true,
      });

      await batch.commit();
      return storeId;
    } catch (error) {
      try {
        await user.delete();
      } catch (cleanupError) {
        throw StateError(
          'Store setup failed and the new authentication account could not '
          'be cleaned up: $cleanupError',
        );
      }
      rethrow;
    }
  }
}
