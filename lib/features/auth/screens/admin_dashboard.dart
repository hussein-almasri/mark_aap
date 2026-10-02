import 'package:flutter/material.dart';

import '../../../data/models/user_model.dart';

class AdminDashboard extends StatelessWidget {
  const AdminDashboard({required this.user, super.key});

  final UserModel user;

  @override
  Widget build(BuildContext context) => _PlaceholderDashboard(user: user);
}

class _PlaceholderDashboard extends StatelessWidget {
  const _PlaceholderDashboard({required this.user});

  final UserModel user;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Text(
          'Dashboard\nالمستخدم: ${user.name}\nالدور: ${user.role}\nالمتجر: ${user.storeId}',
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}
