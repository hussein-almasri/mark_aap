import 'package:cloud_firestore/cloud_firestore.dart';

class StoreModel {
  const StoreModel({
    required this.id,
    required this.ownerUid,
    required this.name,
    this.joinCode,
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String ownerUid;
  final String name;
  final String? joinCode;
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
      ownerUid: data['ownerUid'] as String? ?? '',
      name: data['name'] as String? ?? '',
      joinCode: data['joinCode'] as String?,
      createdAt: data['createdAt'] as Timestamp?,
      updatedAt: data['updatedAt'] as Timestamp?,
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'name': name,
      'ownerUid': ownerUid,
      if (joinCode != null) 'joinCode': joinCode,
      'createdAt': createdAt,
      'updatedAt': updatedAt,
    };
  }
}
