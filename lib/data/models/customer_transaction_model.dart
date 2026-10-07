import 'package:cloud_firestore/cloud_firestore.dart';

enum CustomerTransactionType {
  debt('DEBT'),
  payment('PAYMENT');

  const CustomerTransactionType(this.value);

  final String value;

  static CustomerTransactionType fromValue(String value) {
    if (value == 'DEBT') return CustomerTransactionType.debt;
    if (value == 'PAYMENT') return CustomerTransactionType.payment;
    throw FormatException('Unknown customer transaction type: $value');
  }
}

enum CustomerTransactionStatus {
  active('ACTIVE'),
  cancelled('CANCELLED');

  const CustomerTransactionStatus(this.value);

  final String value;

  static CustomerTransactionStatus fromValue(String value) {
    if (value == 'ACTIVE') return CustomerTransactionStatus.active;
    if (value == 'CANCELLED') return CustomerTransactionStatus.cancelled;
    throw FormatException('Unknown customer transaction status: $value');
  }
}

class CustomerTransactionModel {
  CustomerTransactionModel({
    required this.transactionId,
    required this.type,
    required this.amountFils,
    required this.createdAt,
    required this.createdBy,
    required this.status,
    this.note,
    this.cancelledAt,
    this.cancelledBy,
    this.cancellationReason,
  }) {
    _requireId(transactionId, 'transactionId');
    _requirePositive(amountFils, 'amountFils');
    _requireTimestamp(createdAt, 'createdAt');
    _requireNonEmpty(createdBy, 'createdBy');
    _requireValidStatus(status.value, 'status');
  }

  final String transactionId;
  final CustomerTransactionType type;
  final int amountFils;
  final Timestamp createdAt;
  final String createdBy;
  final CustomerTransactionStatus status;
  final String? note;
  final Timestamp? cancelledAt;
  final String? cancelledBy;
  final String? cancellationReason;

  factory CustomerTransactionModel.fromDocument(
    DocumentSnapshot<Map<String, dynamic>> document,
  ) {
    final data = document.data();
    if (data == null) {
      throw StateError('Customer transaction document is empty.');
    }
    return CustomerTransactionModel.fromData(
      transactionId: document.id,
      data: data,
    );
  }

  factory CustomerTransactionModel.fromData({
    required String transactionId,
    required Map<String, dynamic> data,
  }) {
    final type = data['type'];
    final amountFils = data['amountFils'];
    final createdAt = data['createdAt'];
    final createdBy = data['createdBy'];
    final status = data['status'];
    final note = data['note'];
    final cancelledAt = data['cancelledAt'];
    final cancelledBy = data['cancelledBy'];
    final cancellationReason = data['cancellationReason'];

    if (type is! String ||
        amountFils is! int ||
        createdAt is! Timestamp ||
        createdBy is! String ||
        status is! String ||
        (note != null && note is! String)) {
      throw StateError('Customer transaction document has invalid fields.');
    }

    return CustomerTransactionModel(
      transactionId: transactionId,
      type: CustomerTransactionType.fromValue(type),
      amountFils: amountFils as int,
      createdAt: createdAt as Timestamp,
      createdBy: createdBy as String,
      status: CustomerTransactionStatus.fromValue(status),
      note: note as String?,
      cancelledAt: cancelledAt == null ? null : cancelledAt as Timestamp,
      cancelledBy: cancelledBy as String?,
      cancellationReason: cancellationReason as String?,
    );
  }

  Map<String, dynamic> toData() => {
        'transactionId': transactionId,
        'type': type.value,
        'amountFils': amountFils,
        'createdAt': createdAt,
        'createdBy': createdBy,
        'status': status.value,
        if (note != null) 'note': note,
        if (cancelledAt != null) 'cancelledAt': cancelledAt,
        if (cancelledBy != null) 'cancelledBy': cancelledBy,
        if (cancellationReason != null) 'cancellationReason': cancellationReason,
      };
}

void _requireId(String value, String field) {
  if (value.trim().isEmpty || value.isEmpty) {
    throw ArgumentError.value(value, field, 'Must be non-empty.');
  }
}

void _requirePositive(int value, String field) {
  if (value <= 0) {
    throw ArgumentError.value(value, field, 'Must be greater than zero.');
  }
}

void _requireTimestamp(Timestamp value, String field) {
  if (value is! Timestamp) {
    throw ArgumentError.value(value, field, 'Must be a Timestamp.');
  }
}

void _requireNonEmpty(String value, String field) {
  if (value.trim().isEmpty || value.isEmpty) {
    throw ArgumentError.value(value, field, 'Must be non-empty.');
  }
}

void _requireValidStatus(String value, String field) {
  if (value != 'ACTIVE' && value != 'CANCELLED') {
    throw ArgumentError.value(value, field, 'Must be ACTIVE or CANCELLED.');
  }
}