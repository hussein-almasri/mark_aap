import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mark_aap/data/services/employee_join_code_validator.dart';
import 'package:mark_aap/features/auth/services/employee_registration_service.dart';

class _Lookup implements EmployeeJoinCodeLookup {
  _Lookup(this.storeId);
  final String? storeId;

  @override
  Future<String?> claimStoreId(String normalizedCode) async => storeId;
}

class _Auth implements EmployeeRegistrationAuth {
  int createCount = 0;
  int deleteCount = 0;
  Object? createError;
  Object? deleteError;

  @override
  Future<EmployeeAuthAccount> createAccount({
    required String email,
    required String password,
  }) async {
    createCount++;
    if (createError case final error?) throw error;
    return EmployeeAuthAccount(
      uid: 'new-employee',
      delete: () async {
        deleteCount++;
        if (deleteError case final error?) throw error;
      },
    );
  }
}

class _Writer implements EmployeeRegistrationWriter {
  Object? error;
  final writes = <Map<String, String>>[];

  @override
  Future<void> createEmployee({
    required String uid,
    required String email,
    required String displayName,
    required String storeId,
    required String joinCodeId,
  }) async {
    writes.add({
      'uid': uid,
      'email': email,
      'displayName': displayName,
      'storeId': storeId,
      'joinCodeId': joinCodeId,
    });
    if (error case final failure?) throw failure;
  }
}

EmployeeRegistrationService _service({
  required String? storeId,
  required _Auth auth,
  required _Writer writer,
}) => EmployeeRegistrationService(
  joinCodeValidator: EmployeeJoinCodeValidator(lookup: _Lookup(storeId)),
  auth: auth,
  writer: writer,
);

void main() {
  const code = 'SMAE-S9H4-LQ78-XCCY';

  test(
    'valid Join Code resolves the store and creates employee registration',
    () async {
      final auth = _Auth();
      final writer = _Writer();
      await _service(
        storeId: 'store-from-claim',
        auth: auth,
        writer: writer,
      ).register(
        displayName: ' Employee Name ',
        email: ' employee@example.com ',
        password: 'secret1',
        joinCode: code,
      );

      expect(auth.createCount, 1);
      expect(writer.writes.single, {
        'uid': 'new-employee',
        'email': 'employee@example.com',
        'displayName': 'Employee Name',
        'storeId': 'store-from-claim',
        'joinCodeId': 'smaes9h4lq78xccy',
      });
    },
  );

  test('invalid Join Code is rejected before Auth creation', () async {
    final auth = _Auth();
    final writer = _Writer();
    await expectLater(
      _service(storeId: null, auth: auth, writer: writer).register(
        displayName: 'Employee',
        email: 'employee@example.com',
        password: 'secret1',
        joinCode: code,
      ),
      throwsA(isA<InvalidEmployeeJoinCodeException>()),
    );
    expect(auth.createCount, 0);
  });

  test('duplicate email Auth errors are preserved for UI mapping', () async {
    final auth = _Auth()
      ..createError = FirebaseAuthException(code: 'email-already-in-use');
    final error = await _registerExpectingError(auth, _Writer());
    expect(error, isA<FirebaseAuthException>());
    expect(
      employeeAuthErrorMessage(error as FirebaseAuthException),
      contains('مسجل'),
    );
  });

  test('common Firebase Auth errors map to user-safe messages', () {
    expect(
      employeeAuthErrorMessage(FirebaseAuthException(code: 'invalid-email')),
      contains('بريد إلكتروني'),
    );
    expect(
      employeeAuthErrorMessage(FirebaseAuthException(code: 'weak-password')),
      contains('ضعيفة'),
    );
    expect(
      employeeAuthErrorMessage(
        FirebaseAuthException(code: 'network-request-failed'),
      ),
      contains('الشبكة'),
    );
    expect(
      employeeAuthErrorMessage(
        FirebaseAuthException(code: 'invalid-credential'),
      ),
      contains('البيانات'),
    );
  });

  test(
    'Firestore failure attempts Auth cleanup and preserves the cause',
    () async {
      final auth = _Auth();
      final writer = _Writer()..error = StateError('write failed');
      await expectLater(
        _service(storeId: 'store-1', auth: auth, writer: writer).register(
          displayName: 'Employee',
          email: 'employee@example.com',
          password: 'secret1',
          joinCode: code,
        ),
        throwsA(
          isA<EmployeeRegistrationException>().having(
            (error) => error.cause,
            'cause',
            isA<StateError>(),
          ),
        ),
      );
      expect(auth.deleteCount, 1);
    },
  );

  test(
    'cleanup failure is retained alongside the original write failure',
    () async {
      final auth = _Auth()..deleteError = StateError('delete failed');
      final writer = _Writer()..error = StateError('write failed');
      await expectLater(
        _service(storeId: 'store-1', auth: auth, writer: writer).register(
          displayName: 'Employee',
          email: 'employee@example.com',
          password: 'secret1',
          joinCode: code,
        ),
        throwsA(
          isA<EmployeeRegistrationException>().having(
            (error) => error.cleanupError,
            'cleanupError',
            isA<StateError>(),
          ),
        ),
      );
    },
  );
}

Future<Object> _registerExpectingError(_Auth auth, _Writer writer) async {
  try {
    await _service(storeId: 'store-1', auth: auth, writer: writer).register(
      displayName: 'Employee',
      email: 'employee@example.com',
      password: 'secret1',
      joinCode: 'SMAE-S9H4-LQ78-XCCY',
    );
  } catch (error) {
    return error;
  }
  throw StateError('Expected registration to fail.');
}
