import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../data/repositories/store_repository.dart';
import '../../../data/repositories/user_repository.dart';

class SetupService {
  SetupService({
    FirebaseAuth? firebaseAuth,
    FirebaseFirestore? firestore,
    StoreRepository? storeRepository,
    UserRepository? userRepository,
  }) : _firebaseAuth = firebaseAuth ?? FirebaseAuth.instance,
       _firestore = firestore ?? FirebaseFirestore.instance,
       _storeRepository =
           storeRepository ??
           StoreRepository(firestore: firestore ?? FirebaseFirestore.instance),
       _userRepository =
           userRepository ??
           UserRepository(firestore: firestore ?? FirebaseFirestore.instance);

  final FirebaseAuth _firebaseAuth;
  final FirebaseFirestore _firestore;
  final StoreRepository _storeRepository;
  final UserRepository _userRepository;

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

    final storeDocument = _storeRepository.newStoreReference();
    final storeId = storeDocument.id;
    final batch = _firestore.batch();

    _storeRepository.addStoreToBatch(
      batch: batch,
      document: storeDocument,
      name: storeName.trim(),
      ownerUid: user.uid,
    );
    _userRepository.addUserAndMembershipsToBatch(
      batch: batch,
      storeId: storeId,
      uid: user.uid,
      displayName: ownerName.trim(),
      email: user.email ?? email.trim(),
      role: 'ADMIN',
    );

    try {
      await batch.commit();
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

    return storeId;
  }
}
