import 'package:cloud_firestore/cloud_firestore.dart';

class ProductModel {
  const ProductModel({
    required this.id,
    required this.name,
    required this.barcode,
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String name;
  final String barcode;
  final Timestamp? createdAt;
  final Timestamp? updatedAt;

  factory ProductModel.fromDocument(
    DocumentSnapshot<Map<String, dynamic>> document,
  ) {
    final data = document.data();
    if (data == null) {
      throw StateError('Product document is empty.');
    }

    return ProductModel(
      id: document.id,
      name: data['name'] as String? ?? '',
      barcode: data['barcode'] as String? ?? '',
      createdAt: data['createdAt'] as Timestamp?,
      updatedAt: data['updatedAt'] as Timestamp?,
    );
  }
}
