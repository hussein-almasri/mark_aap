import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../../core/utils/join_code.dart';

class SetupService {
  SetupService({FirebaseAuth? firebaseAuth, FirebaseFirestore? firestore})
    : _firebaseAuth = firebaseAuth ?? FirebaseAuth.instance,
      _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseAuth _firebaseAuth;
  final FirebaseFirestore _firestore;
  static const int _maxJoinCodeAttempts = 8;

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
      final joinCodeClaims = _firestore.collection('storeJoinCodes');

      for (var attempt = 0; attempt < _maxJoinCodeAttempts; attempt++) {
        final joinCode = JoinCode.generate();
        final claimRef = joinCodeClaims.doc(JoinCode.normalize(joinCode));
        if ((await claimRef.get()).exists) continue;

        final batch = _firestore.batch();
        batch.set(storeRef, {
          'name': storeName.trim(),
          'ownerUid': uid,
          'joinCode': joinCode,
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        });
        batch.set(claimRef, {
          'storeId': storeId,
          'createdAt': FieldValue.serverTimestamp(),
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

        try {
          await batch.commit();
          return storeId;
        } on FirebaseException catch (error) {
          if (error.code != 'permission-denied' &&
              error.code != 'already-exists') {
            rethrow;
          }
          final competingClaim = await claimRef.get();
          if (!competingClaim.exists ||
              competingClaim.data()?['storeId'] == storeId) {
            rethrow;
          }
        }
      }

      throw StateError('Could not allocate a unique store join code.');
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
