import 'package:flutter/material';

import '../../data/models/customer_model.dart';
import '../../data/repositories/customer_repository.dart';
import '../../data/models/customer_transaction_model.dart';

class InsufficientBalanceException implements Exception {
  const InsufficientBalanceException();
}

Future<({int amount, String? note})?> _showTransactionForm(
  BuildContext context,
  CustomerModel customer,
  {required String storeId,
  required String createdBy,
  required String transactionType,
}) async {
  final _amountController = TextEditingController();
  final _noteController = TextEditingController();
  final _saving = ValueNotifier<bool>(false);

  double? maxAmount;
  if (transactionType == 'debt') {
    if (!customer.debtEnabled) {
      // Show info but allow override
    }
    maxAmount = null; // Debt can always be added when debtEnabled
  } else {
    // Payment: cannot exceed current balance
    // Balance = active DEBT - active PAYMENT
    // We'll compute it simply: show a message about current balance
    maxAmount = null; // Rules will enforce
  }

  return showDialog<({int amount, String? note})>(
    context: context,
    builder: (_) => AlertDialog(
      title: Text(
        transactionType == 'debt'
            ? 'إضافة دين'
            : 'إضافة مدفوعة',
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              controller: _amountController,
              keyboardType: const TextInputType.numberWithOptions(decimal: false),
              decoration: const InputDecoration(
                labelText: 'المبلغ (فلس)',
                border: OutlineInputBorder(),
              ),
              validator: (value) {
                final amount = value?.trim();
                if (amount == null || amount.isEmpty) return 'المبلغ مطلوب.';
                final amountInt = int.tryParse(amount);
                if (amountInt == null) return 'مبلغ غير صحيح.';
                if (amountInt <= 0) return 'يجب أن يكون أكبر من صفر.';
                return null;
              },
            ),
            if (transactionType == 'payment') ...const [
              const SizedBox(height: 12),
              const Text(
                'لا يتجاوز المبلغ الرصيد الحالي',
                style: TextStyle(color: Colors.red),
              ),
            ],
            const SizedBox(height: 12),
            TextFormField(
              controller: _noteController,
              decoration: const InputDecoration(
                labelText: 'ملاحظة (اختياري)',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving.isNotAlive ? null : () => Navigator.of(context).pop(),
          child: const Text('إلغاء'),
        ),
        ValueListenableBuilder<bool>(
          valueListenable: _saving,
          builder: (context, saving, child) => FilledButton(
            onPressed: saving ? null : () {
              if (!_amountController.text.trim().isEmpty &&
                  int.tryParse(_amountController.text.trim()) != null) {
                final amount = int.parse(_amountController.text.trim());
                Navigator.of(context).pop((
                  amount: amount,
                  note: _noteController.text.trim().isEmpty
                      ? null
                      : _noteController.text.trim(),
                ));
              }
            },
            child: saving
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
}

Future<void> showAddDebtDialog(
  BuildContext context,
  String storeId,
  String customerId,
  String createdBy,
) async {
  final result = await _showTransactionForm(context,
    // We'll fetch customer inside or pass it
    CustomerModel(
      customerId: customerId,
      name: '',
      debtEnabled: false,
      isActive: true,
      createdAt: Timestamp.now(),
      updatedAt: Timestamp.now(),
      createdBy: createdBy,
      updatedBy: createdBy,
    ),
    storeId: storeId,
    createdBy: createdBy,
    transactionType: 'debt',
  );
  if (result == null) return;
  try {
    await CustomerRepository().createDebt(
      storeId: storeId,
      customerId: customerId,
      amountFils: result.amount,
      createdBy: createdBy,
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('تم إضافة الدين')),
    );
  } catch (e) {
    if (!mounted) return;
    String message;
    if (e.toString().contains('debtEnabled')) {
      message = 'خدمة الدين معطلة لهذا العميل';
    } else if (e.toString().contains('Must be > 0')) {
      message = 'المبلغ يجب أن يكون أكبر من صفر';
    } else {
      message = 'تعذر إضافة الدين';
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }
}

Future<void> showAddPaymentDialog(
  BuildContext context,
  String storeId,
  String customerId,
  String createdBy,
) async {
  final result = await _showTransactionForm(context,
    CustomerModel(
      customerId: customerId,
      name: '',
      debtEnabled: false,
      isActive: true,
      createdAt: Timestamp.now(),
      updatedAt: Timestamp.now(),
      createdBy: createdBy,
      updatedBy: createdBy,
    ),
    storeId: storeId,
    createdBy: createdBy,
    transactionType: 'payment',
  );
  if (result == null) return;
  try {
    await CustomerRepository().createPayment(
      storeId: storeId,
      customerId: customerId,
      amountFils: result.amount,
      createdBy: createdBy,
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('تم تسجيل المدفوعة')),
    );
  } catch (e) {
    if (!mounted) return;
    String message;
    if (e.toString().contains('Must be > 0')) {
      message = 'المبلغ يجب أن يكون أكبر من صفر';
    } else {
      message = 'تعذر تسجيل المدفوعة';
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }
}