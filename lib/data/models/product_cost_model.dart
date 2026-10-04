import 'package:cloud_firestore/cloud_firestore.dart';

class ProductCostModel {
  const ProductCostModel({
    required this.productId,
    required this.purchasePrice,
    required this.revision,
    required this.updatedBy,
    this.updatedAt,
  });

  final String productId;
  final int purchasePrice;
  final int revision;
  final String updatedBy;
  final Timestamp? updatedAt;

  factory ProductCostModel.fromDocument(
    DocumentSnapshot<Map<String, dynamic>> document,
  ) {
    final data = document.data();
    if (data == null) {
      throw StateError('Product cost document is empty.');
    }

    return ProductCostModel(
      productId: document.id,
      purchasePrice: data['purchasePrice'] as int? ?? 0,
      revision: data['revision'] as int? ?? 0,
      updatedBy: data['updatedBy'] as String? ?? '',
      updatedAt: data['updatedAt'] as Timestamp?,
    );
  }
}
