import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mark_aap/data/models/financial_operation_model.dart';
import 'package:mark_aap/features/operations/screens/operations_log_screen.dart';

FinancialOperationLogEntry _entry({
  required String id,
  required FinancialOperationType type,
  required DateTime date,
}) => FinancialOperationLogEntry(
  operation: FinancialOperationModel(
    operationId: id,
    type: type,
    createdBy: 'user-1',
    createdAt: Timestamp.fromDate(date),
    status: FinancialOperationStatus.completed,
    retryCount: 0,
    invoiceId: type == FinancialOperationType.createPurchaseInvoice ? id : null,
    paymentId: type == FinancialOperationType.createSupplierPayment ? id : null,
    cashBoxId: type == FinancialOperationType.setOpeningBalance
        ? 'openingBalance'
        : null,
  ),
);

void main() {
  test('filters inclusively by date and type, newest first', () {
    final oldEntry = _entry(
      id: 'old',
      type: FinancialOperationType.createPurchaseInvoice,
      date: DateTime(2026, 5, 31, 23, 59),
    );
    final firstDayEntry = _entry(
      id: 'first-day',
      type: FinancialOperationType.createPurchaseInvoice,
      date: DateTime(2026, 6, 1, 0, 0),
    );
    final lastDayEntry = _entry(
      id: 'last-day',
      type: FinancialOperationType.createPurchaseInvoice,
      date: DateTime(2026, 6, 3, 23, 59),
    );
    final wrongTypeEntry = _entry(
      id: 'wrong-type',
      type: FinancialOperationType.setOpeningBalance,
      date: DateTime(2026, 6, 2),
    );

    final filtered = filterOperationsLogEntries(
      entries: [oldEntry, firstDayEntry, lastDayEntry, wrongTypeEntry],
      type: FinancialOperationType.createPurchaseInvoice,
      startDate: DateTime(2026, 6, 1, 12),
      endDate: DateTime(2026, 6, 3, 8),
    );

    expect(filtered.map((entry) => entry.operation.operationId), [
      'last-day',
      'first-day',
    ]);
  });
}
