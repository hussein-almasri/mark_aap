import 'package:flutter/material.dart';

import '../../../data/models/user_model.dart';

class EmployeeDashboard extends StatelessWidget {
  const EmployeeDashboard({required this.user, super.key});

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
