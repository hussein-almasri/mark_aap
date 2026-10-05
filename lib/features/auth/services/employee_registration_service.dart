import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../../../data/services/employee_join_code_validator.dart';

class EmployeeAuthAccount {
  const EmployeeAuthAccount({required this.uid, required this.delete});

  final String uid;
  final Future<void> Function() delete;
}

abstract interface class EmployeeRegistrationAuth {
  Future<EmployeeAuthAccount> createAccount({
    required String email,
    required String password,
  });
}

abstract interface class EmployeeRegistrationWriter {
  Future<void> createEmployee({
    required String uid,
    required String email,
    required String displayName,
    required String storeId,
    required String joinCodeId,
  });
}

class FirebaseEmployeeRegistrationAuth implements EmployeeRegistrationAuth {
  FirebaseEmployeeRegistrationAuth({FirebaseAuth? auth})
    : _auth = auth ?? FirebaseAuth.instance;

  final FirebaseAuth _auth;

  @override
  Future<EmployeeAuthAccount> createAccount({
    required String email,
    required String password,
  }) async {
    final credential = await _auth.createUserWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );
    final user = credential.user;
    if (user == null) throw StateError('Firebase Auth returned no user.');
    return EmployeeAuthAccount(uid: user.uid, delete: user.delete);
  }
}

class FirestoreEmployeeRegistrationWriter
    implements EmployeeRegistrationWriter {
  FirestoreEmployeeRegistrationWriter({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  @override
  Future<void> createEmployee({
    required String uid,
    required String email,
    required String displayName,
    required String storeId,
    required String joinCodeId,
  }) async {
    final userRef = _firestore.collection('users').doc(uid);
    final indexRef = userRef.collection('memberships').doc(storeId);
    final storeMemberRef = _firestore
        .collection('stores')
        .doc(storeId)
        .collection('users')
        .doc(uid);
    final batch = _firestore.batch();

    batch.set(userRef, {
      'uid': uid,
      'email': email.trim(),
      'displayName': displayName.trim(),
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    batch.set(indexRef, {
      'storeId': storeId,
      'role': 'EMPLOYEE',
      'isActive': true,
      'joinCodeId': joinCodeId,
    });
    batch.set(storeMemberRef, {
      'uid': uid,
      'role': 'EMPLOYEE',
      'isActive': true,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    await batch.commit();
  }
}

class EmployeeRegistrationException implements Exception {
  const EmployeeRegistrationException({required this.cause, this.cleanupError});

  final Object cause;
  final Object? cleanupError;
}

class InvalidEmployeeJoinCodeException implements Exception {
  const InvalidEmployeeJoinCodeException();
}

class EmployeeRegistrationService {
  EmployeeRegistrationService({
    required EmployeeJoinCodeValidator joinCodeValidator,
    required EmployeeRegistrationAuth auth,
    required EmployeeRegistrationWriter writer,
  }) : _joinCodeValidator = joinCodeValidator,
       _auth = auth,
       _writer = writer;

  final EmployeeJoinCodeValidator _joinCodeValidator;
  final EmployeeRegistrationAuth _auth;
  final EmployeeRegistrationWriter _writer;

  Future<void> register({
    required String displayName,
    required String email,
    required String password,
    required String joinCode,
  }) async {
    final validation = await _joinCodeValidator.validate(joinCode);
    if (validation.status != EmployeeJoinCodeStatus.valid ||
        validation.storeId == null ||
        validation.joinCodeId == null) {
      throw const InvalidEmployeeJoinCodeException();
    }

    final account = await _auth.createAccount(
      email: email.trim(),
      password: password,
    );
    try {
      await _writer.createEmployee(
        uid: account.uid,
        email: email.trim(),
        displayName: displayName.trim(),
        storeId: validation.storeId!,
        joinCodeId: validation.joinCodeId!,
      );
    } catch (error) {
      Object? cleanupError;
      try {
        await account.delete();
      } catch (cleanup) {
        cleanupError = cleanup;
      }
      throw EmployeeRegistrationException(
        cause: error,
        cleanupError: cleanupError,
      );
    }
  }
}

String employeeAuthErrorMessage(FirebaseAuthException error) {
  switch (error.code) {
    case 'email-already-in-use':
      return 'هذا البريد الإلكتروني مسجل بالفعل.';
    case 'invalid-email':
      return 'يرجى إدخال بريد إلكتروني صحيح.';
    case 'weak-password':
      return 'كلمة المرور ضعيفة. استخدم كلمة مرور أقوى.';
    case 'network-request-failed':
      return 'تعذر الاتصال بالشبكة. تحقق من الاتصال وحاول مجددًا.';
    case 'invalid-credential':
      return 'تعذر إنشاء الحساب بهذه البيانات.';
    default:
      return 'تعذر إنشاء الحساب. حاول مرة أخرى.';
  }
}
