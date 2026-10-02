import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/store_model.dart';

class StoreRepository {
  StoreRepository({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> get _stores =>
      _firestore.collection('stores');

  Future<String> createStore({
    required String name,
    required String ownerName,
    String? logoUrl,
  }) async {
    final document = await _stores.add({
      'name': name.trim(),
      'ownerName': ownerName.trim(),
      'logoUrl': logoUrl,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });

    return document.id;
  }

  Future<StoreModel> getStore(String storeId) async {
    final document = await _stores.doc(storeId).get();

    if (!document.exists) {
      throw StateError('Store not found.');
    }

    return StoreModel.fromFirestore(document);
  }
}