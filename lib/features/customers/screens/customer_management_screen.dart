import 'package:flutter/material.dart';

import '../../../data/models/customer_model.dart';
import '../../../data/models/user_model.dart';
import '../../../data/repositories/customer_repository.dart';
import '../widgets/customer_form.dart' show showAddCustomerDialog;

class CustomerAlreadyExistsException implements Exception {
  const CustomerAlreadyExistsException();
}

class CustomerNotFoundException implements Exception {
  const CustomerNotFoundException();
}

class CustomerRepositoryException implements Exception {
  const CustomerRepositoryException();
}

class CustomerManagementScreen extends StatefulWidget {
  const CustomerManagementScreen({required this.user, super.key});

  final UserModel user;

  @override
  State<CustomerManagementScreen> createState() =>
      _CustomerManagementScreenState();
}

class _CustomerManagementScreenState extends State<CustomerManagementScreen> {
  late final CustomerRepository _repository =
      CustomerRepository();
  List<CustomerModel>? _customers;
  final Set<String> _processingCustomerIds = {};
  bool _isLoading = true;
  bool _isSaving = false;
  String? _loadError;
  String? _searchQuery;
  bool _showInactive = false;

  @override
  void initState() {
    super.initState();
    _loadCustomers();
  }

  Future<void> _loadCustomers() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _loadError = null;
    });
    try {
      final storeId = widget.user.storeId;
      final allCustomers =
          await _repository.listCustomers(storeId);
      setState(() {
        _customers = allCustomers;
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

  Future<void> _toggleDebtEnabled(CustomerModel customer) async {
    if (_processingCustomerIds.contains(customer.customerId)) return;
    final activate = !customer.debtEnabled;
    final action = activate ? 'تمكين' : 'تعطيل';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('$action الدين؟'),
        content: Text(
            'هل تريد $action دين ${customer.name}؟'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(action),
          ),
        ],
      ),
    );
    if (confirmed != true ||
        !mounted ||
        _processingCustomerIds.contains(customer.customerId)) {
      return;
    }

    setState(() => _processingCustomerIds.add(customer.customerId));
    try {
      await _repository.updateCustomer(
        storeId: widget.user.storeId,
        customerId: customer.customerId,
        name: customer.name,
        phone: customer.phone,
        debtEnabled: activate,
        updatedBy: widget.user.uid,
      );
      await _loadCustomers();
    } catch (_) {
      if (!mounted) return;
      _showMessage('تعذر تغيير حالة الدين. حاول مرة أخرى.');
    } finally {
      if (mounted) {
        setState(() => _processingCustomerIds.remove(customer.customerId));
      }
    }
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  List<CustomerModel> _getFilteredCustomers() {
    var customers = _customers ?? [];
    if (_searchQuery != null && _searchQuery!.isNotEmpty) {
      final query = _searchQuery!.trim().toLowerCase();
      customers = customers.where((c) {
        final nameMatch = c.name.toLowerCase().contains(query);
        final phoneMatch = c.phone?.toLowerCase().contains(query) == true;
        return nameMatch || phoneMatch;
      }).toList();
    }
    if (!_showInactive) {
      customers = customers.where((c) => c.isActive).toList();
    }
    return customers..sort((a, b) => a.name.compareTo(b.name));
  }

  Widget _buildCustomerCard(CustomerModel customer) {
    final isProcessing =
        _processingCustomerIds.contains(customer.customerId);
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          children: [
            ListTile(
              title: Text(customer.name),
              subtitle: customer.phone != null &&
                      customer.phone!.isNotEmpty
                  ? Text(customer.phone!)
                  : const Text(''),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (!isProcessing) ...[
                    Tooltip(
                      message: customer.debtEnabled ? 'تعطيل الدين' : 'تمكين الدين',
                      child: IconButton(
                        icon: Icon(
                          customer.debtEnabled
                              ? Icons.pause_circle_outline
                              : Icons.play_circle_outline,
                        ),
                        onPressed: _isSaving
                            ? null
                            : () => _toggleDebtEnabled(customer),
                        tooltip: customer.debtEnabled
                            ? 'تعطيل الدين'
                            : 'تمكين الدين',
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (!_showInactive) ...[
              const Divider(height: 1),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    final filtered = _getFilteredCustomers();
    return filtered.isEmpty
        ? const Center(
            child: Text('لا توجد عملاء مطابقة للبحث.'))
        : const SizedBox.shrink();
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      title: const Text('إدارة العملاء'),
      actions: [
        IconButton(
          icon: const Icon(Icons.search),
          onPressed: () {
            setState(() {
              _showInactive = !_showInactive;
            });
          },
        ),
      ],
    );
  }

  Widget _buildLoadFailure() => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_loadError ?? 'تعذر تحميل العملاء.'),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: _loadCustomers,
              child: const Text('إعادة المحاولة'),
            ),
          ],
        ),
      );

  @override
  Widget build(BuildContext context) {
    if (!widget.user.isAdmin) {
      return Scaffold(
        appBar: AppBar(title: const Text('إدارة العملاء')),
        body: const Center(child: Text('هذه الصفحة متاحة للأدمن فقط.')),
      );
    }

    return Scaffold(
      appBar: _buildAppBar(),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _loadError != null
              ? _buildLoadFailure()
              : Column(
                  children: [
                    Expanded(
                      child: _buildCustomerList(),
                    ),
                    _buildBottomAddButton(),
                  ],
                ),
    );
  }

  Widget _buildCustomerList() {
    final customers = _getFilteredCustomers();
    return customers.isEmpty
        ? _buildEmptyState()
        : ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
            itemCount: customers.length,
            itemBuilder: (context, index) =>
                _buildCustomerCard(customers[index]),
          );
  }

  Widget _buildBottomAddButton() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: FloatingActionButton.extended(
        onPressed: _isSaving ? null : () => _showAddCustomerDialog(),
        icon: const Icon(Icons.add),
        label: const Text('إضافة عميل'),
      ),
    );
  }

  void _showAddCustomerDialog() {
    showAddCustomerDialog(
      context,
      widget.user.storeId,
      widget.user.uid,
    ).then((_) => _loadCustomers());
  }
}