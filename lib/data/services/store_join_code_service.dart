import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

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
  Future<String> ensureJoinCode(String storeId, {String? modelUid}) =>
      _createOrRotate(
        storeId,
        rotate: false,
        diagnosticModelUid: modelUid,
      );

  /// Atomically claims a new code, updates the store, and releases the old code.
  Future<String> rotateJoinCode(String storeId) =>
      _createOrRotate(storeId, rotate: true);

  Future<String> _createOrRotate(
    String storeId, {
    required bool rotate,
    String? diagnosticModelUid,
  }) async {
    for (var attempt = 0; attempt < _maxAttempts; attempt++) {
      final newCode = JoinCode.generate();
      final newCodeId = JoinCode.normalize(newCode);

      if (diagnosticModelUid != null) {
        final authUid = FirebaseAuth.instance.currentUser?.uid;
        final storeRef = _stores.doc(storeId);
        final memberRef = authUid == null
            ? null
            : storeRef.collection('users').doc(authUid);
        debugPrint('[StoreJoinCodeDiagnostic] authUid=$authUid');
        debugPrint('[StoreJoinCodeDiagnostic] modelUid=$diagnosticModelUid');
        debugPrint('[StoreJoinCodeDiagnostic] storeId=$storeId');
        debugPrint('[StoreJoinCodeDiagnostic] storePath=${storeRef.path}');
        debugPrint('[StoreJoinCodeDiagnostic] generatedCode=$newCode');
        debugPrint('[StoreJoinCodeDiagnostic] normalizedClaimId=$newCodeId');

        Object? preflightError;
        StackTrace? preflightStackTrace;
        try {
          final storeSnapshot = await storeRef.get();
          final storeData = storeSnapshot.data();
          debugPrint(
            '[StoreJoinCodeDiagnostic] storeExists=${storeSnapshot.exists}',
          );
          debugPrint(
            '[StoreJoinCodeDiagnostic] ownerUid=${storeData?['ownerUid']}',
          );
        } catch (error, stackTrace) {
          preflightError = error;
          preflightStackTrace = stackTrace;
          debugPrint('[StoreJoinCodeDiagnostic] storeExists=<read-failed>');
          debugPrint('[StoreJoinCodeDiagnostic] ownerUid=<read-failed>');
        }

        if (memberRef == null) {
          debugPrint('[StoreJoinCodeDiagnostic] memberPath=<no-auth-uid>');
          debugPrint('[StoreJoinCodeDiagnostic] memberExists=<not-read>');
          debugPrint('[StoreJoinCodeDiagnostic] memberRole=<not-read>');
          debugPrint('[StoreJoinCodeDiagnostic] memberIsActive=<not-read>');
        } else {
          debugPrint(
            '[StoreJoinCodeDiagnostic] memberPath=${memberRef.path}',
          );
          try {
            final memberSnapshot = await memberRef.get();
            final memberData = memberSnapshot.data();
            debugPrint(
              '[StoreJoinCodeDiagnostic] memberExists=${memberSnapshot.exists}',
            );
            debugPrint(
              '[StoreJoinCodeDiagnostic] memberRole=${memberData?['role']}',
            );
            debugPrint(
              '[StoreJoinCodeDiagnostic] memberIsActive=${memberData?['isActive']}',
            );
          } catch (error, stackTrace) {
            preflightError ??= error;
            preflightStackTrace ??= stackTrace;
            debugPrint('[StoreJoinCodeDiagnostic] memberExists=<read-failed>');
            debugPrint('[StoreJoinCodeDiagnostic] memberRole=<read-failed>');
            debugPrint(
              '[StoreJoinCodeDiagnostic] memberIsActive=<read-failed>',
            );
          }
        }
        if (preflightError != null) {
          Error.throwWithStackTrace(preflightError, preflightStackTrace!);
        }
        debugPrint('[StoreJoinCodeDiagnostic] starting transaction');
      }

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
