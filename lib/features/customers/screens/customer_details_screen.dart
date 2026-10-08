import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../data/models/customer_model.dart';
import '../../../data/models/customer_transaction_model.dart';
import '../../../data/models/user_model.dart';
import '../../../data/repositories/customer_repository.dart';
import '../../../data/repositories/customer_transaction_repository.dart';

class CustomerDetailsScreen extends StatefulWidget {
  const CustomerDetailsScreen({
    required this.user,
    required this.customerId,
    super.key,
  });

  final UserModel user;
  final String customerId;

  @override
  State<CustomerDetailsScreen> createState() =>
      _CustomerDetailsScreenState();
}

class _CustomerDetailsScreenState extends State<CustomerDetailsScreen> {
  late final CustomerRepository _customerRepo =
      CustomerRepository();
  late final CustomerTransactionRepository _txRepo =
      CustomerTransactionRepository();

  CustomerModel? _customer;
  List<CustomerTransactionModel>? _transactions;
  int? _balance;
  bool _isLoading = true;
  String? _loadError;

  @override
  void initState() {
    super.initState();
    _loadCustomer();
    _loadTransactions();
  }

  Future<void> _loadCustomer() async {
    try {
      final customer =
          await _customerRepo.getCustomer(widget.user.storeId, widget.customerId);
      setState(() => _customer = customer);
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadError = 'تعذر تحميل بيانات العميل');
    }
  }

  Future<void> _loadTransactions() async {
    if (_customer == null) return;
    setState(() {
      _isLoading = true;
      _loadError = null;
    });
    try {
      final txs = await _txRepo.listTransactions(
        widget.user.storeId,
        widget.customerId,
      );
      setState(() => _transactions = txs);
      _computeBalance();
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadError = 'تعذر تحميل المعاملات');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _computeBalance() async {
    if (_customer == null) return;
    final balance =
        await _txRepo.calculateBalanceAsync(
          widget.user.storeId,
          widget.customerId,
        );
    setState(() => _balance = balance);
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  bool _canAddDebt() {
    return _customer?.debtEnabled == true;
  }

  // Show add debt/payment form
  void _showTransactionForm(String type) {
    final customer = _customer!;
    if (type == 'debt' && !customer.debtEnabled) {
      _showMessage('خدمة الدين معطلة لهذا العميل');
      return;
    }
    if (type == 'payment') {
      // Show info about balance
    }
    _showTransactionFormInternal(type);
  }

  Future<void> _showTransactionFormInternal(String type) async {
    final result = await _showTransactionFormInternal2(type);
    if (result == null) return;
    try {
      if (type == 'debt') {
        await _txRepo.createDebt(
          storeId: widget.user.storeId,
          customerId: widget.customerId,
          amountFils: result.amount,
          createdBy: widget.user.uid,
        );
      } else {
        await _txRepo.createPayment(
          storeId: widget.user.storeId,
          customerId: widget.customerId,
          amountFils: result.amount,
          createdBy: widget.user.uid,
        );
      }
      _showMessage(type == 'debt' ? 'تم إضافة الدين' : 'تم تسجيل المدفوعة');
      await _loadTransactions();
    } catch (e) {
      String message;
      if (e.toString().contains('Must be > 0')) {
        message = 'المبلغ يجب أن يكون أكبر من صفر';
      } else if (e.toString().contains('debtEnabled')) {
        message = 'خدمة الدين معطلة لهذا العميل';
      } else {
        message = 'تعذر العملية';
      }
      _showMessage(message);
    }
  }

  Future<({int amount, String? note})?> _showTransactionFormInternal2(
    String type,
  ) async {
    final amountController = TextEditingController();
    final noteController = TextEditingController();
    final saving = ValueNotifier<bool>(false);
    final formKey = GlobalKey<FormState>();

    final result = await showDialog<({int amount, String? note})>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(
          type == 'debt' ? 'إضافة دين' : 'إضافة مدفوعة',
        ),
        content: Form(
          key: formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: amountController,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: false),
                  decoration: const InputDecoration(
                    labelText: 'المبلغ (فلس)',
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) {
                    final amount = value?.trim() ?? '';
                    if (amount.isEmpty) return 'المبلغ مطلوب.';
                    final amountInt = int.tryParse(amount);
                    if (amountInt == null) return 'مبلغ غير صحيح.';
                    if (amountInt <= 0) return 'يجب أن يكون أكبر من صفر.';
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                if (type == 'payment') ...[
                  const SizedBox(height: 8),
                  const Text(
                    'لا يتجاوز المبلغ الرصيد الحالي',
                    style: TextStyle(color: Colors.red),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _balance != null
                        ? 'الرصيد: $_balance Fils'
                        : 'جاري حساب الرصيد...',
                  ),
                ],
                const SizedBox(height: 12),
                TextFormField(
                  controller: noteController,
                  decoration: const InputDecoration(
                    labelText: 'ملاحظة (اختياري)',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('إلغاء'),
          ),
          ValueListenableBuilder<bool>(
            valueListenable: saving,
            builder: (context, isSaving, child) => FilledButton(
              onPressed: isSaving
                  ? null
                  : () {
                      if (!formKey.currentState!.validate()) return;
                      final parsed = int.tryParse(amountController.text.trim());
                      if (parsed == null) return;
                      saving.value = true;
                      Navigator.of(dialogContext).pop((
                        amount: parsed,
                        note: noteController.text.trim().isEmpty
                            ? null
                            : noteController.text.trim(),
                      ));
                    },
              child: isSaving
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('حفظ'),
            ),
          ),
        ],
      ),
    );
    saving.dispose();
    return result;
  }

  // Admin: cancel transaction
  Future<void> _adminCancelTransaction(
      CustomerTransactionModel transaction) async {
    if (transaction.status.value == CustomerTransactionStatus.cancelled.value) {
      _showMessage('هذه المعاملة ملغاة بالفعل');
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('إلغاء المعاملة'),
        content: Text(
            'هل تريد إلغاء هذه المعاملة لـ ${_customer?.name}؟'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('إلغاء'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await _txRepo.adminCancelTransaction(
        storeId: widget.user.storeId,
        customerId: widget.customerId,
        transactionId: transaction.transactionId,
        cancelledBy: widget.user.uid,
        cancellationReason:
            'ملغاة من قبل المسؤول',
      );
      _showMessage('تم إلغاء المعاملة');
      _loadTransactions();
    } catch (e) {
      String message;
      if (e.toString().contains('must have no cancellation metadata')) {
        message = 'النشاملة يجب أن تكون فارغة للمعاملة النشطة';
      } else {
        message = 'تعذر إلغاء المعاملة';
      }
      _showMessage(message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isAdmin = widget.user.isAdmin;
    final customer = _customer;

    if (customer == null) {
      return Scaffold(
        appBar: AppBar(title: Text('${widget.customerId} - تفاصيل العميل')),
        body: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _loadError != null
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(_loadError!),
                        const SizedBox(height: 16),
                        FilledButton(
                          onPressed: _loadCustomer,
                          child: const Text('إعادة المحاولة'),
                        ),
                      ],
                    ),
                  )
                : const Center(child: Text('لا توجد بيانات للعميل'))
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text('${_customer?.name ?? ''} - تفاصيل'),
        actions: [
          if (isAdmin) ...[
            IconButton(
              icon: const Icon(Icons.delete_outline),
              tooltip: 'تعطيل العميل',
              onPressed: () {
                // Could show dialog to deactivate customer
                _showMessage('تعطيل العميل من هنا');
              },
            ),
          ],
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _loadError != null
              ? _buildLoadError()
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Customer info header
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _customer?.name ?? '',
                                style: const TextStyle(
                                  fontSize: 24,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  const Icon(Icons.phone),
                                  const SizedBox(width: 4),
                                  Text(
                                    _customer?.phone ?? 'لا يوجد رقم',
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  const Icon(Icons.money),
                                  const SizedBox(width: 4),
                                  Text(
                                    _balance != null
                                        ? 'الرصيد: ${_balance} Fils'
                                        : 'جاري حساب الرصيد...',
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  const Icon(Icons.toggle_on),
                                  const SizedBox(width: 4),
                                  Text(
                                    _customer?.debtEnabled == true
                                        ? 'دين مفعل'
                                        : 'دين معطل',
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Transaction history
                      const Text(
                        'تاريخ المعاملات',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),

                      _transactions == null || _transactions!.isEmpty
                          ? const Text('لا توجد معاملات')
                          : _buildTransactionList(),
                      const SizedBox(height: 16),

                      // Action buttons
                      _buildActionButtons(isAdmin),
                    ],
                  ),
                ),
    );
  }

  Widget _buildLoadError() => Center(
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(_loadError!),
        const SizedBox(height: 16),
        FilledButton(onPressed: _loadTransactions, child: const Text('إعادة المحاولة')),
      ],
    ),
  );

  Widget _buildTransactionList() {
    final txs = _transactions!
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: txs.length,
      itemBuilder: (context, index) => _buildTransactionCard(txs[index]),
    );
  }

  Widget _buildTransactionCard(CustomerTransactionModel tx) {
    final isCancelled = tx.status.value == CustomerTransactionStatus.cancelled.value;
    final typeLabel = tx.type.value == 'DEBT' ? 'دين' : 'مدفوعة';
    final statusText = isCancelled ? 'ملغاة' : 'نشطة';
    final isAdmin = widget.user.isAdmin;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Icon(
              isCancelled
                  ? Icons.cancel_outlined
                  : tx.type.value == 'DEBT'
                      ? Icons.add_chart
                      : Icons.remove_circle_outline,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '$typeLabel - ${tx.amountFils} Fils',
                    style: const TextStyle(fontWeight: FontWeight.w500),
                  ),
                  Text(
                    '$statusText • ${_formatDate(tx.createdAt)}',
                    style: TextStyle(
                      color: Colors.grey[600],
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            if (isAdmin) ...[
              const SizedBox(width: 4),
              if (!isCancelled)
                IconButton(
                  icon: const Icon(Icons.remove_circle_outline),
                  tooltip: 'إلغاء المعاملة',
                  onPressed: () => _adminCancelTransaction(tx),
                ),
            ],
          ],
        ),
      ),
    );
  }

  String _formatDate(Timestamp timestamp) {
    return DateFormat('dd/MM/yyyy - HH:mm').format(timestamp.toDate());
  }

  Widget _buildActionButtons(bool isAdmin) {
    final canAddDebt = _canAddDebt();
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        const Spacer(),
        if (isAdmin) ...[
          FilledButton.icon(
            onPressed: canAddDebt ? () => _showTransactionForm('debt') : null,
            icon: const Icon(Icons.add_chart),
            label: const Text('دين'),
          ),
          const SizedBox(width: 8),
          FilledButton.icon(
            onPressed: () => _showTransactionForm('payment'),
            icon: const Icon(Icons.payment),
            label: const Text('مدفوعة'),
          ),
        ],
        if (!isAdmin && widget.user.isEmployee) ...[
          const SizedBox(width: 8),
          FilledButton.icon(
            onPressed: canAddDebt ? () => _showTransactionForm('payment') : null,
            icon: const Icon(Icons.payment),
            label: const Text('مدفوعة'),
          ),
        ],
      ],
    );
  }
}