import 'package:flutter_test/flutter_test.dart';
import 'package:mark_aap/data/services/employee_join_code_validator.dart';

class _FakeLookup implements EmployeeJoinCodeLookup {
  String? claimedStoreId;
  bool hasStore = true;
  String? requestedCode;
  String? requestedStoreId;

  @override
  Future<String?> findStoreIdForClaim(String normalizedCode) async {
    requestedCode = normalizedCode;
    return claimedStoreId;
  }

  @override
  Future<bool> storeExists(String storeId) async {
    requestedStoreId = storeId;
    return hasStore;
  }
}

void main() {
  group('EmployeeJoinCodeValidator', () {
    test('rejects an unknown claim', () async {
      final lookup = _FakeLookup();
      final result = await EmployeeJoinCodeValidator(
        lookup: lookup,
      ).validate('SMAE-S9H4-LQ78-XCCY');

      expect(result.status, EmployeeJoinCodeStatus.invalidCode);
      expect(lookup.requestedCode, 'smaes9h4lq78xccy');
      expect(lookup.requestedStoreId, isNull);
    });

    test('validates a claim and its referenced store', () async {
      final lookup = _FakeLookup()..claimedStoreId = 'store-123';
      final result = await EmployeeJoinCodeValidator(
        lookup: lookup,
      ).validate('SMAE-S9H4-LQ78-XCCY');

      expect(result.status, EmployeeJoinCodeStatus.valid);
      expect(result.storeId, 'store-123');
      expect(lookup.requestedCode, 'smaes9h4lq78xccy');
      expect(lookup.requestedStoreId, 'store-123');
    });

    test('rejects a claim whose referenced store is missing', () async {
      final lookup = _FakeLookup()
        ..claimedStoreId = 'store-123'
        ..hasStore = false;
      final result = await EmployeeJoinCodeValidator(
        lookup: lookup,
      ).validate('SMAE-S9H4-LQ78-XCCY');

      expect(result.status, EmployeeJoinCodeStatus.missingStore);
      expect(lookup.requestedStoreId, 'store-123');
    });

    test('does not read Firestore for malformed code', () async {
      final lookup = _FakeLookup();
      final result = await EmployeeJoinCodeValidator(
        lookup: lookup,
      ).validate('not-a-code');

      expect(result.status, EmployeeJoinCodeStatus.invalidCode);
      expect(lookup.requestedCode, isNull);
    });
  });
}
