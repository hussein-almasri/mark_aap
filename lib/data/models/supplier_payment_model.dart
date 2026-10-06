import 'package:cloud_firestore/cloud_firestore.dart';

enum SupplierPaymentSource {
  shopCash('SHOP_CASH'),
  outsideCash('OUTSIDE_CASH');

  const SupplierPaymentSource(this.value);

  final String value;

  static SupplierPaymentSource fromValue(String value) {
    return switch (value) {
      'SHOP_CASH' => SupplierPaymentSource.shopCash,
      'OUTSIDE_CASH' => SupplierPaymentSource.outsideCash,
      _ => throw FormatException('Unknown supplier payment source: $value'),
    };
  }
}

enum SupplierPaymentStatus {
  active('ACTIVE'),
  cancelled('CANCELLED');

  const SupplierPaymentStatus(this.value);

  final String value;

  static SupplierPaymentStatus fromValue(String value) {
    return switch (value) {
      'ACTIVE' => SupplierPaymentStatus.active,
      'CANCELLED' => SupplierPaymentStatus.cancelled,
      _ => throw FormatException('Unknown supplier payment status: $value'),
    };
  }
}

class SupplierPaymentModel {
  SupplierPaymentModel({
    required this.paymentId,
    required this.companyId,
    required this.companyName,
    required this.amountFils,
    required this.source,
    required this.status,
    required this.allocationCount,
    required this.allocation1InvoiceId,
    required this.allocation1AmountFils,
    required this.createdAt,
    required this.createdBy,
    required this.operationId,
    this.allocation2InvoiceId,
    this.allocation2AmountFils,
    this.allocation3InvoiceId,
    this.allocation3AmountFils,
    this.allocation4InvoiceId,
    this.allocation4AmountFils,
    this.allocation5InvoiceId,
    this.allocation5AmountFils,
    this.notes,
    this.cancelledAt,
    this.cancelledBy,
    this.cancellationReason,
    this.cancellationOperationId,
  }) {
    _requireId(paymentId, 'paymentId');
    _requireId(companyId, 'companyId');
    _requireText(companyName, 'companyName');
    _requirePositive(amountFils, 'amountFils');
    _requireId(createdBy, 'createdBy');
    _requireId(operationId, 'operationId');
    if (operationId != paymentId) {
      throw ArgumentError('Supplier payment operationId must equal paymentId.');
    }
    _requireOptionalText(notes, 'notes', 500);
    _validateSlots();
    _validateCancellation();
  }

  final String paymentId;
  final String companyId;
  final String companyName;
  final int amountFils;
  final SupplierPaymentSource source;
  final SupplierPaymentStatus status;
  final int allocationCount;
  final String allocation1InvoiceId;
  final int allocation1AmountFils;
  final String? allocation2InvoiceId;
  final int? allocation2AmountFils;
  final String? allocation3InvoiceId;
  final int? allocation3AmountFils;
  final String? allocation4InvoiceId;
  final int? allocation4AmountFils;
  final String? allocation5InvoiceId;
  final int? allocation5AmountFils;
  final Timestamp createdAt;
  final String createdBy;
  final String operationId;
  final String? notes;
  final Timestamp? cancelledAt;
  final String? cancelledBy;
  final String? cancellationReason;
  final String? cancellationOperationId;

  int get allocationTotalFils =>
      allocation1AmountFils +
      (allocation2AmountFils ?? 0) +
      (allocation3AmountFils ?? 0) +
      (allocation4AmountFils ?? 0) +
      (allocation5AmountFils ?? 0);

  factory SupplierPaymentModel.fromDocument(
    DocumentSnapshot<Map<String, dynamic>> document,
  ) {
    final data = document.data();
    if (data == null) {
      throw StateError('Supplier payment document is empty.');
    }
    return SupplierPaymentModel.fromData(paymentId: document.id, data: data);
  }

  factory SupplierPaymentModel.fromData({
    required String paymentId,
    required Map<String, dynamic> data,
  }) =>
      SupplierPaymentModel(
        paymentId: paymentId,
        companyId: _requiredString(data, 'companyId'),
        companyName: _requiredString(data, 'companyName'),
        amountFils: _requiredInt(data, 'amountFils'),
        source: SupplierPaymentSource.fromValue(_requiredString(data, 'source')),
        status: SupplierPaymentStatus.fromValue(_requiredString(data, 'status')),
        allocationCount: _requiredInt(data, 'allocationCount'),
        allocation1InvoiceId:
            _requiredString(data, 'allocation1InvoiceId'),
        allocation1AmountFils:
            _requiredInt(data, 'allocation1AmountFils'),
        allocation2InvoiceId: _optionalString(data, 'allocation2InvoiceId'),
        allocation2AmountFils: _optionalInt(data, 'allocation2AmountFils'),
        allocation3InvoiceId: _optionalString(data, 'allocation3InvoiceId'),
        allocation3AmountFils: _optionalInt(data, 'allocation3AmountFils'),
        allocation4InvoiceId: _optionalString(data, 'allocation4InvoiceId'),
        allocation4AmountFils: _optionalInt(data, 'allocation4AmountFils'),
        allocation5InvoiceId: _optionalString(data, 'allocation5InvoiceId'),
        allocation5AmountFils: _optionalInt(data, 'allocation5AmountFils'),
        createdAt: _requiredTimestamp(data, 'createdAt'),
        createdBy: _requiredString(data, 'createdBy'),
        operationId: _requiredString(data, 'operationId'),
        notes: _optionalString(data, 'notes'),
        cancelledAt: _optionalTimestamp(data, 'cancelledAt'),
        cancelledBy: _optionalString(data, 'cancelledBy'),
        cancellationReason: _optionalString(data, 'cancellationReason'),
        cancellationOperationId:
            _optionalString(data, 'cancellationOperationId'),
      );

