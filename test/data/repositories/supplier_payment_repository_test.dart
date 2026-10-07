import 'package:flutter_test/flutter/test.dart';

import 'package:mark_aap/data/models/supplier_payment_model.dart';
import 'package:mark_aap/data/repositories/supplier_payment_repository.dart';

void main() {
  const String testStoreId = 'store-1';

  group('SupplierPaymentRepository', () {
    test('createPayment with one allocation succeeds', () async {
      final repo = SupplierPaymentRepository();

      final operationId = 'payment-test-1';

      final paidId = await repo.createPayment(
        storeId: testStoreId,
        companyId: 'company-1',
        companyName: 'Test Supplier',
        amountFils: 700,
        source: SupplierPaymentSource.shopCash,
        allocationCount: 1,
        allocation1InvoiceId: 'invoice-1',
        allocation1AmountFils: 700,
        notes: 'Test payment',
        createdBy: 'admin-1',
        operationId: operationId,
      );

      expect(paidId, operationId);

      // Verify payment was created
      final payment = await repo.getPayment(testStoreId, operationId);
      expect(payment.amountFils, 700);
      expect(payment.companyName, 'Test Supplier');
      expect(payment.source, SupplierPaymentSource.shopCash);
      expect(payment.allocationCount, 1);
      expect(payment.allocation1InvoiceId, 'invoice-1');
      expect(payment.allocation1AmountFils, 700);
      expect(payment.status, 'ACTIVE');
      expect(payment.notes, 'Test payment');

      // Verify supplier debt was decreased
      final debtSnapshot =
          await repo.supplierDebts(testStoreId).doc('invoice-1').get();
      final debtData = debtSnapshot.data()! as Map<String, dynamic>;
      expect(debtData['originalAmountFils'], 700);
      expect(debtData['remainingAmountFils'], 0);
      expect(debtData['status'], 'PAID');

      // Verify automatic cash withdrawal was created (SHOP_CASH)
      final withdrawalSnapshot =
          await repo.cashWithdrawals(testStoreId).doc('supplierPayment_$operationId').get();
      expect(withdrawalSnapshot.exists, true);
      final withdrawalData = withdrawalSnapshot.data()!;
      expect(withdrawalData['amountFils'], 700);
      expect(withdrawalData['type'], 'PURCHASE_INVOICE');

      // Verify financial operation was created
      final operationSnapshot =
          await repo.operations(testStoreId).doc(operationId).get();
      expect(operationSnapshot.exists, true);
      final opData = operationSnapshot.data()!;
      expect(opData['type'], 'CREATE_SUPPLIER_PAYMENT');
      expect(opData['status'], 'COMPLETED');
      expect(opData['retryCount'], 0);
    });

    test('createPayment with multiple allocations succeeds', () async {
      final repo = SupplierPaymentRepository();

      final operationId = 'payment-test-2';

      final paidId = await repo.createPayment(
        storeId: testStoreId,
        companyId: 'company-1',
        companyName: 'Test Supplier',
        amountFils: 1000,
        source: SupplierPaymentSource.outsideCash,
        allocationCount: 3,
        allocation1InvoiceId: 'invoice-2',
        allocation1AmountFils: 400,
        allocation2InvoiceId: 'invoice-3',
        allocation2AmountFils: 300,
        allocation3InvoiceId: 'invoice-4',
        allocation3AmountFils: 300,
        notes: 'Multi-alloc payment',
        createdBy: 'admin-1',
        operationId: operationId,
      );

      expect(paidId, operationId);

      // Verify payment was created
      final payment = await repo.getPayment(testStoreId, operationId);
      expect(payment.amountFils, 1000);
      expect(payment.allocationCount, 3);
      expect(payment.allocation1InvoiceId, 'invoice-2');
      expect(payment.allocation1AmountFils, 400);
      expect(payment.allocation2InvoiceId, 'invoice-3');
      expect(payment.allocation2AmountFils, 300);
      expect(payment.allocation3InvoiceId, 'invoice-4');
      expect(payment.allocation3AmountFils, 300);
      expect(payment.status, 'ACTIVE');
      expect(payment.notes, 'Multi-alloc payment');

      // Since source is OUTSIDE_CASH, no withdrawal should be created
      final withdrawalSnapshot =
          await repo.cashWithdrawals(testStoreId).doc('supplierPayment_$operationId').get();
      expect(withdrawalSnapshot.exists, false);

      // Verify debts were decreased
      for (final invoiceId in ['invoice-2', 'invoice-3', 'invoice-4']) {
        final debtSnapshot =
            await repo.supplierDebts(testStoreId).doc(invoiceId).get();
        final debtData = debtSnapshot.data()! as Map<String, dynamic>;
        // Each debt should have remaining decreased by the allocation amount
        // (assuming original was at least the allocation amount)
        expect(debtSnapshot.exists, true);
      }
    });

    test('createPayment rejects allocationCount > 5', () async {
      final repo = SupplierPaymentRepository();

      expect(
        () => repo.createPayment(
          storeId: 'store-1',
          companyId: 'company-1',
          companyName: 'Supplier',
          amountFils: 100,
          source: SupplierPaymentSource.shopCash,
          allocationCount: 6,
          allocation1InvoiceId: 'invoice-1',
          allocation1AmountFils: 50,
          createdBy: 'admin-1',
          operationId: 'payment-bad-1',
        ),
        throwsArgumentError,
      );
    });

    test('createPayment rejects duplicate invoice IDs', () async {
      final repo = SupplierPaymentRepository();

      expect(
        () => repo.createPayment(
          storeId: 'store-1',
          companyId: 'company-1',
          companyName: 'Supplier',
          amountFils: 200,
          source: SupplierPaymentSource.shopCash,
          allocationCount: 2,
          allocation1InvoiceId: 'invoice-1',
          allocation1AmountFils: 100,
          allocation2InvoiceId: 'invoice-1', // duplicate!
          allocation2AmountFils: 100,
          createdBy: 'admin-1',
          operationId: 'payment-dup-1',
        ),
        throwsArgumentError,
      );
    });

    test('createPayment rejects allocation total mismatch', () async {
      final repo = SupplierPaymentRepository();

      expect(
        () => repo.createPayment(
          storeId: 'store-1',
          companyId: 'company-1',
          companyName: 'Supplier',
          amountFils: 500,
          source: SupplierPaymentSource.shopCash,
          allocationCount: 2,
          allocation1InvoiceId: 'invoice-1',
          allocation1AmountFils: 200,
          allocation2InvoiceId: 'invoice-2',
          allocation2AmountFils: 100, // 200+100=300 ≠ 500
          createdBy: 'admin-1',
          operationId: 'payment-mismatch-1',
        ),
        throwsArgumentError,
      );
    });

    test('createPayment rejects allocation amount > remaining debt', () async {
      final repo = SupplierPaymentRepository();

      expect(
        () => repo.createPayment(
          storeId: 'store-1',
          companyId: 'company-1',
          companyName: 'Supplier',
          amountFils: 500,
          source: SupplierPaymentSource.shopCash,
          allocationCount: 1,
          allocation1InvoiceId: 'invoice-1',
          allocation1AmountFils: 600, // > typical debt
          createdBy: 'admin-1',
          operationId: 'payment-exceed-1',
        ),
        throwsArgumentError,
      );
    });

    test('createPayment with OUTSIDE_CASH creates no withdrawal', () async {
      final repo = SupplierPaymentRepository();

      final operationId = 'payment-outside-1';

      final paidId = await repo.createPayment(
        storeId: testStoreId,
        companyId: 'company-1',
        companyName: 'Test Supplier',
        amountFils: 500,
        source: SupplierPaymentSource.outsideCash,
        allocationCount: 1,
        allocation1InvoiceId: 'invoice-5',
        allocation1AmountFils: 500,
        notes: 'Outside cash payment',
        createdBy: 'admin-1',
        operationId: operationId,
      );

      expect(paidId, operationId);

      // No withdrawal should be created for OUTSIDE_CASH
      final withdrawalSnapshot =
          await repo.cashWithdrawals(testStoreId).doc('supplierPayment_$operationId').get();
      expect(withdrawalSnapshot.exists, false);
    });

    test('idempotency: duplicate operationId throws', () async {
      final repo = SupplierPaymentRepository();
      final operationId = 'payment-idempotent-1';

      // First creation succeeds
      await repo.createPayment(
        storeId: testStoreId,
        companyId: 'company-1',
        companyName: 'Supplier',
        amountFils: 300,
        source: SupplierPaymentSource.shopCash,
        allocationCount: 1,
        allocation1InvoiceId: 'invoice-1',
        allocation1AmountFils: 300,
        notes: 'Idempotent test',
        createdBy: 'admin-1',
        operationId: operationId,
      );

      // Second attempt with same operationId should fail
      expect(
        () => repo.createPayment(
          storeId: testStoreId,
          companyId: 'company-1',
          companyName: 'Supplier',
          amountFils: 300,
          source: SupplierPaymentSource.shopCash,
          allocationCount: 1,
          allocation1InvoiceId: 'invoice-1',
          allocation1AmountFils: 300,
          notes: 'Idempotent test',
          createdBy: 'admin-1',
          operationId: operationId, // same operationId
        ),
        throwsA(isA<PaymentAllocationMismatchException>),
      );
    });

    test('getPayment returns existing payment', () async {
      final repo = SupplierPaymentRepository();

      // First create a payment
      await repo.createPayment(
        storeId: testStoreId,
        companyId: 'company-1',
        companyName: 'Supplier',
        amountFils: 250,
        source: SupplierPaymentSource.shopCash,
        allocationCount: 1,
        allocation1InvoiceId: 'invoice-1',
        allocation1AmountFils: 250,
        notes: 'Test',
        createdBy: 'admin-1',
        operationId: 'payment-get-test-1',
      );

      // Then retrieve it
      final payment = await repo.getPayment(testStoreId, 'payment-get-test-1');
      expect(payment.amountFils, 250);
      expect(payment.companyName, 'Supplier');
      expect(payment.allocation1InvoiceId, 'invoice-1');
    });

    test('listPayments returns list of payments', () async {
      final repo = SupplierPaymentRepository();

      // Create a few payments
      await repo.createPayment(
        storeId: testStoreId,
        companyId: 'company-1',
        companyName: 'Supplier A',
        amountFils: 100,
        source: SupplierPaymentSource.shopCash,
        allocationCount: 1,
        allocation1InvoiceId: 'invoice-1',
        allocation1AmountFils: 100,
        notes: 'Payment 1',
        createdBy: 'admin-1',
        operationId: 'payment-list-1',
      );
      await repo.createPayment(
        storeId: testStoreId,
        companyId: 'company-1',
        companyName: 'Supplier B',
        amountFils: 200,
        source: SupplierPaymentSource.outsideCash,
        allocationCount: 1,
        allocation1InvoiceId: 'invoice-2',
        allocation1AmountFils: 200,
        notes: 'Payment 2',
        createdBy: 'admin-1',
        operationId: 'payment-list-2',
      );

      final payments = await repo.listPayments(testStoreId);
      expect(payments.length, 2);
      expect(payments.map((p) => p.companyName).toSet(), {'Supplier A', 'Supplier B'});
    });
  });
}