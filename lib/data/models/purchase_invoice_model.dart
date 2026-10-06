import 'package:cloud_firestore/cloud_firestore.dart';

enum PurchaseInvoiceStatus {
  active('ACTIVE'),
  cancelled('CANCELLED');

  const PurchaseInvoiceStatus(this.value);

  final String value;

  static PurchaseInvoiceStatus fromValue(String value) {
    return switch (value) {
      'ACTIVE' => PurchaseInvoiceStatus.active,
      'CANCELLED' => PurchaseInvoiceStatus.cancelled,
      _ => throw FormatException('Unknown purchase invoice status: $value'),
    };
  }
}

class PurchaseInvoiceModel {
  PurchaseInvoiceModel({
    required this.invoiceId,
    required this.companyId,
    required this.companyName,
    required this.totalAmountFils,
    required this.shopCashAmountFils,
    required this.outsideCashAmountFils,
    required this.supplierDebtAmountFils,
    required this.status,
    required this.createdAt,
    required this.createdBy,
    required this.operationId,
    required List<String> photoIds,
    this.supplierInvoiceNumber,
    this.notes,
    this.cancelledAt,
    this.cancelledBy,
    this.cancellationReason,
    this.cancellationOperationId,
  }) : photoIds = List.unmodifiable(photoIds) {
    _requireId(invoiceId, 'invoiceId');
    _requireId(companyId, 'companyId');
    _requireText(companyName, 'companyName');
    _requirePositive(totalAmountFils, 'totalAmountFils');
    _requireNonNegative(shopCashAmountFils, 'shopCashAmountFils');
    _requireNonNegative(outsideCashAmountFils, 'outsideCashAmountFils');
    _requireNonNegative(supplierDebtAmountFils, 'supplierDebtAmountFils');
    if (shopCashAmountFils + outsideCashAmountFils + supplierDebtAmountFils !=
        totalAmountFils) {
      throw ArgumentError('Invoice payment components must equal its total.');
    }
    _requireId(createdBy, 'createdBy');
    _requireId(operationId, 'operationId');
    if (operationId != invoiceId) {
      throw ArgumentError('Purchase invoice operationId must equal invoiceId.');
    }
    _requireOptionalText(supplierInvoiceNumber, 'supplierInvoiceNumber', 100);
    _requireOptionalText(notes, 'notes', 500);
    if (this.photoIds.length > 3 ||
        this.photoIds.toSet().length != this.photoIds.length ||
        this.photoIds.any((id) => id.trim().isEmpty)) {
      throw ArgumentError('Invoice photoIds must be unique non-empty IDs (max 3).');
    }
    _validateCancellation(
      status: status,
      cancelledAt: cancelledAt,
      cancelledBy: cancelledBy,
      cancellationReason: cancellationReason,
      cancellationOperationId: cancellationOperationId,
    );
  }

  final String invoiceId;
  final String companyId;
  final String companyName;
  final String? supplierInvoiceNumber;
  final int totalAmountFils;
  final int shopCashAmountFils;
  final int outsideCashAmountFils;
  final int supplierDebtAmountFils;
  final String? notes;
  final PurchaseInvoiceStatus status;
  final Timestamp createdAt;
  final String createdBy;
  final String operationId;
  final List<String> photoIds;
  final Timestamp? cancelledAt;
  final String? cancelledBy;
  final String? cancellationReason;
  final String? cancellationOperationId;

  factory PurchaseInvoiceModel.fromDocument(
    DocumentSnapshot<Map<String, dynamic>> document,
  ) {
    final data = document.data();
    if (data == null) {
      throw StateError('Purchase invoice document is empty.');
    }
    return PurchaseInvoiceModel.fromData(invoiceId: document.id, data: data);
  }

