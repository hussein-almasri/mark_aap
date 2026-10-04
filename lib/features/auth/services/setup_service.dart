import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_functions/cloud_functions.dart';

class SetupService {
  SetupService({
    FirebaseAuth? firebaseAuth,
    FirebaseFunctions? functions,
  }) : _firebaseAuth = firebaseAuth ?? FirebaseAuth.instance,
       _functions =
           functions ?? FirebaseFunctions.instanceFor(region: 'me-central2');

  final FirebaseAuth _firebaseAuth;
  final FirebaseFunctions _functions;

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

    try {
      final result = await _functions.httpsCallable('setupStore').call({
        'storeName': storeName.trim(),
        'ownerName': ownerName.trim(),
      });
      final data = result.data;
      if (data is! Map || data['storeId'] is! String) {
        throw StateError('Store setup returned an invalid response.');
      }
      return data['storeId'] as String;
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
