import 'package:cloud_firestore/cloud_firestore.dart';

class ProductSellingPriceModel {
  const ProductSellingPriceModel({
    required this.productId,
    required this.sellingPrice,
    required this.revision,
    required this.updatedBy,
    this.updatedAt,
  });

  final String productId;
  final int sellingPrice;
  final int revision;
  final String updatedBy;
  final Timestamp? updatedAt;

  factory ProductSellingPriceModel.fromDocument(
    DocumentSnapshot<Map<String, dynamic>> document,
  ) {
    final data = document.data();
    if (data == null) {
      throw StateError('Selling price document is empty.');
    }

    return ProductSellingPriceModel(
      productId: document.id,
      sellingPrice: data['sellingPrice'] as int? ?? 0,
      revision: data['revision'] as int? ?? 0,
      updatedBy: data['updatedBy'] as String? ?? '',
      updatedAt: data['updatedAt'] as Timestamp?,
    );
  }
}
