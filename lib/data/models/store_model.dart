import 'package:cloud_firestore/cloud_firestore.dart';

class StoreModel {
  const StoreModel({
    required this.id,
    this.ownerUid,
    required this.name,
    required this.ownerName,
    this.logoUrl,
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String? ownerUid;
  final String name;
  final String ownerName;
  final String? logoUrl;
  final Timestamp? createdAt;
  final Timestamp? updatedAt;

  factory StoreModel.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> document,
  ) {
    final data = document.data();

    if (data == null) {
      throw StateError('Store document is empty.');
    }

    return StoreModel(
      id: document.id,
      ownerUid: data['ownerUid'] as String?,
      name: data['name'] as String? ?? '',
      ownerName: data['ownerName'] as String? ?? '',
      logoUrl: data['logoUrl'] as String?,
      createdAt: data['createdAt'] as Timestamp?,
      updatedAt: data['updatedAt'] as Timestamp?,
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'name': name,
      if (ownerUid != null) 'ownerUid': ownerUid,
      'ownerName': ownerName,
      'logoUrl': logoUrl,
      'createdAt': createdAt,
      'updatedAt': updatedAt,
    };
  }
}
