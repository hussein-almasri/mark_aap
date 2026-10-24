import 'package:cloud_firestore/cloud_firestore.dart';

/// Lifecycle of a cash-box deposit. Deposits are immutable money-in records:
/// they are created ACTIVE and the Firestore rules forbid any later update,
/// so no cancellation state exists.
enum CashDepositStatus {
  active('ACTIVE');

  const CashDepositStatus(this.value);

  final String value;

  static CashDepositStatus fromValue(String value) {
    return switch (value) {
      'ACTIVE' => CashDepositStatus.active,
      _ => throw FormatException('Unknown cash deposit status: $value'),
    };
  }
}

/// A cash deposit into the shop cash box. Mirrors the exact document shape
/// written by [CashBoxRepository.createDeposit] and enforced by
/// `validCashDepositCreateAfter` in firestore.rules.
class CashDepositModel {
  CashDepositModel({
    required this.depositId,
    required this.amountFils,
    required this.note,
    required this.createdAt,
    required this.createdBy,
    required this.status,
    required this.operationId,
  }) {
    _requireId(depositId, 'depositId');
    _requirePositive(amountFils, 'amountFils');
    _requireNote(note, 'note');
    _requireId(createdBy, 'createdBy');
    _requireId(operationId, 'operationId');
    if (operationId != depositId) {
      throw ArgumentError.value(
        operationId,
        'operationId',
        'Cash deposit operationId must equal depositId.',
      );
    }
  }

  final String depositId;
  final int amountFils;
  final String note;
  final Timestamp createdAt;
  final String createdBy;
  final CashDepositStatus status;

  /// The CREATE_CASH_DEPOSIT operation written in the same transaction;
  /// equal to [depositId] so a retried operation targets the same document.
  final String operationId;

  factory CashDepositModel.fromDocument(
    DocumentSnapshot<Map<String, dynamic>> document,
  ) {
    final data = document.data();
    if (data == null) {
      throw StateError('Cash deposit document is empty.');
    }
    return CashDepositModel.fromData(
      depositId: document.id,
      data: data,
    );
  }

  factory CashDepositModel.fromData({
    required String depositId,
    required Map<String, dynamic> data,
  }) =>
      CashDepositModel(
        depositId: depositId,
        amountFils: _requiredInt(data, 'amountFils'),
        note: _requiredString(data, 'note'),
        createdAt: _requiredTimestamp(data, 'createdAt'),
        createdBy: _requiredString(data, 'createdBy'),
        status: CashDepositStatus.fromValue(_requiredString(data, 'status')),
        operationId: _requiredString(data, 'operationId'),
      );

  Map<String, dynamic> toData() => {
        'amountFils': amountFils,
        'note': note,
        'createdAt': createdAt,
        'createdBy': createdBy,
        'status': status.value,
        'operationId': operationId,
      };
}

String _requiredString(Map<String, dynamic> data, String key) {
  final value = data[key];
  if (value is! String) {
    throw FormatException('Cash deposit $key must be a string.');
  }
  return value;
}

int _requiredInt(Map<String, dynamic> data, String key) {
  final value = data[key];
  if (value is! int) {
    throw FormatException('Cash deposit $key must be an integer.');
  }
  return value;
}

Timestamp _requiredTimestamp(Map<String, dynamic> data, String key) {
  final value = data[key];
  if (value is! Timestamp) {
    throw FormatException('Cash deposit $key must be a Timestamp.');
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

/// Same contract as the Firestore rules (`validCashReason`): trimmed,
/// non-empty and at most 500 characters.
void _requireNote(String value, String field) {
  if (value.trim().isEmpty || value != value.trim() || value.length > 500) {
    throw ArgumentError.value(
      value,
      field,
      'Must be trimmed, non-empty and at most 500 characters.',
    );
  }
}