  Map<String, dynamic> toData() => {
        'companyId': companyId,
        'companyName': companyName,
        'amountFils': amountFils,
        'source': source.value,
        'status': status.value,
        'allocationCount': allocationCount,
        'allocation1InvoiceId': allocation1InvoiceId,
        'allocation1AmountFils': allocation1AmountFils,
        if (allocation2InvoiceId != null) ...{
          'allocation2InvoiceId': allocation2InvoiceId,
          'allocation2AmountFils': allocation2AmountFils,
        },
        if (allocation3InvoiceId != null) ...{
          'allocation3InvoiceId': allocation3InvoiceId,
          'allocation3AmountFils': allocation3AmountFils,
        },
        if (allocation4InvoiceId != null) ...{
          'allocation4InvoiceId': allocation4InvoiceId,
          'allocation4AmountFils': allocation4AmountFils,
        },
        if (allocation5InvoiceId != null) ...{
          'allocation5InvoiceId': allocation5InvoiceId,
          'allocation5AmountFils': allocation5AmountFils,
        },
        'createdAt': createdAt,
        'createdBy': createdBy,
        'operationId': operationId,
        if (notes != null) 'notes': notes,
        if (cancelledAt != null) 'cancelledAt': cancelledAt,
        if (cancelledBy != null) 'cancelledBy': cancelledBy,
        if (cancellationReason != null)
          'cancellationReason': cancellationReason,
        if (cancellationOperationId != null)
          'cancellationOperationId': cancellationOperationId,
      };

  void _validateSlots() {
    if (allocationCount < 1 || allocationCount > 5) {
      throw ArgumentError.value(allocationCount, 'allocationCount', 'Must be 1..5.');
    }
    final ids = [
      allocation1InvoiceId,
      allocation2InvoiceId,
      allocation3InvoiceId,
      allocation4InvoiceId,
      allocation5InvoiceId,
    ];
    final amounts = [
      allocation1AmountFils,
      allocation2AmountFils,
      allocation3AmountFils,
      allocation4AmountFils,
      allocation5AmountFils,
    ];
    for (var index = 0; index < 5; index++) {
      final isUsed = index < allocationCount;
      final id = ids[index];
      final amount = amounts[index];
      if (isUsed) {
        if (id == null || amount == null) {
          throw ArgumentError('Each counted allocation slot must be complete.');
        }
        _requireId(id, 'allocation${index + 1}InvoiceId');
        _requirePositive(amount, 'allocation${index + 1}AmountFils');
      } else if (id != null || amount != null) {
        throw ArgumentError('Slots beyond allocationCount must be absent.');
      }
    }
    final populatedIds = ids.take(allocationCount).cast<String>().toList();
    if (populatedIds.toSet().length != allocationCount) {
      throw ArgumentError('A supplier payment cannot allocate an invoice twice.');
    }
    if (allocationTotalFils != amountFils) {
      throw ArgumentError('Allocation total must equal payment amountFils.');
    }
  }

  void _validateCancellation() {
    final values = [
      cancelledAt,
      cancelledBy,
      cancellationReason,
      cancellationOperationId,
    ];
    if (status == SupplierPaymentStatus.active) {
      if (values.any((value) => value != null)) {
        throw ArgumentError('Active payments cannot contain cancellation data.');
      }
      return;
    }
    if (values.any((value) => value == null)) {
      throw ArgumentError('Cancelled payments require complete cancellation data.');
    }
    _requireId(cancelledBy!, 'cancelledBy');
    _requireId(cancellationOperationId!, 'cancellationOperationId');
    _requireOptionalText(cancellationReason, 'cancellationReason', 500);
  }
}

String _requiredString(Map<String, dynamic> data, String key) {
  final value = data[key];
  if (value is! String) throw FormatException('Supplier payment $key must be a string.');
  return value;
}

String? _optionalString(Map<String, dynamic> data, String key) {
  final value = data[key];
  if (value != null && value is! String) {
    throw FormatException('Supplier payment $key must be a string.');
  }
  return value as String?;
}

int _requiredInt(Map<String, dynamic> data, String key) {
  final value = data[key];
  if (value is! int) throw FormatException('Supplier payment $key must be an integer.');
  return value;
}

int? _optionalInt(Map<String, dynamic> data, String key) {
  final value = data[key];
  if (value != null && value is! int) {
    throw FormatException('Supplier payment $key must be an integer.');
  }
  return value as int?;
}

Timestamp _requiredTimestamp(Map<String, dynamic> data, String key) {
  final value = data[key];
  if (value is! Timestamp) {
    throw FormatException('Supplier payment $key must be a Timestamp.');
  }
  return value;
}

Timestamp? _optionalTimestamp(Map<String, dynamic> data, String key) {
  final value = data[key];
  if (value != null && value is! Timestamp) {
    throw FormatException('Supplier payment $key must be a Timestamp.');
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
  if (value != value.trim() ||
      value.length > maxLength ||
      (field == 'cancellationReason' && value.isEmpty)) {
    throw ArgumentError.value(value, field, 'Invalid optional text value.');
  }
}

void _requirePositive(int value, String field) {
  if (value <= 0) throw ArgumentError.value(value, field, 'Must be positive.');
}
