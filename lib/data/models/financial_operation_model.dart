import 'package:cloud_firestore/cloud_firestore.dart';

enum FinancialOperationType {
  createPurchaseInvoice('CREATE_PURCHASE_INVOICE'),
  createSupplierPayment('CREATE_SUPPLIER_PAYMENT'),
  cancelPurchaseInvoice('CANCEL_PURCHASE_INVOICE'),
  cancelSupplierPayment('CANCEL_SUPPLIER_PAYMENT');

  const FinancialOperationType(this.value);

  final String value;

  static FinancialOperationType fromValue(String value) {
    return switch (value) {
      'CREATE_PURCHASE_INVOICE' => FinancialOperationType.createPurchaseInvoice,
      'CREATE_SUPPLIER_PAYMENT' => FinancialOperationType.createSupplierPayment,
      'CANCEL_PURCHASE_INVOICE' => FinancialOperationType.cancelPurchaseInvoice,
      'CANCEL_SUPPLIER_PAYMENT' => FinancialOperationType.cancelSupplierPayment,
      _ => throw FormatException('Unknown financial operation type: $value'),
    };
  }
}

enum FinancialOperationStatus {
  processing('PROCESSING'),
  completed('COMPLETED'),
  failed('FAILED');

  const FinancialOperationStatus(this.value);

  final String value;

  static FinancialOperationStatus fromValue(String value) {
    return switch (value) {
      'PROCESSING' => FinancialOperationStatus.processing,
      'COMPLETED' => FinancialOperationStatus.completed,
      'FAILED' => FinancialOperationStatus.failed,
      _ => throw FormatException('Unknown financial operation status: $value'),
    };
  }
}

class FinancialOperationModel {
  FinancialOperationModel({
    required this.operationId,
    required this.type,
    required this.createdBy,
    required this.createdAt,
    required this.status,
    required this.retryCount,
    this.invoiceId,
    this.paymentId,
    List<String>? photoIds,
  }) : photoIds = photoIds == null ? null : List.unmodifiable(photoIds) {
    _requireId(operationId, 'operationId');
    _requireId(createdBy, 'createdBy');
    if (retryCount < 0 || retryCount > 3) {
      throw ArgumentError.value(retryCount, 'retryCount', 'Must be between 0 and 3.');
    }
    _validatePayload();
  }

  final String operationId;
  final FinancialOperationType type;
  final String createdBy;
  final Timestamp createdAt;
  final FinancialOperationStatus status;
  final int retryCount;
  final String? invoiceId;
  final String? paymentId;
  final List<String>? photoIds;

  factory FinancialOperationModel.fromDocument(
    DocumentSnapshot<Map<String, dynamic>> document,
  ) {
    final data = document.data();
    if (data == null) {
      throw StateError('Financial operation document is empty.');
    }
    return FinancialOperationModel.fromData(
      operationId: document.id,
      data: data,
    );
  }

  factory FinancialOperationModel.fromData({
    required String operationId,
    required Map<String, dynamic> data,
  }) {
    final rawPhotoIds = data['photoIds'];
    if (rawPhotoIds != null &&
        (rawPhotoIds is! List || rawPhotoIds.any((value) => value is! String))) {
      throw FormatException('Financial operation photoIds must be a string list.');
    }
    return FinancialOperationModel(
      operationId: operationId,
      type: FinancialOperationType.fromValue(_requiredString(data, 'type')),
      createdBy: _requiredString(data, 'createdBy'),
      createdAt: _requiredTimestamp(data, 'createdAt'),
      status: FinancialOperationStatus.fromValue(
        _requiredString(data, 'status'),
      ),
      retryCount: _requiredInt(data, 'retryCount'),
      invoiceId: _optionalString(data, 'invoiceId'),
      paymentId: _optionalString(data, 'paymentId'),
      photoIds: rawPhotoIds == null ? null : List<String>.from(rawPhotoIds),
    );
  }

  Map<String, dynamic> toData() => {
        'operationId': operationId,
        'type': type.value,
        'createdBy': createdBy,
        'createdAt': createdAt,
        'status': status.value,
        'retryCount': retryCount,
        if (invoiceId != null) 'invoiceId': invoiceId,
        if (paymentId != null) 'paymentId': paymentId,
        if (photoIds != null) 'photoIds': photoIds,
      };

  void _validatePayload() {
    final isInvoiceOperation = type == FinancialOperationType.createPurchaseInvoice ||
        type == FinancialOperationType.cancelPurchaseInvoice;
    if (isInvoiceOperation) {
      if (invoiceId == null || paymentId != null) {
        throw ArgumentError('Invoice operations require invoiceId only.');
      }
      _requireId(invoiceId!, 'invoiceId');
      if (type == FinancialOperationType.createPurchaseInvoice &&
          invoiceId != operationId) {
        throw ArgumentError('Invoice creation operationId must equal invoiceId.');
      }
      if (type == FinancialOperationType.cancelPurchaseInvoice &&
          photoIds != null) {
        throw ArgumentError('Invoice cancellation operations cannot include photoIds.');
      }
      if (photoIds != null &&
          (photoIds!.length > 3 ||
              photoIds!.toSet().length != photoIds!.length ||
              photoIds!.any((id) => id.trim().isEmpty))) {
        throw ArgumentError('Invoice operation photoIds must be unique IDs (max 3).');
      }
      return;
    }
    if (paymentId == null || invoiceId != null || photoIds != null) {
      throw ArgumentError('Payment operations require paymentId only.');
    }
    _requireId(paymentId!, 'paymentId');
    if (type == FinancialOperationType.createSupplierPayment &&
        paymentId != operationId) {
      throw ArgumentError('Payment creation operationId must equal paymentId.');
    }
  }
}

String _requiredString(Map<String, dynamic> data, String key) {
  final value = data[key];
  if (value is! String) {
    throw FormatException('Financial operation $key must be a string.');
  }
  return value;
}

String? _optionalString(Map<String, dynamic> data, String key) {
  final value = data[key];
  if (value != null && value is! String) {
    throw FormatException('Financial operation $key must be a string.');
  }
  return value as String?;
}

int _requiredInt(Map<String, dynamic> data, String key) {
  final value = data[key];
  if (value is! int) {
    throw FormatException('Financial operation $key must be an integer.');
  }
  return value;
}

Timestamp _requiredTimestamp(Map<String, dynamic> data, String key) {
  final value = data[key];
  if (value is! Timestamp) {
    throw FormatException('Financial operation $key must be a Timestamp.');
  }
  return value;
}

void _requireId(String value, String field) {
  if (value.trim().isEmpty || value != value.trim()) {
    throw ArgumentError.value(value, field, 'Must be a non-empty trimmed ID.');
  }
}
