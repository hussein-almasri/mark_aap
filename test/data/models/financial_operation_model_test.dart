import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mark_aap/data/models/financial_operation_model.dart';

void main() {
  final createdAt = Timestamp.fromDate(DateTime.utc(2026, 6, 1));

  test('parses all operation types stored by the financial repositories', () {
    final fixtures = <({
      String operationId,
      String type,
      Map<String, String> target,
    })>[
      (
        operationId: 'invoice-1',
        type: 'CREATE_PURCHASE_INVOICE',
        target: {'invoiceId': 'invoice-1'},
      ),
      (
        operationId: 'payment-1',
        type: 'CREATE_SUPPLIER_PAYMENT',
        target: {'paymentId': 'payment-1'},
      ),
      (
        operationId: 'cancel-invoice-1',
        type: 'CANCEL_PURCHASE_INVOICE',
        target: {'invoiceId': 'invoice-1'},
      ),
      (
        operationId: 'cancel-payment-1',
        type: 'CANCEL_SUPPLIER_PAYMENT',
        target: {'paymentId': 'payment-1'},
      ),
      (
        operationId: 'withdrawal-1',
        type: 'CREATE_MANUAL_WITHDRAWAL',
        target: {'withdrawalId': 'withdrawal-1'},
      ),
      (
        operationId: 'cancel-withdrawal-1',
        type: 'CANCEL_MANUAL_WITHDRAWAL',
        target: {'withdrawalId': 'withdrawal-1'},
      ),
      (
        operationId: 'set-opening-1',
        type: 'SET_OPENING_BALANCE',
        target: {'cashBoxId': 'openingBalance'},
      ),
      (
        operationId: 'amend-opening-1',
        type: 'AMEND_OPENING_BALANCE',
        target: {'cashBoxId': 'openingBalance'},
      ),
      (
        operationId: 'deposit-1',
        type: 'CREATE_CASH_DEPOSIT',
        target: {'depositId': 'deposit-1'},
      ),
    ];

    for (final fixture in fixtures) {
      final operation = FinancialOperationModel.fromData(
        operationId: fixture.operationId,
        data: {
          'type': fixture.type,
          'createdBy': 'user-1',
          'createdAt': createdAt,
          'status': 'COMPLETED',
          'retryCount': 0,
          ...fixture.target,
        },
      );
      expect(operation.type.value, fixture.type);
      expect(operation.createdBy, 'user-1');
      expect(operation.createdAt, createdAt);
    }
  });

  test('round-trips an operation with displayable amount metadata', () {
    final operation = FinancialOperationModel.fromData(
      operationId: 'deposit-1',
      data: {
        'type': 'CREATE_CASH_DEPOSIT',
        'depositId': 'deposit-1',
        'createdBy': 'user-1',
        'createdAt': createdAt,
        'status': 'COMPLETED',
        'retryCount': 0,
        'amountFils': 15000,
      },
    );

    expect(operation.amountFils, 15000);
    expect(
      FinancialOperationModel.fromData(
        operationId: operation.operationId,
        data: operation.toData(),
      ).toData(),
      operation.toData(),
    );
  });

  test('rejects mismatched and missing operation targets', () {
    expect(
      () => FinancialOperationModel.fromData(
        operationId: 'op-1',
        data: {
          'type': 'CREATE_MANUAL_WITHDRAWAL',
          'withdrawalId': 'withdrawal-1',
          'depositId': 'deposit-1',
          'createdBy': 'user-1',
          'createdAt': createdAt,
          'status': 'COMPLETED',
          'retryCount': 0,
        },
      ),
      throwsArgumentError,
    );
    expect(
      () => FinancialOperationModel.fromData(
        operationId: 'op-1',
        data: {
          'type': 'CREATE_CASH_DEPOSIT',
          'createdBy': 'user-1',
          'createdAt': createdAt,
          'status': 'COMPLETED',
          'retryCount': 0,
        },
      ),
      throwsArgumentError,
    );
  });
}
