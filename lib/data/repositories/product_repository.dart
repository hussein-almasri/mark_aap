import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/product_model.dart';
import '../models/price_history_model.dart';

enum ProductDuplicateField { name, barcode }

class ProductAlreadyExistsException implements Exception {
  const ProductAlreadyExistsException(this.field);

  final ProductDuplicateField field;
}

class ProductRepository {
  ProductRepository({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> _products(String storeId) =>
      _firestore.collection('stores').doc(storeId).collection('products');

  CollectionReference<Map<String, dynamic>> _nameKeys(String storeId) =>
      _firestore
          .collection('stores')
          .doc(storeId)
          .collection('productNameKeys');

  CollectionReference<Map<String, dynamic>> _barcodeKeys(String storeId) =>
      _firestore
          .collection('stores')
          .doc(storeId)
          .collection('productBarcodeKeys');

  CollectionReference<Map<String, dynamic>> _sellingPrices(String storeId) =>
      _firestore
          .collection('stores')
          .doc(storeId)
          .collection('productSellingPrices');

  CollectionReference<Map<String, dynamic>> _productCosts(String storeId) =>
      _firestore.collection('stores').doc(storeId).collection('productCosts');

  CollectionReference<Map<String, dynamic>> _priceHistory(String storeId) =>
      _firestore.collection('stores').doc(storeId).collection('priceHistory');

  static String normalizeName(String name) => name.trim().toLowerCase();

  static String _base64UrlKey(String prefix, String value) =>
      '$prefix${base64Url.encode(utf8.encode(value)).replaceAll('=', '')}';

  static String nameKey(String name) =>
      _base64UrlKey('n_', normalizeName(name));

  static String barcodeKey(String barcode) =>
      _base64UrlKey('b_', barcode.trim());

  static String historyId(
    String productId,
    ProductPriceType type,
    int revision,
  ) => '${productId}_${type.value}_$revision';

  Future<String> createProduct({
    required String storeId,
    required String userId,
    required String name,
    required String barcode,
    required int purchasePrice,
    required int sellingPrice,
  }) async {
    final cleanName = name.trim();
    final cleanBarcode = barcode.trim();
    _validateFields(
      name: cleanName,
      barcode: cleanBarcode,
      purchasePrice: purchasePrice,
      sellingPrice: sellingPrice,
    );

    final productRef = _products(storeId).doc();
    final nameKeyRef = _nameKeys(storeId).doc(nameKey(cleanName));
    final barcodeKeyRef = _barcodeKeys(storeId).doc(barcodeKey(cleanBarcode));
    final sellingRef = _sellingPrices(storeId).doc(productRef.id);
    final costRef = _productCosts(storeId).doc(productRef.id);
    final sellingHistoryRef = _priceHistory(
      storeId,
    ).doc(historyId(productRef.id, ProductPriceType.selling, 1));
    final purchaseHistoryRef = _priceHistory(
      storeId,
    ).doc(historyId(productRef.id, ProductPriceType.purchase, 1));

    return _firestore.runTransaction((transaction) async {
      final existingProduct = await transaction.get(productRef);
      final existingNameKey = await transaction.get(nameKeyRef);
      final existingBarcodeKey = await transaction.get(barcodeKeyRef);
      if (existingProduct.exists) {
        throw StateError('The generated product ID already exists.');
      }
      if (existingNameKey.exists) {
        throw const ProductAlreadyExistsException(ProductDuplicateField.name);
      }
      if (existingBarcodeKey.exists) {
        throw const ProductAlreadyExistsException(
          ProductDuplicateField.barcode,
        );
      }

      final timestamp = FieldValue.serverTimestamp();
      transaction.set(productRef, {
        'name': cleanName,
        'barcode': cleanBarcode,
        'createdAt': timestamp,
        'updatedAt': timestamp,
      });
      transaction.set(sellingRef, {
        'sellingPrice': sellingPrice,
        'revision': 1,
        'updatedAt': timestamp,
        'updatedBy': userId,
      });
      transaction.set(costRef, {
        'purchasePrice': purchasePrice,
        'revision': 1,
        'updatedAt': timestamp,
        'updatedBy': userId,
      });
      transaction.set(nameKeyRef, {
        'productId': productRef.id,
        'normalizedName': normalizeName(cleanName),
      });
      transaction.set(barcodeKeyRef, {
        'productId': productRef.id,
        'barcode': cleanBarcode,
      });
      transaction.set(sellingHistoryRef, {
        'productId': productRef.id,
        'priceType': ProductPriceType.selling.value,
        'price': sellingPrice,
        'revision': 1,
        'createdBy': userId,
        'createdAt': timestamp,
      });
      transaction.set(purchaseHistoryRef, {
        'productId': productRef.id,
        'priceType': ProductPriceType.purchase.value,
        'price': purchasePrice,
        'revision': 1,
        'createdBy': userId,
        'createdAt': timestamp,
      });
      return productRef.id;
    });
  }

  Future<void> updateProduct({
    required String storeId,
    required String productId,
    required String name,
    required String barcode,
  }) async {
    final cleanName = name.trim();
    final cleanBarcode = barcode.trim();
    if (cleanName.isEmpty || cleanName.length > 120) {
      throw const FormatException('Enter a product name up to 120 characters.');
    }
    if (cleanBarcode.isEmpty || cleanBarcode.length > 128) {
      throw const FormatException('Enter a barcode up to 128 characters.');
    }

    final productRef = _products(storeId).doc(productId);
    await _firestore.runTransaction((transaction) async {
      final productDocument = await transaction.get(productRef);
      if (!productDocument.exists) {
        throw StateError('Product not found.');
      }
      final product = ProductModel.fromDocument(productDocument);
      final oldNameKey = nameKey(product.name);
      final newNameKey = nameKey(cleanName);
      final oldBarcodeKey = barcodeKey(product.barcode);
      final newBarcodeKey = barcodeKey(cleanBarcode);

      final oldNameRef = _nameKeys(storeId).doc(oldNameKey);
      final newNameRef = _nameKeys(storeId).doc(newNameKey);
      final oldBarcodeRef = _barcodeKeys(storeId).doc(oldBarcodeKey);
      final newBarcodeRef = _barcodeKeys(storeId).doc(newBarcodeKey);

      final oldNameDocument = await transaction.get(oldNameRef);
      final newNameDocument = oldNameKey == newNameKey
          ? oldNameDocument
          : await transaction.get(newNameRef);
      final oldBarcodeDocument = await transaction.get(oldBarcodeRef);
      final newBarcodeDocument = oldBarcodeKey == newBarcodeKey
          ? oldBarcodeDocument
          : await transaction.get(newBarcodeRef);

      if (!oldNameDocument.exists ||
          oldNameDocument.data()?['productId'] != productId ||
          !oldBarcodeDocument.exists ||
          oldBarcodeDocument.data()?['productId'] != productId) {
        throw StateError('Product uniqueness claims are inconsistent.');
      }
      if (oldNameKey != newNameKey && newNameDocument.exists) {
        throw const ProductAlreadyExistsException(ProductDuplicateField.name);
      }
      if (oldBarcodeKey != newBarcodeKey && newBarcodeDocument.exists) {
        throw const ProductAlreadyExistsException(
          ProductDuplicateField.barcode,
        );
      }

      transaction.update(productRef, {
        'name': cleanName,
        'barcode': cleanBarcode,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      if (oldNameKey != newNameKey) {
        transaction.delete(oldNameRef);
        transaction.set(newNameRef, {
          'productId': productId,
          'normalizedName': normalizeName(cleanName),
        });
      }
      if (oldBarcodeKey != newBarcodeKey) {
        transaction.delete(oldBarcodeRef);
        transaction.set(newBarcodeRef, {
          'productId': productId,
          'barcode': cleanBarcode,
        });
      }
    });
  }

  Future<List<ProductModel>> searchProducts({
    required String storeId,
    String query = '',
    int limit = 50,
  }) async {
    final products = _products(storeId);
    final searchText = query.trim();
    if (searchText.isEmpty) {
      final snapshot = await products.orderBy('name').limit(limit).get();
      return snapshot.docs.map(ProductModel.fromDocument).toList();
    }

    final normalizedQuery = normalizeName(searchText);
    final nameMatches = await _nameKeys(storeId)
        .orderBy('normalizedName')
        .startAt([normalizedQuery])
        .endAt(['$normalizedQuery\uf8ff'])
        .limit(limit)
        .get();
    final barcodeMatches = await products
        .orderBy('barcode')
        .startAt([searchText])
        .endAt(['$searchText\uf8ff'])
        .limit(limit)
        .get();

    final productIds = <String>{
      ...nameMatches.docs
          .map((document) => document.data()['productId'])
          .whereType<String>(),
      ...barcodeMatches.docs.map((document) => document.id),
    };
    final documents = await Future.wait(
      productIds.map((id) => products.doc(id).get()),
    );
    return documents
        .where((document) => document.exists)
        .map(ProductModel.fromDocument)
        .toList()
      ..sort(
        (left, right) =>
            left.name.toLowerCase().compareTo(right.name.toLowerCase()),
      );
  }

  Future<ProductModel?> getProduct({
    required String storeId,
    required String productId,
  }) async {
    final document = await _products(storeId).doc(productId).get();
    return document.exists ? ProductModel.fromDocument(document) : null;
  }

  static void _validateFields({
    required String name,
    required String barcode,
    required int purchasePrice,
    required int sellingPrice,
  }) {
    if (name.isEmpty || name.length > 120) {
      throw const FormatException('Enter a product name up to 120 characters.');
    }
    if (barcode.isEmpty || barcode.length > 128) {
      throw const FormatException('Enter a barcode up to 128 characters.');
    }
    if (purchasePrice < 0) {
      throw const FormatException('Purchase price cannot be negative.');
    }
    if (sellingPrice <= 0) {
      throw const FormatException('Selling price must be greater than zero.');
    }
  }
}
