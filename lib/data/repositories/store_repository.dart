import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/store_model.dart';

class StoreRepository {
  StoreRepository({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> get _stores =>
      _firestore.collection('stores');

  DocumentReference<Map<String, dynamic>> newStoreReference() =>
      _stores.doc();

  void addStoreToBatch({
    required WriteBatch batch,
    required DocumentReference<Map<String, dynamic>> document,
    required String name,
    required String ownerName,
    required String ownerUid,
    String? logoUrl,
  }) {
    batch.set(document, {
      'ownerUid': ownerUid,
      'name': name.trim(),
      'ownerName': ownerName.trim(),
      'logoUrl': logoUrl,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<StoreModel> getStore(String storeId) async {
    final document = await _stores.doc(storeId).get();

    if (!document.exists) {
      throw StateError('Store not found.');
    }

    return StoreModel.fromFirestore(document);
  }
}
