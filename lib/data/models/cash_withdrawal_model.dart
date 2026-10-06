import 'package:cloud_firestore/cloud_firestore.dart';

enum CashWithdrawalType {
  purchaseInvoice('PURCHASE_INVOICE');

  const CashWithdrawalType(this.value);

  final String value;

  static CashWithdrawalType fromValue(String value) {
    return switch (value) {
      'PURCHASE_INVOICE' => CashWithdrawalType.purchaseInvoice,
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
    required this.createdAt,
    required this.createdBy,
    required this.status,
    this.invoiceId,
    this.supplierPaymentId,
  }) {
    _requireId(withdrawalId, 'withdrawalId');
    _requirePositive(amountFils, 'amountFils');
    _requireId(createdBy, 'createdBy');
    if ((invoiceId == null) == (supplierPaymentId == null)) {
      throw ArgumentError('Withdrawal must link to exactly one invoice or payment.');
    }
    if (invoiceId != null) {
      _requireId(invoiceId!, 'invoiceId');
      if (withdrawalId != 'invoice_$invoiceId') {
        throw ArgumentError('Invoice withdrawal ID must match its invoice.');
      }
    }
    if (supplierPaymentId != null) {
      _requireId(supplierPaymentId!, 'supplierPaymentId');
      if (withdrawalId != 'supplierPayment_$supplierPaymentId') {
        throw ArgumentError('Payment withdrawal ID must match its payment.');
      }
    }
  }

  final String withdrawalId;
  final int amountFils;
  final CashWithdrawalType type;
  final String? invoiceId;
  final String? supplierPaymentId;
  final Timestamp createdAt;
  final String createdBy;
  final CashWithdrawalStatus status;

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
        invoiceId: _optionalString(data, 'invoiceId'),
        supplierPaymentId: _optionalString(data, 'supplierPaymentId'),
        createdAt: _requiredTimestamp(data, 'createdAt'),
        createdBy: _requiredString(data, 'createdBy'),
        status: CashWithdrawalStatus.fromValue(_requiredString(data, 'status')),
      );

  Map<String, dynamic> toData() => {
        'amountFils': amountFils,
        'type': type.value,
        if (invoiceId != null) 'invoiceId': invoiceId,
        if (supplierPaymentId != null) 'supplierPaymentId': supplierPaymentId,
        'createdAt': createdAt,
        'createdBy': createdBy,
        'status': status.value,
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

void _requireId(String value, String field) {
  if (value.trim().isEmpty || value != value.trim()) {
    throw ArgumentError.value(value, field, 'Must be a non-empty trimmed ID.');
  }
}

void _requirePositive(int value, String field) {
  if (value <= 0) throw ArgumentError.value(value, field, 'Must be positive.');
}
