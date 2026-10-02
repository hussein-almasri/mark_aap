import 'package:firebase_auth/firebase_auth.dart';

import '../../../data/repositories/store_repository.dart';
import '../../../data/repositories/user_repository.dart';

class SetupService {
  SetupService({
    FirebaseAuth? firebaseAuth,
    StoreRepository? storeRepository,
    UserRepository? userRepository,
  })  : _firebaseAuth = firebaseAuth ?? FirebaseAuth.instance,
        _storeRepository = storeRepository ?? StoreRepository(),
        _userRepository = userRepository ?? UserRepository();

  final FirebaseAuth _firebaseAuth;
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

    final storeId = await _storeRepository.createStore(
      name: storeName,
      ownerName: ownerName,
    );

    await _userRepository.createUserProfile(
      storeId: storeId,
      uid: user.uid,
      name: ownerName,
      email: email,
      role: 'ADMIN',
    );

    return storeId;
  }
}