import 'package:flutter/material.dart';

import '../../../data/models/user_model.dart';
import '../../customers/screens/customer_lookup_screen.dart';
import '../../products/screens/product_list_screen.dart';

class EmployeeDashboard extends StatelessWidget {
  const EmployeeDashboard({required this.user, super.key});

  final UserModel user;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('رَفّ | لوحة الموظف')),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: ListTile(
            leading: const CircleAvatar(child: Icon(Icons.search)),
            title: const Text('المنتجات'),
            subtitle: const Text('البحث وعرض أسعار البيع'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push<void>(
              MaterialPageRoute(builder: (_) => ProductListScreen(user: user)),
            ),
          ),
        ),
        Card(
          child: ListTile(
            leading: const CircleAvatar(child: Icon(Icons.people_outlined)),
            title: const Text('عملاء'),
            subtitle: const Text('عرض قائمة العملاء'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push<void>(
              MaterialPageRoute(
                builder: (_) => CustomerLookupScreen(user: user),
              ),
            ),
          ),
        ),
      ],
    ),
  );
}
