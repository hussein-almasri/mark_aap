import 'package:flutter_test/flutter_test.dart';
import 'package:mark_aap/data/repositories/supplier_payment_repository.dart';

/// Each phase-2 precondition is exercised on its own, so a supplier-name
/// problem is never confused with a cancelled invoice or a balance conflict.
void main() {
  Map<String, dynamic> debt({
    String companyId = 'company-1',
    String companyName = 'Example Company',
    String status = 'OPEN',
    int remainingAmountFils = 40000,
  }) => {
    'invoiceId': 'inv-1',
    'companyId': companyId,
    'companyName': companyName,
    'originalAmountFils': 40000,
    'remainingAmountFils': remainingAmountFils,
    'status': status,
    'createdBy': 'admin-1',
    'operationId': 'inv-op-1',
    'lastOperationId': 'inv-op-1',
  };

  Map<String, dynamic> invoice({
    String companyId = 'company-1',
    String companyName = 'Example Company',
    String status = 'ACTIVE',
  }) => {
    'invoiceId': 'inv-1',
    'companyId': companyId,
    'companyName': companyName,
    'status': status,
    'supplierDebtAmountFils': 40000,
    'operationId': 'inv-op-1',
    'createdBy': 'admin-1',
  };

  SupplierPaymentConflictReason? classify({
    Map<String, dynamic>? debtData,
    Map<String, dynamic>? invoiceData,
    String companyId = 'company-1',
    String companyName = 'Example Company',
    int allocationAmountFils = 40000,
  }) => SupplierPaymentRepository.classifyAllocationConflict(
    companyId: companyId,
    companyName: companyName,
    debt: debtData ?? debt(),
    invoice: invoiceData ?? invoice(),
    allocationAmountFils: allocationAmountFils,
  );

  test('returns null while every precondition still holds', () {
    expect(classify(), isNull);
  });

  test('detects a renamed supplier and nothing else', () {
    expect(
      classify(companyName: 'Renamed Company'),
      SupplierPaymentConflictReason.companyNameMismatch,
    );
    // The invoice really is ACTIVE and the balance really covers the amount,
    // so neither of those may be reported.
    final reason = classify(companyName: 'Renamed Company');
    expect(reason, isNot(SupplierPaymentConflictReason.invoiceNotActive));
    expect(reason, isNot(SupplierPaymentConflictReason.allocationExceedsRemaining));
  });

  test('detects a cancelled invoice and nothing else', () {
    expect(
      classify(invoiceData: invoice(status: 'CANCELLED')),
      SupplierPaymentConflictReason.invoiceNotActive,
    );
    expect(
      classify(invoiceData: invoice(status: 'CANCELLED')),
      isNot(SupplierPaymentConflictReason.companyNameMismatch),
    );
  });

  test('detects an allocation that no longer fits the remaining balance', () {
    expect(
      classify(
        debtData: debt(remainingAmountFils: 10000),
        allocationAmountFils: 40000,
      ),
      SupplierPaymentConflictReason.allocationExceedsRemaining,
    );
  });

  test('detects a debt that is no longer open', () {
    expect(
      classify(debtData: debt(status: 'PAID', remainingAmountFils: 0)),
      SupplierPaymentConflictReason.debtNotOpen,
    );
  });

  test('detects a company id that no longer matches', () {
    expect(
      classify(companyId: 'company-2'),
      SupplierPaymentConflictReason.companyIdMismatch,
    );
    expect(
      classify(debtData: debt(companyId: 'company-2')),
      SupplierPaymentConflictReason.companyIdMismatch,
    );
  });

  test('reports the balance conflict before the name mismatch', () {
    // Both are broken; the rules reject on the first violated precondition and
    // the balance one is checked first.
    expect(
      classify(
        debtData: debt(remainingAmountFils: 10000),
        companyName: 'Renamed Company',
      ),
      SupplierPaymentConflictReason.allocationExceedsRemaining,
    );
  });

  test('treats a non-integer remaining balance as a balance conflict', () {
    expect(
      classify(
        debtData: debt(remainingAmountFils: 0)..['remainingAmountFils'] = '40000',
        allocationAmountFils: 40000,
      ),
      SupplierPaymentConflictReason.allocationExceedsRemaining,
    );
  });
}
