import 'package:flutter_test/flutter_test.dart';
import 'package:mark_aap/data/services/employee_join_code_validator.dart';

class _FakeLookup implements EmployeeJoinCodeLookup {
  String? storeId;
  int lookupCount = 0;
  final requestedCodes = <String>[];

  @override
  Future<String?> claimStoreId(String normalizedCode) async {
    lookupCount++;
    requestedCodes.add(normalizedCode);
    return storeId;
  }
}

void main() {
  group('EmployeeJoinCodeValidator', () {
    test('invalid format is rejected without a Firestore lookup', () async {
      final lookup = _FakeLookup();
      final result = await EmployeeJoinCodeValidator(
        lookup: lookup,
      ).validate('not-a-code');

      expect(result.status, EmployeeJoinCodeStatus.invalidCode);
      expect(lookup.lookupCount, 0);
      expect(lookup.requestedCodes, isEmpty);
    });

    test(
      'valid-format code with no claim is invalid after one lookup',
      () async {
        final lookup = _FakeLookup();
        final result = await EmployeeJoinCodeValidator(
          lookup: lookup,
        ).validate('SMAE-S9H4-LQ78-XCCY');

        expect(result.status, EmployeeJoinCodeStatus.invalidCode);
        expect(lookup.lookupCount, 1);
        expect(lookup.requestedCodes, ['smaes9h4lq78xccy']);
      },
    );

    test('existing claim is valid after exactly one lookup', () async {
      final lookup = _FakeLookup()..storeId = 'store-123';
      final result = await EmployeeJoinCodeValidator(
        lookup: lookup,
      ).validate('SMAE-S9H4-LQ78-XCCY');

      expect(result.status, EmployeeJoinCodeStatus.valid);
      expect(lookup.lookupCount, 1);
      expect(lookup.requestedCodes, ['smaes9h4lq78xccy']);
      expect(result.storeId, 'store-123');
      expect(result.joinCodeId, 'smaes9h4lq78xccy');
    });

    test('claim storeId is not needed to validate an existing claim', () async {
      final lookup = _FakeLookup()..storeId = 'store-123';
      final result = await EmployeeJoinCodeValidator(
        lookup: lookup,
      ).validate('SMAE-S9H4-LQ78-XCCY');

      expect(result.status, EmployeeJoinCodeStatus.valid);
      expect(lookup.lookupCount, 1);
      expect(lookup.requestedCodes, ['smaes9h4lq78xccy']);
    });

    test(
      'claim stays valid even when its referenced store is absent',
      () async {
        final lookup = _FakeLookup()..storeId = 'missing-store';
        final result = await EmployeeJoinCodeValidator(
          lookup: lookup,
        ).validate('SMAE-S9H4-LQ78-XCCY');

        expect(result.status, EmployeeJoinCodeStatus.valid);
        expect(lookup.lookupCount, 1);
        expect(lookup.requestedCodes, ['smaes9h4lq78xccy']);
      },
    );
  });
}
