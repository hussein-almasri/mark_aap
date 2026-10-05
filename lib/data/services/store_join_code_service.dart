import 'package:cloud_firestore/cloud_firestore.dart';

import '../../core/utils/join_code.dart';

class StoreJoinCodeService {
  StoreJoinCodeService({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;
  static const int _maxAttempts = 8;

  CollectionReference<Map<String, dynamic>> get _stores =>
      _firestore.collection('stores');

  CollectionReference<Map<String, dynamic>> get _claims =>
      _firestore.collection('storeJoinCodes');

  /// Lazily assigns a code to an existing store when its admin opens this page.
  Future<String> ensureJoinCode(String storeId) =>
      _createOrRotate(storeId, rotate: false);

  /// Atomically claims a new code, updates the store, and releases the old code.
  Future<String> rotateJoinCode(String storeId) =>
      _createOrRotate(storeId, rotate: true);

  Future<String> _createOrRotate(String storeId, {required bool rotate}) async {
    for (var attempt = 0; attempt < _maxAttempts; attempt++) {
      final newCode = JoinCode.generate();
      final newCodeId = JoinCode.normalize(newCode);

      final result = await _firestore.runTransaction<String?>((
        transaction,
      ) async {
        final storeRef = _stores.doc(storeId);
        final storeSnapshot = await transaction.get(storeRef);
        if (!storeSnapshot.exists) {
          throw StateError('Store not found.');
        }

        final storeData = storeSnapshot.data()!;
        final currentCode = storeData['joinCode'] as String?;
        if (!rotate && currentCode != null && currentCode.isNotEmpty) {
          final currentCodeId = JoinCode.normalize(currentCode);
          final currentClaimRef = _claims.doc(currentCodeId);
          final currentClaim = await transaction.get(currentClaimRef);
          if (currentClaim.exists &&
              currentClaim.data()?['storeId'] == storeId) {
            return currentCode;
          }
        }

        final newClaimRef = _claims.doc(newCodeId);
        final newClaim = await transaction.get(newClaimRef);
        if (newClaim.exists) {
          return null;
        }

        DocumentReference<Map<String, dynamic>>? oldClaimRef;
        if (currentCode != null && currentCode.isNotEmpty) {
          try {
            oldClaimRef = _claims.doc(JoinCode.normalize(currentCode));
            final oldClaim = await transaction.get(oldClaimRef);
            if (!oldClaim.exists || oldClaim.data()?['storeId'] != storeId) {
              oldClaimRef = null;
            }
          } on FormatException {
            oldClaimRef = null;
          }
        }

        transaction.set(newClaimRef, {
          'storeId': storeId,
          'createdAt': FieldValue.serverTimestamp(),
        });
        transaction.update(storeRef, {
          'joinCode': newCode,
          'updatedAt': FieldValue.serverTimestamp(),
        });
        if (oldClaimRef != null) {
          transaction.delete(oldClaimRef);
        }
        return newCode;
      });

      if (result != null) {
        return result;
      }
    }

    throw StateError('Could not allocate a unique store join code.');
  }
}
