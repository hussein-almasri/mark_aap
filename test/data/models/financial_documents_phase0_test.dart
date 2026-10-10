import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mark_aap/data/models/cash_withdrawal_model.dart';
import 'package:mark_aap/data/models/purchase_invoice_model.dart';
import 'package:mark_aap/data/models/supplier_debt_model.dart';
import 'package:mark_aap/data/models/supplier_payment_model.dart';

/// Round-trips the exact Firestore document shapes the two-phase repositories
/// (PurchaseInvoiceRepository.createInvoice / SupplierPaymentRepository
/// .createPayment) now write, through the models' fromData factories.
///
/// These are pure-Dart tests (no Firebase / emulator required) so they run in
/// any environment. They specifically pin the Phase 0 fixes:
///
///  * Automatic (invoice / supplier-payment) cash-withdrawal documents are
///    written WITHOUT a `source` key (the Firestore rules forbid it via
///    hasOnlyKeys). [CashWithdrawalModel.fromData] must therefore treat a
///    missing `source` as the shop-cash default instead of throwing.
///  * The invoice document omits `notes` when null (the rules reject a null
///    `notes` key), so fromData must yield a null note.
void main() {
  final createdAt = Timestamp.fromMillisecondsSinceEpoch(1700000000000);

  group('CashWithdrawalModel.fromData (automatic withdrawals have no source)', () {
    test('invoice-linked withdrawal without a source key defaults to shop cash', () {
      // Exact shape written by createInvoice when shopCashAmountFils > 0:
      // hasOnlyKeys([amountFils, type, invoiceId, createdAt, createdBy, status]).
      final model = CashWithdrawalModel.fromData(
        withdrawalId: 'invoice_inv-1',
        data: {
          'amountFils': 3000,
          'type': 'PURCHASE_INVOICE',
          'invoiceId': 'inv-1',
          'createdAt': createdAt,
          'createdBy': 'admin-1',
          'status': 'ACTIVE',
        },
      );

      expect(model.amountFils, 3000);
      expect(model.type, CashWithdrawalType.purchaseInvoice);
      expect(model.invoiceId, 'inv-1');
      expect(model.supplierPaymentId, isNull);
      expect(model.status, CashWithdrawalStatus.active);
      // The Phase 0 fix: a missing source must not throw, and must default to
      // the shop-cash source the model uses for automatic withdrawals.
      expect(model.source, SupplierPaymentSource.shopCash);
    });

    test('supplier-payment-linked withdrawal without a source key defaults to shop cash', () {
      // Exact shape written by createPayment when source == SHOP_CASH:
      // hasOnlyKeys([amountFils, type, supplierPaymentId, createdAt, createdBy, status]).
      final model = CashWithdrawalModel.fromData(
        withdrawalId: 'supplierPayment_pay-1',
        data: {
          'amountFils': 4000,
          'type': 'PURCHASE_INVOICE',
          'supplierPaymentId': 'pay-1',
          'createdAt': createdAt,
          'createdBy': 'employee-1',
          'status': 'ACTIVE',
        },
      );

      expect(model.supplierPaymentId, 'pay-1');
      expect(model.invoiceId, isNull);
      expect(model.source, SupplierPaymentSource.shopCash);
    });

    test('manual withdrawal with an explicit source still parses it', () {
      final model = CashWithdrawalModel.fromData(
        withdrawalId: 'wd-manual-1',
        data: {
          'amountFils': 500,
          'type': 'PERSONAL_EXPENSE',
          'source': 'SHOP_CASH',
          'note': 'petty cash',
          'createdAt': createdAt,
          'createdBy': 'admin-1',
          'status': 'ACTIVE',
        },
      );

      expect(model.type, CashWithdrawalType.personalExpense);
      expect(model.source, SupplierPaymentSource.shopCash);
      expect(model.note, 'petty cash');
    });

    test('automatic invoice withdrawal enforces the invoice_ ID prefix', () {
      expect(
        () => CashWithdrawalModel.fromData(
          withdrawalId: 'wrong-id',
          data: {
            'amountFils': 100,
            'type': 'PURCHASE_INVOICE',
            'invoiceId': 'inv-1',
            'createdAt': createdAt,
            'createdBy': 'admin-1',
            'status': 'ACTIVE',
          },
        ),
        throwsArgumentError,
      );
    });
  });

  group('PurchaseInvoiceModel.fromData (two-phase invoice shape)', () {
    test('parses the invoice document, with notes omitted as null', () {
      // Exact shape written by createInvoice phase 2 (notes key absent).
      final model = PurchaseInvoiceModel.fromData(
        invoiceId: 'inv-1',
        data: {
          'companyId': 'company-1',
          'companyName': 'Example Company',
          'totalAmountFils': 10000,
          'shopCashAmountFils': 3000,
          'outsideCashAmountFils': 2000,
          'supplierDebtAmountFils': 5000,
          'status': 'ACTIVE',
          'createdAt': createdAt,
          'createdBy': 'admin-1',
          'operationId': 'inv-1',
          'photoIds': <String>[],
        },
      );

      expect(model.invoiceId, 'inv-1');
      expect(model.operationId, 'inv-1');
      expect(model.totalAmountFils, 10000);
      expect(model.notes, isNull);
      expect(model.supplierInvoiceNumber, isNull);
      expect(model.status, PurchaseInvoiceStatus.active);
      expect(model.photoIds, isEmpty);
    });

    test('parses the invoice document when notes and number are present', () {
      final model = PurchaseInvoiceModel.fromData(
        invoiceId: 'inv-2',
        data: {
          'companyId': 'company-1',
          'companyName': 'Example Company',
          'supplierInvoiceNumber': 'SI-100',
          'totalAmountFils': 1000,
          'shopCashAmountFils': 0,
          'outsideCashAmountFils': 0,
          'supplierDebtAmountFils': 1000,
          'notes': 'restock',
          'status': 'ACTIVE',
          'createdAt': createdAt,
          'createdBy': 'employee-1',
          'operationId': 'inv-2',
          'photoIds': <String>['photo-1'],
        },
      );

      expect(model.supplierInvoiceNumber, 'SI-100');
      expect(model.notes, 'restock');
      expect(model.photoIds, const ['photo-1']);
    });
  });

  group('SupplierDebtModel.fromData (written only when debt > 0)', () {
    test('parses the debt document written alongside an invoice', () {
      final model = SupplierDebtModel.fromData(
        invoiceId: 'inv-1',
        data: {
          'invoiceId': 'inv-1',
          'companyId': 'company-1',
          'companyName': 'Example Company',
          'originalAmountFils': 5000,
          'remainingAmountFils': 5000,
          'status': 'OPEN',
          'createdAt': createdAt,
          'createdBy': 'admin-1',
          'operationId': 'inv-1',
          'lastOperationId': 'inv-1',
        },
      );

      expect(model.invoiceId, 'inv-1');
      expect(model.originalAmountFils, 5000);
      expect(model.remainingAmountFils, 5000);
      expect(model.status, SupplierDebtStatus.open);
      expect(model.lastOperationId, 'inv-1');
    });
  });

  group('SupplierPaymentModel.fromData (two-phase payment shape)', () {
    test('parses a one-allocation SHOP_CASH payment', () {
      final model = SupplierPaymentModel.fromData(
        paymentId: 'pay-1',
        data: {
          'companyId': 'company-1',
          'companyName': 'Example Company',
          'amountFils': 4000,
          'source': 'SHOP_CASH',
          'status': 'ACTIVE',
          'allocationCount': 1,
          'allocation1InvoiceId': 'inv-1',
          'allocation1AmountFils': 4000,
          'createdAt': createdAt,
          'createdBy': 'employee-1',
          'operationId': 'pay-1',
        },
      );

      expect(model.paymentId, 'pay-1');
      expect(model.operationId, 'pay-1');
      expect(model.source, SupplierPaymentSource.shopCash);
      expect(model.allocationCount, 1);
      expect(model.allocationTotalFils, 4000);
      expect(model.allocation1InvoiceId, 'inv-1');
      expect(model.notes, isNull);
    });
  });
}
