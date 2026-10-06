import 'package:cloud_firestore/cloud_firestore.dart';

enum SupplierDebtStatus {
  open('OPEN'),
  paid('PAID'),
  cancelled('CANCELLED');

  const SupplierDebtStatus(this.value);

  final String value;

  static SupplierDebtStatus fromValue(String value) {
    return switch (value) {
      'OPEN' => SupplierDebtStatus.open,
      'PAID' => SupplierDebtStatus.paid,
      'CANCELLED' => SupplierDebtStatus.cancelled,
      _ => throw FormatException('Unknown supplier debt status: $value'),
    };
  }
}

class SupplierDebtModel {
  SupplierDebtModel({
    required this.invoiceId,
    required this.companyId,
    required this.companyName,
    required this.originalAmountFils,
    required this.remainingAmountFils,
    required this.status,
    required this.createdAt,
    required this.createdBy,
    required this.operationId,
    required this.lastOperationId,
  }) {
    _requireId(invoiceId, 'invoiceId');
    _requireId(companyId, 'companyId');
    _requireText(companyName, 'companyName');
    _requirePositive(originalAmountFils, 'originalAmountFils');
    _requireNonNegative(remainingAmountFils, 'remainingAmountFils');
    if (remainingAmountFils > originalAmountFils) {
      throw ArgumentError('Debt remainder cannot exceed original amount.');
    }
    if (status == SupplierDebtStatus.open && remainingAmountFils == 0 ||
        status == SupplierDebtStatus.paid && remainingAmountFils != 0) {
      throw ArgumentError('Debt status must match its remaining amount.');
    }
    _requireId(createdBy, 'createdBy');
    _requireId(operationId, 'operationId');
    _requireId(lastOperationId, 'lastOperationId');
  }

  final String invoiceId;
  final String companyId;
  final String companyName;
  final int originalAmountFils;
  final int remainingAmountFils;
  final SupplierDebtStatus status;
  final Timestamp createdAt;
  final String createdBy;
  final String operationId;
  final String lastOperationId;

  factory SupplierDebtModel.fromDocument(
    DocumentSnapshot<Map<String, dynamic>> document,
  ) {
    final data = document.data();
    if (data == null) {
      throw StateError('Supplier debt document is empty.');
    }
    return SupplierDebtModel.fromData(invoiceId: document.id, data: data);
  }

  factory SupplierDebtModel.fromData({
    required String invoiceId,
    required Map<String, dynamic> data,
  }) =>
      SupplierDebtModel(
        invoiceId: _requiredString(data, 'invoiceId'),
        companyId: _requiredString(data, 'companyId'),
        companyName: _requiredString(data, 'companyName'),
        originalAmountFils: _requiredInt(data, 'originalAmountFils'),
        remainingAmountFils: _requiredInt(data, 'remainingAmountFils'),
        status: SupplierDebtStatus.fromValue(_requiredString(data, 'status')),
        createdAt: _requiredTimestamp(data, 'createdAt'),
        createdBy: _requiredString(data, 'createdBy'),
        operationId: _requiredString(data, 'operationId'),
        lastOperationId: _requiredString(data, 'lastOperationId'),
      );

  Map<String, dynamic> toData() => {
        'invoiceId': invoiceId,
        'companyId': companyId,
        'companyName': companyName,
        'originalAmountFils': originalAmountFils,
        'remainingAmountFils': remainingAmountFils,
        'status': status.value,
        'createdAt': createdAt,
        'createdBy': createdBy,
        'operationId': operationId,
        'lastOperationId': lastOperationId,
      };
}

String _requiredString(Map<String, dynamic> data, String key) {
  final value = data[key];
  if (value is! String) throw FormatException('Supplier debt $key must be a string.');
  return value;
}

int _requiredInt(Map<String, dynamic> data, String key) {
  final value = data[key];
  if (value is! int) throw FormatException('Supplier debt $key must be an integer.');
  return value;
}

Timestamp _requiredTimestamp(Map<String, dynamic> data, String key) {
  final value = data[key];
  if (value is! Timestamp) {
    throw FormatException('Supplier debt $key must be a Timestamp.');
  }
  return value;
}

void _requireId(String value, String field) {
  if (value.trim().isEmpty || value != value.trim()) {
    throw ArgumentError.value(value, field, 'Must be a non-empty trimmed ID.');
  }
}

void _requireText(String value, String field) {
  if (value.trim().isEmpty || value != value.trim()) {
    throw ArgumentError.value(value, field, 'Must be non-empty trimmed text.');
  }
}

void _requirePositive(int value, String field) {
  if (value <= 0) throw ArgumentError.value(value, field, 'Must be positive.');
}

void _requireNonNegative(int value, String field) {
  if (value < 0) throw ArgumentError.value(value, field, 'Must not be negative.');
}
