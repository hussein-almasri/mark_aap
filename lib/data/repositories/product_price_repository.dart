import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/price_history_model.dart';
import '../models/product_cost_model.dart';
import '../models/product_selling_price_model.dart';
import 'product_repository.dart';

class ProductPriceRepository {
  ProductPriceRepository({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> _sellingPrices(String storeId) =>
      _firestore
          .collection('stores')
          .doc(storeId)
          .collection('productSellingPrices');

  CollectionReference<Map<String, dynamic>> _productCosts(String storeId) =>
      _firestore.collection('stores').doc(storeId).collection('productCosts');

  CollectionReference<Map<String, dynamic>> _history(String storeId) =>
      _firestore.collection('stores').doc(storeId).collection('priceHistory');

  Future<ProductSellingPriceModel> getSellingPrice({
    required String storeId,
    required String productId,
  }) async {
    final document = await _sellingPrices(storeId).doc(productId).get();
    if (!document.exists) {
      throw StateError('Selling price not found.');
    }
    return ProductSellingPriceModel.fromDocument(document);
  }

  Future<ProductCostModel> getProductCost({
    required String storeId,
    required String productId,
  }) async {
    final document = await _productCosts(storeId).doc(productId).get();
    if (!document.exists) {
      throw StateError('Purchase cost not found.');
    }
    return ProductCostModel.fromDocument(document);
  }

  Future<List<PriceHistoryModel>> getPriceHistory({
    required String storeId,
    required String productId,
  }) async {
    final snapshot = await _history(
      storeId,
    ).where('productId', isEqualTo: productId).get();
    final history = snapshot.docs.map(PriceHistoryModel.fromDocument).toList();
    history.sort((left, right) {
      final leftMillis = left.createdAt?.millisecondsSinceEpoch ?? 0;
      final rightMillis = right.createdAt?.millisecondsSinceEpoch ?? 0;
      return rightMillis.compareTo(leftMillis);
    });
    return history;
  }

  Future<bool> changePurchasePrice({
    required String storeId,
    required String productId,
    required String userId,
    required int purchasePrice,
  }) async {
    if (purchasePrice < 0) {
      throw const FormatException('Purchase price cannot be negative.');
    }

    final costRef = _productCosts(storeId).doc(productId);
    return _firestore.runTransaction((transaction) async {
      final costDocument = await transaction.get(costRef);
      if (!costDocument.exists) {
        throw StateError('Purchase cost not found.');
      }
      final cost = ProductCostModel.fromDocument(costDocument);
      if (cost.purchasePrice == purchasePrice) {
        return false;
      }

      final revision = cost.revision + 1;
      final historyRef = _history(storeId).doc(
        ProductRepository.historyId(
          productId,
          ProductPriceType.purchase,
          revision,
        ),
      );
      final existingHistory = await transaction.get(historyRef);
      if (existingHistory.exists) {
        throw StateError('Purchase price history revision already exists.');
      }

      final timestamp = FieldValue.serverTimestamp();
      transaction.update(costRef, {
        'purchasePrice': purchasePrice,
        'revision': revision,
        'updatedAt': timestamp,
        'updatedBy': userId,
      });
      transaction.set(historyRef, {
        'productId': productId,
        'priceType': ProductPriceType.purchase.value,
        'price': purchasePrice,
        'revision': revision,
        'createdBy': userId,
        'createdAt': timestamp,
      });
      return true;
    });
  }

  Future<bool> changeSellingPrice({
    required String storeId,
    required String productId,
    required String userId,
    required int sellingPrice,
  }) async {
    if (sellingPrice <= 0) {
      throw const FormatException('Selling price must be greater than zero.');
    }

    final sellingRef = _sellingPrices(storeId).doc(productId);
    return _firestore.runTransaction((transaction) async {
      final sellingDocument = await transaction.get(sellingRef);
      if (!sellingDocument.exists) {
        throw StateError('Selling price not found.');
      }
      final selling = ProductSellingPriceModel.fromDocument(sellingDocument);
      if (selling.sellingPrice == sellingPrice) {
        return false;
      }

      final revision = selling.revision + 1;
      final historyRef = _history(storeId).doc(
        ProductRepository.historyId(
          productId,
          ProductPriceType.selling,
          revision,
        ),
      );
      final existingHistory = await transaction.get(historyRef);
      if (existingHistory.exists) {
        throw StateError('Selling price history revision already exists.');
      }

      final timestamp = FieldValue.serverTimestamp();
      transaction.update(sellingRef, {
        'sellingPrice': sellingPrice,
        'revision': revision,
        'updatedAt': timestamp,
        'updatedBy': userId,
      });
      transaction.set(historyRef, {
        'productId': productId,
        'priceType': ProductPriceType.selling.value,
        'price': sellingPrice,
        'revision': revision,
        'createdBy': userId,
        'createdAt': timestamp,
      });
      return true;
    });
  }
}
