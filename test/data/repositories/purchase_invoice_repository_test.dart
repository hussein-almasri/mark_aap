import 'package:flutter_test/flutter/test.dart';

import 'package:mark_aap/data/models/purchase_invoice_model.dart';
import 'package:mark_aap/data/repositories/purchase_invoice_repository.dart';

void main() {
  const String testStoreId = 'store-1';

  group('PurchaseInvoiceRepository', () {
    test('createInvoice succeeds with valid data', () async {
      final repo = PurchaseInvoiceRepository();
      final operationId = 'invoice-test-1';

      final returnedId = await repo.createInvoice(
        storeId: testStoreId,
        companyId: 'company-1',
        companyName: 'Test Supplier',
        totalAmountFils: 1000,
        shopCashAmountFils: 200,
        outsideCashAmountFils: 300,
        supplierDebtAmountFils: 500,
        supplierInvoiceNumber: 'SI-100',
        notes: 'Test invoice',
        photoIds: const ['photo-1', 'photo-2'],
        createdBy: 'admin-1',
        operationId: operationId,
      );

      expect(returnedId, operationId);

      // Verify invoice was created
      final invoice = await repo.getInvoice(testStoreId, operationId);
      expect(invoice.totalAmountFils, 1000);
      expect(invoice.shopCashAmountFils, 200);
      expect(invoice.outsideCashAmountFils, 300);
      expect(invoice.supplierDebtAmountFils, 500);
      expect(invoice.companyName, 'Test Supplier');
      expect(invoice.status, PurchaseInvoiceStatus.active);
      expect(invoice.photoIds, const ['photo-1', 'photo-2']);
      expect(invoice.supplierInvoiceNumber, 'SI-100');
      expect(invoice.notes, 'Test invoice');

      // Verify supplier debt was created
      final debtSnapshot =
          await repo.supplierDebts(testStoreId).doc(operationId).get();
      expect(debtSnapshot.exists, true);
      final debtData = debtSnapshot.data()!;
      expect(debtData['originalAmountFils'], 500);
      expect(debtData['remainingAmountFils'], 500);
      expect(debtData['status'], 'OPEN');

      // Verify cash withdrawal was created (shopCash > 0)
      final withdrawalSnapshot =
          await repo.cashWithdrawals(testStoreId).doc('invoice_$operationId').get();
      expect(withdrawalSnapshot.exists, true);
      final withdrawalData = withdrawalSnapshot.data()!;
      expect(withdrawalData['amountFils'], 200);
      expect(withdrawalData['type'], 'PURCHASE_INVOICE');

      // Verify financial operation was created
      final operationSnapshot =
          await repo.operations(testStoreId).doc(operationId).get();
      expect(operationSnapshot.exists, true);
      final opData = operationSnapshot.data()!;
      expect(opData['type'], 'CREATE_PURCHASE_INVOICE');
      expect(opData['status'], 'COMPLETED');
      expect(opData['retryCount'], 0);
    });

    test('createInvoice rejects invalid component sum', () async {
      final repo = PurchaseInvoiceRepository();

      expect(
        () => repo.createInvoice(
          storeId: testStoreId,
          companyId: 'company-1',
          companyName: 'Supplier',
          totalAmountFils: 1000,
          shopCashAmountFils: 300,
          outsideCashAmountFils: 300,
          supplierDebtAmountFils: 300,
          supplierInvoiceNumber: null,
          notes: null,
          photoIds: const [],
          createdBy: 'admin-1',
          operationId: 'invoice-bad-1',
        ),
        throwsArgumentError,
      );
    });

    test('createInvoice rejects total <= 0', () async {
      final repo = PurchaseInvoiceRepository();

      expect(
        () => repo.createInvoice(
          storeId: testStoreId,
          companyId: 'company-1',
          companyName: 'Supplier',
          totalAmountFils: 0,
          shopCashAmountFils: 0,
          outsideCashAmountFils: 0,
          supplierDebtAmountFils: 0,
          supplierInvoiceNumber: null,
          notes: null,
          photoIds: const [],
          createdBy: 'admin-1',
          operationId: 'invoice-zero-1',
        ),
        throwsArgumentError,
      );
    });

    test('idempotency: duplicate operationId throws', () async {
      final repo = PurchaseInvoiceRepository();
      final operationId = 'invoice-idempotent-1';

      // First creation succeeds
      await repo.createInvoice(
        storeId: testStoreId,
        companyId: 'company-1',
        companyName: 'Supplier',
        totalAmountFils: 500,
        shopCashAmountFils: 100,
        outsideCashAmountFils: 200,
        supplierDebtAmountFils: 200,
        supplierInvoiceNumber: null,
        notes: null,
        photoIds: const [],
        createdBy: 'admin-1',
        operationId: operationId,
      );

      // Second attempt with same operationId should fail (idempotent)
      expect(
        () => repo.createInvoice(
          storeId: testStoreId,
          companyId: 'company-1',
          companyName: 'Supplier',
          totalAmountFils: 500,
          shopCashAmountFils: 100,
          outsideCashAmountFils: 200,
          supplierDebtAmountFils: 200,
          supplierInvoiceNumber: null,
          notes: null,
          photoIds: const [],
          createdBy: 'admin-1',
          operationId: operationId,
        ),
        throwsA(isA<InvoiceAlreadyExistsException>),
      );
    });

    test('getInvoice returns existing invoice', () async {
      final repo = PurchaseInvoiceRepository();

      // First create an invoice
      await repo.createInvoice(
        storeId: testStoreId,
        companyId: 'company-1',
        companyName: 'Supplier',
        totalAmountFils: 750,
        shopCashAmountFils: 100,
        outsideCashAmountFils: 300,
        supplierDebtAmountFils: 350,
        supplierInvoiceNumber: 'SI-200',
        notes: 'Another invoice',
        photoIds: const ['photo-3'],
        createdBy: 'employee-1',
        operationId: 'invoice-get-test-1',
      );

      // Then retrieve it
      final invoice = await repo.getInvoice(testStoreId, 'invoice-get-test-1');
      expect(invoice.totalAmountFils, 750);
      expect(invoice.companyName, 'Supplier');
      expect(invoice.supplierInvoiceNumber, 'SI-200');
      expect(invoice.notes, 'Another invoice');
      expect(invoice.photoIds, const ['photo-3']);
    });

    test('listInvoices returns list of invoices', () async {
      final repo = PurchaseInvoiceRepository();

      // Create a few invoices
      await repo.createInvoice(
        storeId: testStoreId,
        companyId: 'company-1',
        companyName: 'Supplier A',
        totalAmountFils: 100,
        shopCashAmountFils: 20,
        outsideCashAmountFils: 30,
        supplierDebtAmountFils: 50,
        supplierInvoiceNumber: 'SI-1',
        notes: 'Invoice 1',
        photoIds: const [],
        createdBy: 'admin-1',
        operationId: 'invoice-list-1',
      );
      await repo.createInvoice(
        storeId: testStoreId,
        companyId: 'company-1',
        companyName: 'Supplier B',
        totalAmountFils: 200,
        shopCashAmountFils: 30,
        outsideCashAmountFils: 80,
        supplierDebtAmountFils: 90,
        supplierInvoiceNumber: 'SI-2',
        notes: 'Invoice 2',
        photoIds: const ['photo-1'],
        createdBy: 'admin-1',
        operationId: 'invoice-list-2',
      );

      final invoices = await repo.listInvoices(testStoreId);
      expect(invoices.length, 2);
      expect(invoices.map((i) => i.companyName).toSet(), {'Supplier A', 'Supplier B'});
    });
  });
}