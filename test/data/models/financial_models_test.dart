import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mark_aap/data/models/cash_withdrawal_model.dart';
import 'package:mark_aap/data/models/financial_operation_model.dart';
import 'package:mark_aap/data/models/purchase_invoice_model.dart';
import 'package:mark_aap/data/models/supplier_debt_model.dart';
import 'package:mark_aap/data/models/supplier_payment_model.dart';

void main() {
  final timestamp = Timestamp.fromDate(DateTime.utc(2026, 1, 2));

  PurchaseInvoiceModel invoice({
    PurchaseInvoiceStatus status = PurchaseInvoiceStatus.active,
    Timestamp? cancelledAt,
    String? cancelledBy,
    String? cancellationReason,
    String? cancellationOperationId,
    int total = 1000,
  }) => PurchaseInvoiceModel(
    invoiceId: 'invoice-1',
    companyId: 'company-1',
    companyName: 'Supplier',
    totalAmountFils: total,
    shopCashAmountFils: 200,
    outsideCashAmountFils: 300,
    supplierDebtAmountFils: total - 500,
    status: status,
    createdAt: timestamp,
    createdBy: 'admin-1',
    operationId: 'invoice-1',
    photoIds: const ['photo-1'],
    cancelledAt: cancelledAt,
    cancelledBy: cancelledBy,
    cancellationReason: cancellationReason,
    cancellationOperationId: cancellationOperationId,
  );

  SupplierPaymentModel payment({
    int allocationCount = 2,
    int amountFils = 700,
    SupplierPaymentStatus status = SupplierPaymentStatus.active,
    Timestamp? cancelledAt,
    String? cancelledBy,
    String? cancellationReason,
    String? cancellationOperationId,
    String? allocation2InvoiceId = 'invoice-2',
    int? allocation2AmountFils = 300,
    String? allocation3InvoiceId,
    int? allocation3AmountFils,
  }) => SupplierPaymentModel(
    paymentId: 'payment-1',
    companyId: 'company-1',
    companyName: 'Supplier',
    amountFils: amountFils,
    source: SupplierPaymentSource.shopCash,
    status: status,
    allocationCount: allocationCount,
    allocation1InvoiceId: 'invoice-1',
    allocation1AmountFils: 400,
    allocation2InvoiceId: allocation2InvoiceId,
    allocation2AmountFils: allocation2AmountFils,
    allocation3InvoiceId: allocation3InvoiceId,
    allocation3AmountFils: allocation3AmountFils,
    createdAt: timestamp,
    createdBy: 'admin-1',
    operationId: 'payment-1',
    cancelledAt: cancelledAt,
    cancelledBy: cancelledBy,
    cancellationReason: cancellationReason,
    cancellationOperationId: cancellationOperationId,
  );

  test('PurchaseInvoice round-trips integer fils and immutable photo IDs', () {
    final model = invoice();
    expect(model.totalAmountFils, 1000);
    expect(model.toData()['totalAmountFils'], isA<int>());
    expect(() => model.photoIds.add('photo-2'), throwsUnsupportedError);
    final parsed = PurchaseInvoiceModel.fromData(
      invoiceId: model.invoiceId,
      data: model.toData(),
    );
    expect(parsed.toData(), model.toData());
  });

  test(
    'PurchaseInvoice rejects invalid totals, split amounts, and cancellation data',
    () {
      expect(() => invoice(total: 0), throwsArgumentError);
      expect(
        () => PurchaseInvoiceModel(
          invoiceId: 'invoice-1',
          companyId: 'company-1',
          companyName: 'Supplier',
          totalAmountFils: 1000,
          shopCashAmountFils: 300,
          outsideCashAmountFils: 300,
          supplierDebtAmountFils: 300,
          status: PurchaseInvoiceStatus.active,
          createdAt: timestamp,
          createdBy: 'admin-1',
          operationId: 'invoice-1',
          photoIds: const [],
        ),
        throwsArgumentError,
      );
      expect(
        () => invoice(
          status: PurchaseInvoiceStatus.cancelled,
          cancelledAt: timestamp,
        ),
        throwsArgumentError,
      );
    },
  );

  test(
    'SupplierDebt round-trips and validates status against remaining fils',
    () {
      final model = SupplierDebtModel(
        invoiceId: 'invoice-1',
        companyId: 'company-1',
        companyName: 'Supplier',
        originalAmountFils: 1000,
        remainingAmountFils: 400,
        status: SupplierDebtStatus.open,
        createdAt: timestamp,
        createdBy: 'admin-1',
        operationId: 'invoice-1',
        lastOperationId: 'payment-1',
      );
      expect(
        SupplierDebtModel.fromData(
          invoiceId: model.invoiceId,
          data: model.toData(),
        ).toData(),
        model.toData(),
      );
      expect(
        () => SupplierDebtModel(
          invoiceId: 'invoice-1',
          companyId: 'company-1',
          companyName: 'Supplier',
          originalAmountFils: 1000,
          remainingAmountFils: 0,
          status: SupplierDebtStatus.open,
          createdAt: timestamp,
          createdBy: 'admin-1',
          operationId: 'invoice-1',
          lastOperationId: 'payment-1',
        ),
        throwsArgumentError,
      );
    },
  );

  test('SupplierPayment serializes five explicit fixed allocation slots', () {
    final model = payment();
    final data = model.toData();
    expect(data['allocationCount'], 2);
    expect(data['allocation1InvoiceId'], 'invoice-1');
    expect(data['allocation2AmountFils'], 300);
    expect(data.keys.any((key) => key.contains('Manifest')), isFalse);
    expect(data.keys.any((key) => key.contains('allocations')), isFalse);
    expect(
      SupplierPaymentModel.fromData(
        paymentId: model.paymentId,
        data: data,
      ).toData(),
      data,
    );
  });

  test(
    'SupplierPayment rejects invalid count, slots, totals, IDs, and money',
    () {
      expect(() => payment(allocationCount: 0), throwsArgumentError);
      expect(() => payment(allocationCount: 6), throwsArgumentError);
      expect(() => payment(amountFils: 701), throwsArgumentError);
      expect(() => payment(allocationCount: 1), throwsArgumentError);
      expect(
        () => payment(
          allocationCount: 2,
          amountFils: 700,
          allocation3InvoiceId: 'invoice-3',
          allocation3AmountFils: 1,
        ),
        throwsArgumentError,
      );
      expect(
        () => payment(
          allocationCount: 2,
          allocation2InvoiceId: 'invoice-1',
          allocation2AmountFils: 300,
        ),
        throwsArgumentError,
      );
    },
  );

  test('SupplierPayment rejects incomplete cancellation and unknown enums', () {
    expect(
      () => payment(
        status: SupplierPaymentStatus.cancelled,
        cancelledAt: timestamp,
      ),
      throwsArgumentError,
    );
    final data = payment().toData()..['source'] = 'CASH';
    expect(
      () => SupplierPaymentModel.fromData(paymentId: 'payment-1', data: data),
      throwsFormatException,
    );
  });

  test('CashWithdrawal round-trips and requires exactly one matching link', () {
    final model = CashWithdrawalModel(
      withdrawalId: 'supplierPayment_payment-1',
      amountFils: 700,
      type: CashWithdrawalType.purchaseInvoice,
      supplierPaymentId: 'payment-1',
      createdAt: timestamp,
      createdBy: 'admin-1',
      status: CashWithdrawalStatus.active,
    );
    expect(
      CashWithdrawalModel.fromData(
        withdrawalId: model.withdrawalId,
        data: model.toData(),
      ).toData(),
      model.toData(),
    );
    expect(
      () => CashWithdrawalModel(
        withdrawalId: 'withdrawal-1',
        amountFils: 700,
        type: CashWithdrawalType.purchaseInvoice,
        createdAt: timestamp,
        createdBy: 'admin-1',
        status: CashWithdrawalStatus.active,
      ),
      throwsArgumentError,
    );
  });

  test(
    'FinancialOperation round-trips valid payment operation and rejects bad payloads',
    () {
      final model = FinancialOperationModel(
        operationId: 'payment-1',
        type: FinancialOperationType.createSupplierPayment,
        createdBy: 'admin-1',
        createdAt: timestamp,
        status: FinancialOperationStatus.completed,
        retryCount: 0,
        paymentId: 'payment-1',
      );
      expect(
        FinancialOperationModel.fromData(
          operationId: model.operationId,
          data: model.toData(),
        ).toData(),
        model.toData(),
      );
      expect(
        () => FinancialOperationModel(
          operationId: 'payment-1',
          type: FinancialOperationType.createSupplierPayment,
          createdBy: 'admin-1',
          createdAt: timestamp,
          status: FinancialOperationStatus.processing,
          retryCount: 4,
          paymentId: 'payment-1',
        ),
        throwsArgumentError,
      );
      expect(
        () => FinancialOperationModel(
          operationId: 'payment-1',
          type: FinancialOperationType.createSupplierPayment,
          createdBy: 'admin-1',
          createdAt: timestamp,
          status: FinancialOperationStatus.processing,
          retryCount: 0,
          paymentId: null,
        ),
        throwsArgumentError,
      );
    },
  );
}
