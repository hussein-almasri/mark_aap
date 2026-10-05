import 'package:cloud_firestore/cloud_firestore.dart';

class CompanyModel {
  const CompanyModel({
    required this.companyId,
    required this.name,
    required this.isActive,
    this.phone,
    this.createdAt,
    this.updatedAt,
  });

  final String companyId;
  final String name;
  final String? phone;
  final bool isActive;
  final Timestamp? createdAt;
  final Timestamp? updatedAt;

  factory CompanyModel.fromDocument(
    DocumentSnapshot<Map<String, dynamic>> document,
  ) {
    final data = document.data();
    if (data == null) {
      throw StateError('Company document is empty.');
    }

    final name = data['name'];
    final isActive = data['isActive'];
    final phone = data['phone'];
    if (name is! String ||
        isActive is! bool ||
        (phone != null && phone is! String)) {
      throw StateError('Company document has invalid fields.');
    }

    return CompanyModel(
      companyId: document.id,
      name: name,
      phone: phone as String?,
      isActive: isActive,
      createdAt: data['createdAt'] as Timestamp?,
      updatedAt: data['updatedAt'] as Timestamp?,
    );
  }
}
