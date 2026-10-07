import 'package:cloud_firestore/cloud_firestore.dart';

class CustomerModel {
  CustomerModel({
    required this.customerId,
    required this.name,
    this.phone,
    required this.debtEnabled,
    required this.isActive,
    required this.createdAt,
    required this.updatedAt,
    required this.createdBy,
    required this.updatedBy,
  }) {
    _requireId(customerId, 'customerId');
    _requireNonEmpty(name, 'name');
    _requireTrimmed(name, 'name');
    _requireMaxLength(name, 'name', 120);
    _requireBool(debtEnabled, 'debtEnabled');
    _requireBool(isActive, 'isActive');
    _requireTimestamp(createdAt, 'createdAt');
    _requireTimestamp(updatedAt, 'updatedAt');
    _requireNonEmpty(createdBy, 'createdBy');
    _requireNonEmpty(updatedBy, 'updatedBy');
  }

  final String customerId;
  final String name;
  final String? phone;
  final bool debtEnabled;
  final bool isActive;
  final Timestamp createdAt;
  final Timestamp updatedAt;
  final String createdBy;
  final String updatedBy;

  factory CustomerModel.fromDocument(
    DocumentSnapshot<Map<String, dynamic>> document,
  ) {
    final data = document.data();
    if (data == null) {
      throw StateError('Customer document is empty.');
    }
    return CustomerModel.fromData(
      customerId: document.id,
      data: data,
    );
  }

  factory CustomerModel.fromData({
    required String customerId,
    required Map<String, dynamic> data,
  }) {
    final name = data['name'];
    final phone = data['phone'];
    final debtEnabled = data['debtEnabled'];
    final isActive = data['isActive'];
    final createdAt = data['createdAt'];
    final updatedAt = data['updatedAt'];
    final createdBy = data['createdBy'];
    final updatedBy = data['updatedBy'];

    if (name is! String ||
        debtEnabled is! bool ||
        isActive is! bool ||
        createdAt is! Timestamp ||
        updatedAt is! Timestamp ||
        createdBy is! String ||
        updatedBy is! String) {
      throw StateError('Customer document has invalid fields.');
    }

    return CustomerModel(
      customerId: customerId,
      name: name,
      phone: phone as String?,
      debtEnabled: debtEnabled,
      isActive: isActive,
      createdAt: createdAt as Timestamp,
      updatedAt: updatedAt as Timestamp,
      createdBy: createdBy as String,
      updatedBy: updatedBy as String,
    );
  }

  Map<String, dynamic> toData() => {
        'customerId': customerId,
        'name': name,
        if (phone != null) 'phone': phone,
        'debtEnabled': debtEnabled,
        'isActive': isActive,
        'createdAt': createdAt,
        'updatedAt': updatedAt,
        'createdBy': createdBy,
        'updatedBy': updatedBy,
      };
}

void _requireId(String value, String field) {
  if (value.trim().isEmpty || value.isEmpty) {
    throw ArgumentError.value(value, field, 'Must be non-empty.');
  }
}

void _requireNonEmpty(String value, String field) {
  if (value.trim().isEmpty || value.isEmpty) {
    throw ArgumentError.value(value, field, 'Must be non-empty.');
  }
}

void _requireTrimmed(String value, String field) {
  if (value != value.trim()) {
    throw ArgumentError.value(value, field, 'Must be trimmed.');
  }
}

void _requireMaxLength(String value, String field, int max) {
  if (value.length > max) {
    throw ArgumentError.value(value, field, 'Must not exceed $max characters.');
  }
}

void _requireBool(bool value, String field) {
  if (value != true && value != false) {
    throw ArgumentError.value(value, field, 'Must be a boolean.');
  }
}

void _requireTimestamp(Timestamp value, String field) {
  if (value is! Timestamp) {
    throw ArgumentError.value(value, field, 'Must be a Timestamp.');
  }
}