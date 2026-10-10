import 'package:flutter/material.dart';

import '../../../data/models/user_model.dart';
import '../../debts/screens/debt_management_screen.dart';
import '../../products/screens/product_list_screen.dart';
import '../../purchases/screens/purchase_invoice_list_screen.dart';

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
            leading: const CircleAvatar(
              child: Icon(Icons.account_balance_wallet_outlined),
            ),
            title: const Text('إدارة الديون'),
            subtitle: const Text(
              'بحث عن عميل وعرض رصيده وسجل الديون والدفعات',
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push<void>(
              MaterialPageRoute(
                builder: (_) => DebtManagementScreen(user: user),
              ),
            ),
          ),
        ),
        Card(
          child: ListTile(
            leading: const CircleAvatar(
              child: Icon(Icons.receipt_long_outlined),
            ),
            title: const Text('فواتير المشتريات'),
            subtitle: const Text('إنشاء فاتورة شراء وعرض تفاصيلها'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push<void>(
              MaterialPageRoute(
                builder: (_) => PurchaseInvoiceListScreen(user: user),
              ),
            ),
          ),
        ),
      ],
    ),
  );
}
