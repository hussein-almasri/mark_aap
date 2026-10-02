class UserModel {
  const UserModel({
    required this.uid,
    required this.storeId,
    required this.name,
    required this.email,
    required this.role,
    required this.isActive,
  });

  final String uid;
  final String storeId;
  final String name;
  final String email;
  final String role;
  final bool isActive;

  bool get isAdmin => role == 'ADMIN';

  bool get isEmployee => role == 'EMPLOYEE';
}