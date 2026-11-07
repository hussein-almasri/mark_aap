import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:firebase_core/firebase_core.dart';

import '../../data/models/user_model.dart';

class DataLoadDiagnostics {
  const DataLoadDiagnostics._();

  static Future<T> run<T>(
    String label,
    FutureOr<T> Function() action, {
    String Function(T value)? successDetails,
  }) async {
    try {
      final result = await action();
      if (kDebugMode) {
        final details = successDetails?.call(result);
        _log('$label: success${details == null ? '' : ' ($details)'}');
      }
      return result;
    } on FirebaseException catch (error) {
      if (kDebugMode) {
        _log(
          '$label: FirebaseException '
          'code=${error.code} message=${error.message}',
        );
      }
      rethrow;
    } catch (error) {
      if (kDebugMode) {
        _log('$label: failed errorType=${error.runtimeType}');
      }
      rethrow;
    }
  }

  static Future<void> inspectMemberships({
    required UserModel user,
    required String source,
    FirebaseFirestore? firestore,
  }) async {
    if (!kDebugMode || Firebase.apps.isEmpty) return;

    final db = firestore ?? FirebaseFirestore.instance;
    _log(
      '$source session uid=${user.uid} storeId=${user.storeId} '
      'role=${user.role}',
    );

    final index = await _readMembership(
      source: source,
      label: 'users/${user.uid}/memberships/${user.storeId}',
      reference: db
          .collection('users')
          .doc(user.uid)
          .collection('memberships')
          .doc(user.storeId),
    );
    final storeUser = await _readMembership(
      source: source,
      label: 'stores/${user.storeId}/users/${user.uid}',
      reference: db
          .collection('stores')
          .doc(user.storeId)
          .collection('users')
          .doc(user.uid),
    );

    final indexData = index?.data();
    final storeUserData = storeUser?.data();
    final indexStoreId = indexData?['storeId'];
    final indexRole = indexData?['role'];
    final indexActive = indexData?['isActive'];
    final storeUserUid = storeUserData?['uid'];
    final storeUserRole = storeUserData?['role'];
    final storeUserActive = storeUserData?['isActive'];

    _log(
      '$source membership checks '
      'indexExists=${index?.exists ?? false} '
      'storeUserExists=${storeUser?.exists ?? false} '
      'indexStoreIdMatches=${indexStoreId == user.storeId} '
      'indexRoleAllowed=${indexRole == 'ADMIN' || indexRole == 'EMPLOYEE'} '
      'rolesMatch=${indexRole == storeUserRole} '
      'storeUserRoleMatchesSession=${storeUserRole == user.role} '
      'indexActiveFieldValid=${indexActive is bool} '
      'indexActive=${indexActive == true} '
      'storeUserUidMatches=${storeUserUid == user.uid} '
      'storeUserActiveFieldValid=${storeUserActive is bool} '
      'storeUserActive=${storeUserActive == true}',
    );
  }

  static Future<DocumentSnapshot<Map<String, dynamic>>?> _readMembership({
    required String source,
    required String label,
    required DocumentReference<Map<String, dynamic>> reference,
  }) async {
    try {
      return await run<DocumentSnapshot<Map<String, dynamic>>>(
        '$source membership read $label',
        reference.get,
        successDetails: (snapshot) => 'exists=${snapshot.exists}',
      );
    } on FirebaseException {
      return null;
    } catch (_) {
      return null;
    }
  }

  static void _log(String message) {
    debugPrint('[DataLoadDiagnostic] $message');
  }
}
