import 'package:flutter/material.dart';

import '../../../data/models/user_model.dart';
import '../../companies/screens/company_management_screen.dart';
import 'employee_management_screen.dart';
import 'store_join_code_screen.dart';
import '../../products/screens/product_list_screen.dart';

class AdminDashboard extends StatelessWidget {
  const AdminDashboard({required this.user, super.key});

  final UserModel user;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('رَفّ | لوحة الإدارة')),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: ListTile(
            leading: const CircleAvatar(
              child: Icon(Icons.business_outlined),
            ),
            title: const Text('إدارة الشركات'),
            subtitle: const Text('إضافة الشركات وتحديث بياناتها وحالتها'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push<void>(
              MaterialPageRoute(
                builder: (_) => CompanyManagementScreen(user: user),
              ),
            ),
          ),
        ),
        Card(
          child: ListTile(
            leading: const CircleAvatar(child: Icon(Icons.people_alt_outlined)),
            title: const Text('إدارة الموظفين'),
            subtitle: const Text('عرض حالة الموظفين وإدارتها'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push<void>(
              MaterialPageRoute(
                builder: (_) => EmployeeManagementScreen(user: user),
              ),
            ),
          ),
        ),
        Card(
          child: ListTile(
            leading: const CircleAvatar(child: Icon(Icons.key_rounded)),
            title: const Text('كود انضمام الموظفين'),
            subtitle: const Text('عرض الكود الحالي أو تغييره'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push<void>(
              MaterialPageRoute(
                builder: (_) => StoreJoinCodeScreen(user: user),
              ),
            ),
          ),
        ),
        Card(
          child: ListTile(
            leading: const CircleAvatar(
              child: Icon(Icons.inventory_2_outlined),
            ),
            title: const Text('المنتجات'),
            subtitle: const Text('إدارة المنتجات والأسعار'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push<void>(
              MaterialPageRoute(builder: (_) => ProductListScreen(user: user)),
            ),
          ),
        ),
      ],
    ),
  );
}