  factory PurchaseInvoiceModel.fromData({
    required String invoiceId,
    required Map<String, dynamic> data,
  }) {
    final rawPhotoIds = data['photoIds'];
    if (rawPhotoIds is! List || rawPhotoIds.any((value) => value is! String)) {
      throw FormatException('Purchase invoice photoIds must be a string list.');
    }
    return PurchaseInvoiceModel(
      invoiceId: invoiceId,
      companyId: _requiredString(data, 'companyId'),
      companyName: _requiredString(data, 'companyName'),
      supplierInvoiceNumber: _optionalString(data, 'supplierInvoiceNumber'),
      totalAmountFils: _requiredInt(data, 'totalAmountFils'),
      shopCashAmountFils: _requiredInt(data, 'shopCashAmountFils'),
      outsideCashAmountFils: _requiredInt(data, 'outsideCashAmountFils'),
      supplierDebtAmountFils: _requiredInt(data, 'supplierDebtAmountFils'),
      notes: _optionalString(data, 'notes'),
      status: PurchaseInvoiceStatus.fromValue(_requiredString(data, 'status')),
      createdAt: _requiredTimestamp(data, 'createdAt'),
      createdBy: _requiredString(data, 'createdBy'),
      operationId: _requiredString(data, 'operationId'),
      photoIds: List<String>.from(rawPhotoIds),
      cancelledAt: _optionalTimestamp(data, 'cancelledAt'),
      cancelledBy: _optionalString(data, 'cancelledBy'),
      cancellationReason: _optionalString(data, 'cancellationReason'),
      cancellationOperationId:
          _optionalString(data, 'cancellationOperationId'),
    );
  }

  Map<String, dynamic> toData() => {
        'companyId': companyId,
        'companyName': companyName,
        if (supplierInvoiceNumber != null)
          'supplierInvoiceNumber': supplierInvoiceNumber,
        'totalAmountFils': totalAmountFils,
        'shopCashAmountFils': shopCashAmountFils,
        'outsideCashAmountFils': outsideCashAmountFils,
        'supplierDebtAmountFils': supplierDebtAmountFils,
        if (notes != null) 'notes': notes,
        'status': status.value,
        'createdAt': createdAt,
        'createdBy': createdBy,
        'operationId': operationId,
        'photoIds': photoIds,
        if (cancelledAt != null) 'cancelledAt': cancelledAt,
        if (cancelledBy != null) 'cancelledBy': cancelledBy,
        if (cancellationReason != null)
          'cancellationReason': cancellationReason,
        if (cancellationOperationId != null)
          'cancellationOperationId': cancellationOperationId,
      };
}

void _validateCancellation({
  required PurchaseInvoiceStatus status,
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
  if (status == PurchaseInvoiceStatus.active) {
    if (values.any((value) => value != null)) {
      throw ArgumentError('Active invoices cannot contain cancellation data.');
    }
    return;
  }
  if (values.any((value) => value == null)) {
    throw ArgumentError('Cancelled invoices require complete cancellation data.');
  }
  _requireId(cancelledBy!, 'cancelledBy');
  _requireId(cancellationOperationId!, 'cancellationOperationId');
  _requireOptionalText(cancellationReason, 'cancellationReason', 500);
}

String _requiredString(Map<String, dynamic> data, String key) {
  final value = data[key];
  if (value is! String) {
    throw FormatException('Purchase invoice $key must be a string.');
  }
  return value;
}

String? _optionalString(Map<String, dynamic> data, String key) {
  final value = data[key];
  if (value != null && value is! String) {
    throw FormatException('Purchase invoice $key must be a string.');
  }
  return value as String?;
}

int _requiredInt(Map<String, dynamic> data, String key) {
  final value = data[key];
  if (value is! int) {
    throw FormatException('Purchase invoice $key must be an integer.');
  }
  return value;
}

Timestamp _requiredTimestamp(Map<String, dynamic> data, String key) {
  final value = data[key];
  if (value is! Timestamp) {
    throw FormatException('Purchase invoice $key must be a Timestamp.');
  }
  return value;
}

Timestamp? _optionalTimestamp(Map<String, dynamic> data, String key) {
  final value = data[key];
  if (value != null && value is! Timestamp) {
    throw FormatException('Purchase invoice $key must be a Timestamp.');
  }
  return value as Timestamp?;
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

void _requireOptionalText(String? value, String field, int maxLength) {
  if (value == null) return;
  if (value != value.trim() || value.length > maxLength) {
    throw ArgumentError.value(value, field, 'Must be trimmed and <= $maxLength characters.');
  }
  if (field == 'cancellationReason' && value.isEmpty) {
    throw ArgumentError.value(value, field, 'Must not be empty.');
  }
}

void _requirePositive(int value, String field) {
  if (value <= 0) {
    throw ArgumentError.value(value, field, 'Must be greater than zero.');
  }
}

void _requireNonNegative(int value, String field) {
  if (value < 0) {
    throw ArgumentError.value(value, field, 'Must not be negative.');
  }
}
