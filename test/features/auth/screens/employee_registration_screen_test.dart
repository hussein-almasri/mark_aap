import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mark_aap/data/services/employee_join_code_validator.dart';
import 'package:mark_aap/features/auth/screens/employee_registration_screen.dart';
import 'package:mark_aap/features/auth/services/employee_registration_service.dart';

class _Lookup implements EmployeeJoinCodeLookup {
  @override
  Future<String?> claimStoreId(String normalizedCode) async => 'store-1';
}

class _Auth implements EmployeeRegistrationAuth {
  @override
  Future<EmployeeAuthAccount> createAccount({
    required String email,
    required String password,
  }) async => EmployeeAuthAccount(uid: 'unused', delete: () async {});
}

class _Writer implements EmployeeRegistrationWriter {
  @override
  Future<void> createEmployee({
    required String uid,
    required String email,
    required String displayName,
    required String storeId,
    required String joinCodeId,
  }) async {}
}

class _BlockingRegistration extends EmployeeRegistrationService {
  _BlockingRegistration()
    : super(
        joinCodeValidator: EmployeeJoinCodeValidator(lookup: _Lookup()),
        auth: _Auth(),
        writer: _Writer(),
      );

  final completer = Completer<void>();
  int calls = 0;

  @override
  Future<void> register({
    required String displayName,
    required String email,
    required String password,
    required String joinCode,
  }) {
    calls++;
    return completer.future;
  }
}

void main() {
  testWidgets('disables a second registration submission while loading', (
    tester,
  ) async {
    final registration = _BlockingRegistration();
    await tester.pumpWidget(
      MaterialApp(
        home: EmployeeRegistrationScreen(registrationService: registration),
      ),
    );

    final fields = find.byType(TextFormField);
    await tester.enterText(fields.at(0), 'Example Employee');
    await tester.enterText(fields.at(1), 'employee@example.com');
    await tester.enterText(fields.at(2), 'password123');
    await tester.enterText(fields.at(3), 'password123');
    await tester.enterText(fields.at(4), 'SMAE-S9H4-LQ78-XCCY');
    final button = find.byType(FilledButton);
    await tester.ensureVisible(button);
    await tester.tap(button);
    await tester.pump();
    expect(registration.calls, 1);
    expect(tester.widget<FilledButton>(button).onPressed, isNull);
    expect(registration.calls, 1);

    registration.completer.complete();
    await tester.pumpAndSettle();
  });
}
