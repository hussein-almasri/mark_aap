import 'package:flutter/material.dart';

import '../../../data/models/user_model.dart';
import '../../../shared/widgets/raff_app_shell.dart';

class AdminDashboard extends StatelessWidget {
  const AdminDashboard({required this.user, super.key});

  final UserModel user;

  @override
  Widget build(BuildContext context) => RaffAppShell(user: user);
}
