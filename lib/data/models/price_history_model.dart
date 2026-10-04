import 'package:cloud_firestore/cloud_firestore.dart';

enum ProductPriceType {
  purchase('PURCHASE'),
  selling('SELLING');

  const ProductPriceType(this.value);

  final String value;

  static ProductPriceType fromValue(String value) {
    return switch (value) {
      'PURCHASE' => ProductPriceType.purchase,
      'SELLING' => ProductPriceType.selling,
      _ => throw FormatException('Unknown product price type: $value'),
    };
  }
}

class PriceHistoryModel {
  const PriceHistoryModel({
    required this.id,
    required this.productId,
    required this.priceType,
    required this.price,
    required this.revision,
    required this.createdBy,
    this.createdAt,
  });

  final String id;
  final String productId;
  final ProductPriceType priceType;
  final int price;
  final int revision;
  final String createdBy;
  final Timestamp? createdAt;

  factory PriceHistoryModel.fromDocument(
    DocumentSnapshot<Map<String, dynamic>> document,
  ) {
    final data = document.data();
    if (data == null) {
      throw StateError('Price history document is empty.');
    }

    return PriceHistoryModel(
      id: document.id,
      productId: data['productId'] as String? ?? '',
      priceType: ProductPriceType.fromValue(data['priceType'] as String? ?? ''),
      price: data['price'] as int? ?? 0,
      revision: data['revision'] as int? ?? 0,
      createdBy: data['createdBy'] as String? ?? '',
      createdAt: data['createdAt'] as Timestamp?,
    );
  }
}
