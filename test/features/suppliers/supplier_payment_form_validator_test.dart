import 'package:flutter_test/flutter_test.dart';
import 'package:mark_aap/features/suppliers/supplier_payment_form_validator.dart';

void main() {
  group('tryParseJodField', () {
    test('treats a blank field as zero fils', () {
      expect(SupplierPaymentFormValidator.tryParseJodField(''), 0);
      expect(SupplierPaymentFormValidator.tryParseJodField('   '), 0);
    });

    test('parses whole and two-decimal JOD amounts to integer fils', () {
      expect(SupplierPaymentFormValidator.tryParseJodField('1'), 1000);
      expect(SupplierPaymentFormValidator.tryParseJodField('125.50'), 125500);
      expect(SupplierPaymentFormValidator.tryParseJodField('0.01'), 10);
      expect(SupplierPaymentFormValidator.tryParseJodField('0.1'), 100);
    });

    test('rejects more than two decimal places', () {
      expect(SupplierPaymentFormValidator.tryParseJodField('1.234'), isNull);
      expect(SupplierPaymentFormValidator.tryParseJodField('1.2345'), isNull);
    });

    test('rejects non-numeric and negative input', () {
      expect(SupplierPaymentFormValidator.tryParseJodField('abc'), isNull);
      expect(SupplierPaymentFormValidator.tryParseJodField('-5'), isNull);
      expect(SupplierPaymentFormValidator.tryParseJodField('1.2.3'), isNull);
    });
  });

  group('validateAmountField', () {
    test('requires a value', () {
      expect(
        SupplierPaymentFormValidator.validateAmountField(''),
        'مبلغ الدفعة مطلوب.',
      );
      expect(
        SupplierPaymentFormValidator.validateAmountField(null),
        'مبلغ الدفعة مطلوب.',
      );
    });

    test('rejects invalid amounts', () {
      expect(SupplierPaymentFormValidator.validateAmountField('abc'), isNotNull);
      expect(
        SupplierPaymentFormValidator.validateAmountField('1.234'),
        isNotNull,
      );
    });

    test('accepts a valid amount', () {
      expect(SupplierPaymentFormValidator.validateAmountField('125.50'), isNull);
      expect(SupplierPaymentFormValidator.validateAmountField('7'), isNull);
    });
  });

  group('validateAllocationField', () {
    test('treats blank as valid (not allocated)', () {
      expect(
        SupplierPaymentFormValidator.validateAllocationField(
          '',
          maxFils: 50000,
          label: 'فاتورة inv-1',
        ),
        isNull,
      );
      expect(
        SupplierPaymentFormValidator.validateAllocationField(
          null,
          maxFils: 50000,
          label: 'فاتورة inv-1',
        ),
        isNull,
      );
    });

    test('accepts an amount within the remaining balance', () {
      expect(
        SupplierPaymentFormValidator.validateAllocationField(
          '40.00',
          maxFils: 40000,
          label: 'فاتورة inv-1',
        ),
        isNull,
      );
    });

    test('rejects an amount greater than the remaining balance', () {
      final error = SupplierPaymentFormValidator.validateAllocationField(
        '40.01',
        maxFils: 40000,
        label: 'فاتورة inv-1',
      );
      expect(error, isNotNull);
      expect(error, contains('فاتورة inv-1'));
    });

    test('rejects invalid amounts but keeps the label in the message', () {
      final error = SupplierPaymentFormValidator.validateAllocationField(
        '1.234',
        maxFils: 40000,
        label: 'فاتورة inv-1',
      );
      expect(error, contains('فاتورة inv-1'));
    });
  });

  group('validatePayment (cross-field)', () {
    test('accepts a single-invoice allocation that sums exactly to the amount', () {
      expect(
        SupplierPaymentFormValidator.validatePayment(
          amountFils: 40000,
          allocationFils: [40000],
          remainingFils: [40000],
        ),
        isNull,
      );
    });

    test('accepts a multi-invoice allocation that sums exactly to the amount', () {
      expect(
        SupplierPaymentFormValidator.validatePayment(
          amountFils: 65000,
          allocationFils: [40000, 25000],
          remainingFils: [40000, 25000],
        ),
        isNull,
      );
    });

    test('accepts a five-invoice allocation (the model maximum)', () {
      expect(
        SupplierPaymentFormValidator.validatePayment(
          amountFils: 150000,
          allocationFils: [10000, 20000, 30000, 40000, 50000],
          remainingFils: [10000, 20000, 30000, 40000, 50000],
        ),
        isNull,
      );
    });

    test('rejects a non-positive amount', () {
      expect(
        SupplierPaymentFormValidator.validatePayment(
          amountFils: 0,
          allocationFils: [0],
          remainingFils: [10000],
        ),
        isNotNull,
      );
      expect(
        SupplierPaymentFormValidator.validatePayment(
          amountFils: -1000,
          allocationFils: [0],
          remainingFils: [10000],
        ),
        isNotNull,
      );
    });

    test('rejects a sum that does not equal the amount', () {
      final error = SupplierPaymentFormValidator.validatePayment(
        amountFils: 65000,
        allocationFils: [40000, 20000], // sums to 60000, not 65000
        remainingFils: [40000, 25000],
      );
      expect(error, isNotNull);
      expect(error, contains('لا يساوي'));
    });

    test('rejects an over-summing allocation', () {
      expect(
        SupplierPaymentFormValidator.validatePayment(
          amountFils: 65000,
          allocationFils: [40000, 30000], // sums to 70000
          remainingFils: [40000, 30000],
        ),
        isNotNull,
      );
    });

    test('rejects an allocation greater than its remaining balance', () {
      final error = SupplierPaymentFormValidator.validatePayment(
        amountFils: 45000,
        allocationFils: [45000],
        remainingFils: [40000],
      );
      expect(error, isNotNull);
      expect(error, contains('يتجاوز الرصيد'));
    });

    test('rejects an allocation when none is provided', () {
      expect(
        SupplierPaymentFormValidator.validatePayment(
          amountFils: 40000,
          allocationFils: [0, 0],
          remainingFils: [40000, 25000],
        ),
        isNotNull,
      );
    });

    test('rejects more than five allocations', () {
      expect(
        SupplierPaymentFormValidator.validatePayment(
          amountFils: 60000,
          allocationFils: [10000, 10000, 10000, 10000, 10000, 10000],
          remainingFils: [10000, 10000, 10000, 10000, 10000, 10000],
        ),
        isNotNull,
      );
    });

    test('rejects a negative allocation', () {
      expect(
        SupplierPaymentFormValidator.validatePayment(
          amountFils: 40000,
          allocationFils: [-1000],
          remainingFils: [40000],
        ),
        isNotNull,
      );
    });

    test('rejects mismatched allocation/remaining list lengths', () {
      expect(
        SupplierPaymentFormValidator.validatePayment(
          amountFils: 40000,
          allocationFils: [40000],
          remainingFils: [40000, 25000],
        ),
        isNotNull,
      );
    });

    test('uses exact fils arithmetic so 0.10 + 0.20 == 0.30 with no float drift', () {
      expect(
        SupplierPaymentFormValidator.validatePayment(
          amountFils: 300,
          allocationFils: [100, 200],
          remainingFils: [100, 200],
        ),
        isNull,
      );
    });
  });
}
