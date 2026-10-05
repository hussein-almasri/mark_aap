import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mark_aap/data/models/company_model.dart';

void main() {
  test('parses company fields and document ID', () {
    final createdAt = Timestamp.fromDate(DateTime.utc(2025));
    final updatedAt = Timestamp.fromDate(DateTime.utc(2026));
    final model = CompanyModel.fromData(
      companyId: 'company-1',
      data: {
        'name': 'Example Supplier',
        'phone': '+1 555 0100',
        'isActive': true,
        'createdAt': createdAt,
        'updatedAt': updatedAt,
      },
    );

    expect(model.companyId, 'company-1');
    expect(model.name, 'Example Supplier');
    expect(model.phone, '+1 555 0100');
    expect(model.isActive, isTrue);
    expect(model.createdAt, createdAt);
    expect(model.updatedAt, updatedAt);
  });

  test('parses company without optional phone or timestamps', () {
    final model = CompanyModel.fromData(
      companyId: 'company-2',
      data: {'name': 'No Phone', 'isActive': false},
    );

    expect(model.phone, isNull);
    expect(model.isActive, isFalse);
    expect(model.createdAt, isNull);
    expect(model.updatedAt, isNull);
  });

  test('rejects malformed company data', () {
    expect(
      () => CompanyModel.fromData(
        companyId: 'company-3',
        data: {'name': 'Invalid', 'isActive': 'yes'},
      ),
      throwsStateError,
    );
    expect(
      () => CompanyModel.fromData(
        companyId: 'company-4',
        data: {'name': 'Invalid phone', 'phone': 12, 'isActive': true},
      ),
      throwsStateError,
    );
  });
}
