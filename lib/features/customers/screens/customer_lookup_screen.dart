import 'package:flutter/material.dart';

import '../../../data/models/customer_model.dart';
import '../../../data/models/user_model.dart';
import '../../../data/repositories/customer_repository.dart';
import 'customer_details_screen.dart';

class CustomerLookupScreen extends StatefulWidget {
  const CustomerLookupScreen({
    required this.user,
    this.title = 'العملاء',
    super.key,
  });

  final UserModel user;

  /// Presented title. Debt management reuses this screen under its own name
  /// so the search/history flow is not duplicated.
  final String title;

  @override
  State<CustomerLookupScreen> createState() => _CustomerLookupScreenState();
}

class _CustomerLookupScreenState extends State<CustomerLookupScreen> {
  final CustomerRepository _repository = CustomerRepository();
  List<CustomerModel>? _customers;
  bool _isLoading = true;
  String? _loadError;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _loadCustomers();
  }

  Future<void> _loadCustomers() async {
    setState(() {
      _isLoading = true;
      _loadError = null;
    });
    try {
      final customers =
          await _repository.listActiveCustomers(widget.user.storeId);
      if (!mounted) return;
      setState(() {
        _customers = customers;
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loadError = 'تعذر تحميل قائمة العملاء.';
        _isLoading = false;
      });
    }
  }

  List<CustomerModel> _getFilteredCustomers() {
    final customers = _customers ?? [];
    final query = _searchQuery.trim().toLowerCase();
    final filtered = query.isEmpty
        ? customers
        : customers.where((c) {
            final nameMatch = c.name.toLowerCase().contains(query);
            final phoneMatch = c.phone?.toLowerCase().contains(query) == true;
            return nameMatch || phoneMatch;
          }).toList();
    return filtered..sort((a, b) => a.name.compareTo(b.name));
  }

  void _openCustomer(CustomerModel customer) {
    Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => CustomerDetailsScreen(
          user: widget.user,
          customerId: customer.customerId,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: TextField(
              decoration: const InputDecoration(
                hintText: 'ابحث بالاسم أو رقم الهاتف',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
              ),
              onChanged: (value) => setState(() => _searchQuery = value),
            ),
          ),
          Expanded(child: _buildBody()),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_loadError != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_loadError!),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: _loadCustomers,
              child: const Text('إعادة المحاولة'),
            ),
          ],
        ),
      );
    }

    final customers = _getFilteredCustomers();
    if (customers.isEmpty) {
      return const Center(child: Text('لا توجد عملاء مطابقة للبحث.'));
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: customers.length,
      itemBuilder: (context, index) {
        final customer = customers[index];
        return Card(
          child: ListTile(
            title: Text(customer.name),
            subtitle: customer.phone != null && customer.phone!.isNotEmpty
                ? Text(customer.phone!)
                : null,
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _openCustomer(customer),
          ),
        );
      },
    );
  }
}
