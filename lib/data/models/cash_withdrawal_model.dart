import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:mark_aap/data/models/supplier_payment_model.dart';

enum CashWithdrawalType {
  purchaseInvoice('PURCHASE_INVOICE'),
  personalExpense('PERSONAL_EXPENSE'),
  employeePayment('EMPLOYEE_PAYMENT'),
  billPayment('BILL_PAYMENT'),
  electricity('ELECTRICITY'),
  shopExpense('SHOP_EXPENSE'),
  other('OTHER');

  const CashWithdrawalType(this.value);

  final String value;

  static CashWithdrawalType fromValue(String value) {
    return switch (value) {
      'PURCHASE_INVOICE' => CashWithdrawalType.purchaseInvoice,
      'PERSONAL_EXPENSE' => CashWithdrawalType.personalExpense,
      'EMPLOYEE_PAYMENT' => CashWithdrawalType.employeePayment,
      'BILL_PAYMENT' => CashWithdrawalType.billPayment,
      'ELECTRICITY' => CashWithdrawalType.electricity,
      'SHOP_EXPENSE' => CashWithdrawalType.shopExpense,
      'OTHER' => CashWithdrawalType.other,
      _ => throw FormatException('Unknown cash withdrawal type: $value'),
    };
  }
}

enum CashWithdrawalStatus {
  active('ACTIVE'),
  cancelled('CANCELLED');

  const CashWithdrawalStatus(this.value);

  final String value;

  static CashWithdrawalStatus fromValue(String value) {
    return switch (value) {
      'ACTIVE' => CashWithdrawalStatus.active,
      'CANCELLED' => CashWithdrawalStatus.cancelled,
      _ => throw FormatException('Unknown cash withdrawal status: $value'),
    };
  }
}

class CashWithdrawalModel {
  CashWithdrawalModel({
    required this.withdrawalId,
    required this.amountFils,
    required this.type,
    this.source = SupplierPaymentSource.shopCash,
    required this.createdAt,
    required this.createdBy,
    required this.status,
    this.invoiceId,
    this.supplierPaymentId,
    this.note,
    this.operationId,
    this.cancelledAt,
    this.cancelledBy,
    this.cancellationReason,
    this.cancellationOperationId,
  }) {
    _requireId(withdrawalId, 'withdrawalId');
    _requirePositive(amountFils, 'amountFils');
    _requireId(createdBy, 'createdBy');

    // --- Automatic (PURCHASE_INVOICE) validation ---
    if (type == CashWithdrawalType.purchaseInvoice) {
      // Either invoiceId or supplierPaymentId must be set for automatic withdrawals
      if (invoiceId == null && supplierPaymentId == null) {
        throw ArgumentError(
            'PURCHASE_INVOICE type requires invoiceId or supplierPaymentId.');
      }
      // Enforce automatic ID format
      if (invoiceId != null) {
        if (withdrawalId != 'invoice_$invoiceId') {
          throw ArgumentError(
              'PURCHASE_INVOICE automatic withdrawal ID must be invoice_$invoiceId.');
        }
      }
      if (supplierPaymentId != null) {
        if (withdrawalId != 'supplierPayment_$supplierPaymentId') {
          throw ArgumentError(
              'PURCHASE_INVOICE automatic withdrawal ID must be supplierPayment_$supplierPaymentId.');
        }
      }
      // Cannot have both invoiceId and supplierPaymentId
      if (invoiceId != null && supplierPaymentId != null) {
        throw ArgumentError(
            'PURCHASE_INVOICE type cannot have both invoiceId and supplierPaymentId.');
      }
    }

    // --- Manual withdrawal validation ---
    if (type != CashWithdrawalType.purchaseInvoice) {
      // Manual withdrawals must NOT have invoiceId or supplierPaymentId
      if (invoiceId != null) {
        throw ArgumentError(
            'Manual withdrawal type cannot have invoiceId.');
      }
      if (supplierPaymentId != null) {
        throw ArgumentError(
            'Manual withdrawal type cannot have supplierPaymentId.');
      }
      // Manual withdrawals require source == SHOP_CASH
      if (source != SupplierPaymentSource.shopCash) {
        throw ArgumentError(
            'Manual withdrawal source must be SHOP_CASH.');
      }
      // Manual ID does not use automatic prefixes - just validate it's a non-empty ID
      _requireId(withdrawalId, 'withdrawalId');
    }

    _validateCancellation(
      status: status,
      cancelledAt: cancelledAt,
      cancelledBy: cancelledBy,
      cancellationReason: cancellationReason,
      cancellationOperationId: cancellationOperationId,
    );
  }

  final String withdrawalId;
  final int amountFils;
  final CashWithdrawalType type;
  final SupplierPaymentSource source;
  final String? invoiceId;
  final String? supplierPaymentId;
  final String? note;
  final Timestamp createdAt;
  final String createdBy;
  final CashWithdrawalStatus status;

  /// Manual withdrawals carry the CREATE_MANUAL_WITHDRAWAL operation that was
  /// written in the same transaction; automatic ones are linked through their
  /// invoice or supplier payment instead.
  final String? operationId;

  /// Cancellation metadata, set together when an admin cancelled the
  /// withdrawal (the Firestore rules require the complete set).
  final Timestamp? cancelledAt;
  final String? cancelledBy;
  final String? cancellationReason;
  final String? cancellationOperationId;

