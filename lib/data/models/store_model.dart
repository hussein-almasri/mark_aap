import 'package:cloud_firestore/cloud_firestore.dart';

class StoreModel {
  const StoreModel({
    required this.id,
    required this.name,
    required this.ownerName,
    this.logoUrl,
    this.createdAt,
    this.updatedAt,
  });

  final String id;
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
      'ownerName': ownerName,
      'logoUrl': logoUrl,
      'createdAt': createdAt,
      'updatedAt': updatedAt,
    };
  }
}