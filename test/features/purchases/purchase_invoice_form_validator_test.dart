import 'package:flutter_test/flutter_test.dart';
import 'package:mark_aap/features/purchases/purchase_invoice_form_validator.dart';

void main() {
  group('tryParseJodField', () {
    test('treats a blank field as zero fils', () {
      expect(PurchaseInvoiceFormValidator.tryParseJodField(''), 0);
      expect(PurchaseInvoiceFormValidator.tryParseJodField('   '), 0);
    });

    test('parses whole and two-decimal JOD amounts to integer fils', () {
      expect(PurchaseInvoiceFormValidator.tryParseJodField('1'), 1000);
      expect(PurchaseInvoiceFormValidator.tryParseJodField('125.50'), 125500);
      expect(PurchaseInvoiceFormValidator.tryParseJodField('0.01'), 10);
      expect(PurchaseInvoiceFormValidator.tryParseJodField('0.1'), 100);
    });

    test('rejects more than two decimal places', () {
      expect(PurchaseInvoiceFormValidator.tryParseJodField('1.234'), isNull);
      expect(PurchaseInvoiceFormValidator.tryParseJodField('1.2345'), isNull);
    });

    test('rejects non-numeric and negative input', () {
      expect(PurchaseInvoiceFormValidator.tryParseJodField('abc'), isNull);
      expect(PurchaseInvoiceFormValidator.tryParseJodField('-5'), isNull);
      expect(PurchaseInvoiceFormValidator.tryParseJodField('1.2.3'), isNull);
    });
  });

  group('validateTotalField', () {
    test('requires a value', () {
      expect(
        PurchaseInvoiceFormValidator.validateTotalField(''),
        'الإجمالي مطلوب.',
      );
      expect(
        PurchaseInvoiceFormValidator.validateTotalField(null),
        'الإجمالي مطلوب.',
      );
    });

    test('rejects invalid amounts', () {
      expect(PurchaseInvoiceFormValidator.validateTotalField('abc'), isNotNull);
      expect(
        PurchaseInvoiceFormValidator.validateTotalField('1.234'),
        isNotNull,
      );
    });

    test('accepts a valid amount', () {
      expect(PurchaseInvoiceFormValidator.validateTotalField('125.50'), isNull);
      expect(PurchaseInvoiceFormValidator.validateTotalField('7'), isNull);
    });
  });

  group('validateSplitField', () {
    test('treats blank as valid (zero)', () {
      expect(
        PurchaseInvoiceFormValidator.validateSplitField('', label: 'كاش'),
        isNull,
      );
      expect(
        PurchaseInvoiceFormValidator.validateSplitField(null, label: 'كاش'),
        isNull,
      );
    });

    test('rejects invalid amounts but keeps the label in the message', () {
      final error = PurchaseInvoiceFormValidator.validateSplitField(
        '1.234',
        label: 'دين المورد',
      );
      expect(error, contains('دين المورد'));
    });

    test('accepts a valid amount', () {
      expect(
        PurchaseInvoiceFormValidator.validateSplitField('10.00', label: 'كاش'),
        isNull,
      );
    });
  });

  group('validateSplit (cross-field)', () {
    test('accepts a split that sums exactly to the total', () {
      expect(
        PurchaseInvoiceFormValidator.validateSplit(
          totalFils: 125500,
          shopCashFils: 50000,
          outsideCashFils: 25500,
          supplierDebtFils: 50000,
        ),
        isNull,
      );
    });

    test('accepts an all-zero split with a positive total only via zeros summing', () {
      // 10.00 total fully paid from shop cash, nothing elsewhere.
      expect(
        PurchaseInvoiceFormValidator.validateSplit(
          totalFils: 10000,
          shopCashFils: 10000,
          outsideCashFils: 0,
          supplierDebtFils: 0,
        ),
        isNull,
      );
    });

    test('rejects a non-positive total', () {
      expect(
        PurchaseInvoiceFormValidator.validateSplit(
          totalFils: 0,
          shopCashFils: 0,
          outsideCashFils: 0,
          supplierDebtFils: 0,
        ),
        isNotNull,
      );
      expect(
        PurchaseInvoiceFormValidator.validateSplit(
          totalFils: -1000,
          shopCashFils: 0,
          outsideCashFils: 0,
          supplierDebtFils: 0,
        ),
        isNotNull,
      );
    });

    test('rejects a split that does not sum to the total', () {
      final error = PurchaseInvoiceFormValidator.validateSplit(
        totalFils: 10000,
        shopCashFils: 5000,
        outsideCashFils: 2000,
        supplierDebtFils: 2000, // sums to 9000, not 10000
      );
      expect(error, isNotNull);
      expect(error, contains('لا يساوي'));
    });

    test('rejects an over-summing split', () {
      expect(
        PurchaseInvoiceFormValidator.validateSplit(
          totalFils: 10000,
          shopCashFils: 6000,
          outsideCashFils: 3000,
          supplierDebtFils: 3000, // sums to 12000
        ),
        isNotNull,
      );
    });

    test('rejects any negative part', () {
      expect(
        PurchaseInvoiceFormValidator.validateSplit(
          totalFils: 10000,
          shopCashFils: -1,
          outsideCashFils: 10000,
          supplierDebtFils: 0,
        ),
        isNotNull,
      );
    });

    test('uses exact fils arithmetic so 0.10 + 0.20 == 0.30 with no float drift', () {
      expect(
        PurchaseInvoiceFormValidator.validateSplit(
          totalFils: 300,
          shopCashFils: 100,
          outsideCashFils: 200,
          supplierDebtFils: 0,
        ),
        isNull,
      );
    });
  });
}
