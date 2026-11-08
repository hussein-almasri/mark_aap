import 'package:flutter/material.dart';

import '../../../data/models/user_model.dart';
import '../../../shared/widgets/raff_app_shell.dart';

class EmployeeDashboard extends StatelessWidget {
  const EmployeeDashboard({required this.user, super.key});

  final UserModel user;

  @override
  Widget build(BuildContext context) => RaffAppShell(user: user);
}
