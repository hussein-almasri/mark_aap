import 'package:cloud_firestore/cloud_firestore.dart' show Timestamp;
import 'package:flutter_test/flutter_test.dart';
import 'package:mark_aap/data/models/supplier_debt_model.dart';
import 'package:mark_aap/data/repositories/supplier_payment_repository.dart';

SupplierDebtModel _debt({
  required String invoiceId,
  required int remainingAmountFils,
  SupplierDebtStatus status = SupplierDebtStatus.open,
  int createdAtMillis = 0,
}) => SupplierDebtModel(
  invoiceId: invoiceId,
  companyId: 'company-1',
  companyName: 'Example Company',
  originalAmountFils: 10000,
  remainingAmountFils: remainingAmountFils,
  status: status,
  createdAt: Timestamp.fromMillisecondsSinceEpoch(createdAtMillis),
  createdBy: 'admin-1',
  operationId: invoiceId,
  lastOperationId: invoiceId,
);

void main() {
  group('selectOpenWithBalance', () {
    test('keeps only OPEN debts with a positive remaining balance', () {
      final result = SupplierPaymentRepository.selectOpenWithBalance([
        _debt(invoiceId: 'open-positive', remainingAmountFils: 5000),
        _debt(
          invoiceId: 'paid-zero',
          remainingAmountFils: 0,
          status: SupplierDebtStatus.paid,
        ),
        _debt(
          invoiceId: 'cancelled',
          remainingAmountFils: 5000,
          status: SupplierDebtStatus.cancelled,
        ),
        _debt(invoiceId: 'another-open', remainingAmountFils: 1),
      ]);

      expect(
        result.map((debt) => debt.invoiceId),
        ['open-positive', 'another-open'],
      );
    });

    test('returns an empty list when nothing qualifies', () {
      final result = SupplierPaymentRepository.selectOpenWithBalance([
        _debt(
          invoiceId: 'paid-zero',
          remainingAmountFils: 0,
          status: SupplierDebtStatus.paid,
        ),
        _debt(
          invoiceId: 'cancelled',
          remainingAmountFils: 5000,
          status: SupplierDebtStatus.cancelled,
        ),
      ]);
      expect(result, isEmpty);
    });

    test('returns an empty list for an empty input', () {
      expect(SupplierPaymentRepository.selectOpenWithBalance([]), isEmpty);
    });

    test('sorts qualifying debts by createdAt ascending', () {
      final result = SupplierPaymentRepository.selectOpenWithBalance([
        _debt(invoiceId: 'newest', remainingAmountFils: 1000, createdAtMillis: 300),
        _debt(invoiceId: 'oldest', remainingAmountFils: 1000, createdAtMillis: 100),
        _debt(invoiceId: 'middle', remainingAmountFils: 1000, createdAtMillis: 200),
        // Excluded so it never disturbs the ordering assertions.
        _debt(
          invoiceId: 'excluded',
          remainingAmountFils: 0,
          status: SupplierDebtStatus.paid,
          createdAtMillis: 0,
        ),
      ]);

      expect(
        result.map((debt) => debt.invoiceId),
        ['oldest', 'middle', 'newest'],
      );
    });

    test('does not mutate the balances of the debts it reads', () {
      final debts = [
        _debt(invoiceId: 'keep', remainingAmountFils: 4200),
        _debt(
          invoiceId: 'drop',
          remainingAmountFils: 0,
          status: SupplierDebtStatus.paid,
        ),
      ];
      SupplierPaymentRepository.selectOpenWithBalance(debts);

      expect(debts, hasLength(2));
      expect(debts[0].remainingAmountFils, 4200);
      expect(debts[1].remainingAmountFils, 0);
    });
  });
}