  factory CashWithdrawalModel.fromDocument(
    DocumentSnapshot<Map<String, dynamic>> document,
  ) {
    final data = document.data();
    if (data == null) {
      throw StateError('Cash withdrawal document is empty.');
    }
    return CashWithdrawalModel.fromData(
      withdrawalId: document.id,
      data: data,
    );
  }

  factory CashWithdrawalModel.fromData({
    required String withdrawalId,
    required Map<String, dynamic> data,
  }) =>
      CashWithdrawalModel(
        withdrawalId: withdrawalId,
        amountFils: _requiredInt(data, 'amountFils'),
        type: CashWithdrawalType.fromValue(_requiredString(data, 'type')),
        // Automatic (PURCHASE_INVOICE) withdrawal documents are written by the
        // Firestore rules with an EXACT key set that forbids a `source` field
        // (see validInvoiceWithdrawalCreate / validSupplierPaymentWithdrawalCreate).
        // Fall back to the shop-cash default when the key is absent so those
        // documents can still be read back. Manual withdrawals always store it.
        source: data['source'] is String
            ? SupplierPaymentSource.fromValue(data['source'] as String)
            : SupplierPaymentSource.shopCash,
        invoiceId: _optionalString(data, 'invoiceId'),
        supplierPaymentId: _optionalString(data, 'supplierPaymentId'),
        note: _optionalString(data, 'note'),
        createdAt: _requiredTimestamp(data, 'createdAt'),
        createdBy: _requiredString(data, 'createdBy'),
        status: CashWithdrawalStatus.fromValue(_requiredString(data, 'status')),
        operationId: _optionalString(data, 'operationId'),
        cancelledAt: _optionalTimestamp(data, 'cancelledAt'),
        cancelledBy: _optionalString(data, 'cancelledBy'),
        cancellationReason: _optionalString(data, 'cancellationReason'),
        cancellationOperationId:
            _optionalString(data, 'cancellationOperationId'),
      );

  Map<String, dynamic> toData() => {
        'amountFils': amountFils,
        'type': type.value,
        'source': source.value,
        if (invoiceId != null) 'invoiceId': invoiceId,
        if (supplierPaymentId != null) 'supplierPaymentId': supplierPaymentId,
        if (note != null) 'note': note,
        'createdAt': createdAt,
        'createdBy': createdBy,
        'status': status.value,
        if (operationId != null) 'operationId': operationId,
        if (cancelledAt != null) 'cancelledAt': cancelledAt,
        if (cancelledBy != null) 'cancelledBy': cancelledBy,
        if (cancellationReason != null)
          'cancellationReason': cancellationReason,
        if (cancellationOperationId != null)
          'cancellationOperationId': cancellationOperationId,
      };
}

String _requiredString(Map<String, dynamic> data, String key) {
  final value = data[key];
  if (value is! String) throw FormatException('Cash withdrawal $key must be a string.');
  return value;
}

String? _optionalString(Map<String, dynamic> data, String key) {
  final value = data[key];
  if (value != null && value is! String) {
    throw FormatException('Cash withdrawal $key must be a string.');
  }
  return value as String?;
}

int _requiredInt(Map<String, dynamic> data, String key) {
  final value = data[key];
  if (value is! int) throw FormatException('Cash withdrawal $key must be an integer.');
  return value;
}

Timestamp _requiredTimestamp(Map<String, dynamic> data, String key) {
  final value = data[key];
  if (value is! Timestamp) {
    throw FormatException('Cash withdrawal $key must be a Timestamp.');
  }
  return value;
}

Timestamp? _optionalTimestamp(Map<String, dynamic> data, String key) {
  final value = data[key];
  if (value != null && value is! Timestamp) {
    throw FormatException('Cash withdrawal $key must be a Timestamp.');
  }
  return value as Timestamp?;
}

// Mirrors the Firestore rules for a cancelled withdrawal
// (see validManualWithdrawalCancel): cancellation data is only allowed
// together with the CANCELLED status, and a cancelled document must carry
// the complete set. The same shape as PurchaseInvoiceModel._validateCancellation.
void _validateCancellation({
  required CashWithdrawalStatus status,
  required Timestamp? cancelledAt,
  required String? cancelledBy,
  required String? cancellationReason,
  required String? cancellationOperationId,
}) {
  final values = [
    cancelledAt,
    cancelledBy,
    cancellationReason,
    cancellationOperationId,
  ];
  if (status == CashWithdrawalStatus.active) {
    if (values.any((value) => value != null)) {
      throw ArgumentError(
          'Active cash withdrawals cannot contain cancellation data.');
    }
    return;
  }
  if (values.any((value) => value == null)) {
    throw ArgumentError(
        'Cancelled cash withdrawals require complete cancellation data.');
  }
  _requireId(cancelledBy!, 'cancelledBy');
  _requireId(cancellationOperationId!, 'cancellationOperationId');
  _requireCancellationReason(cancellationReason!, 'cancellationReason');
}

void _requireCancellationReason(String value, String field) {
  if (value != value.trim() || value.isEmpty || value.length > 500) {
    throw ArgumentError.value(
        value, field, 'Must be trimmed, non-empty and <= 500 characters.');
  }
}

void _requireId(String value, String field) {
  if (value.trim().isEmpty || value != value.trim()) {
    throw ArgumentError.value(value, field, 'Must be a non-empty trimmed ID.');
  }
}

void _requirePositive(int value, String field) {
  if (value <= 0) throw ArgumentError.value(value, field, 'Must be positive.');
}