import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../../data/models/customer_model.dart';
import '../../../data/repositories/customer_transaction_repository.dart';

class InsufficientBalanceException implements Exception {
  const InsufficientBalanceException();
}

Future<({int amount, String? note})?> _showTransactionForm(
  BuildContext context,
  CustomerModel customer, {
  required String storeId,
  required String createdBy,
  required String transactionType,
}) async {
  final amountController = TextEditingController();
  final noteController = TextEditingController();
  final formKey = GlobalKey<FormState>();
  final saving = ValueNotifier<bool>(false);

  final result = await showDialog<({int amount, String? note})>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(
        transactionType == 'debt' ? 'إضافة دين' : 'إضافة مدفوعة',
      ),
      content: Form(
        key: formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: amountController,
                keyboardType: const TextInputType.numberWithOptions(decimal: false),
                decoration: const InputDecoration(
                  labelText: 'المبلغ (فلس)',
                  border: OutlineInputBorder(),
                ),
                validator: (value) {
                  final text = value?.trim() ?? '';
                  if (text.isEmpty) return 'المبلغ مطلوب.';
                  final amount = int.tryParse(text);
                  if (amount == null) return 'مبلغ غير صحيح.';
                  if (amount <= 0) return 'يجب أن يكون أكبر من صفر.';
                  if (transactionType == 'payment' && customer.debtEnabled == false) {
                    return null;
                  }
                  return null;
                },
              ),
              if (transactionType == 'payment') ...[
                const SizedBox(height: 12),
                const Text(
                  'لا يتجاوز المبلغ الرصيد الحالي',
                  style: TextStyle(color: Colors.red),
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
                    final rawValue = amountController.text.trim();
                    final parsedAmount = int.tryParse(rawValue);
                    if (parsedAmount == null) return;
                    saving.value = true;
                    Navigator.of(dialogContext).pop((
                      amount: parsedAmount,
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

Future<void> showAddDebtDialog(
  BuildContext context,
  String storeId,
  String customerId,
  String createdBy,
) async {
  final customer = CustomerModel(
    customerId: customerId,
    name: 'Customer',
    debtEnabled: true,
    isActive: true,
    createdAt: Timestamp.now(),
    updatedAt: Timestamp.now(),
    createdBy: createdBy,
    updatedBy: createdBy,
  );

  final result = await _showTransactionForm(
    context,
    customer,
    storeId: storeId,
    createdBy: createdBy,
    transactionType: 'debt',
  );
  if (result == null) return;

  try {
    await CustomerTransactionRepository().createDebt(
      storeId: storeId,
      customerId: customerId,
      amountFils: result.amount,
      createdBy: createdBy,
    );

    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('تم إضافة الدين')),
    );
  } catch (e) {
    if (!context.mounted) return;
    final message = e.toString().contains('Must be > 0')
        ? 'المبلغ يجب أن يكون أكبر من صفر'
        : e.toString().contains('debtEnabled')
            ? 'خدمة الدين معطلة لهذا العميل'
            : 'تعذر إضافة الدين';
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
  final customer = CustomerModel(
    customerId: customerId,
    name: 'Customer',
    debtEnabled: true,
    isActive: true,
    createdAt: Timestamp.now(),
    updatedAt: Timestamp.now(),
    createdBy: createdBy,
    updatedBy: createdBy,
  );

  final result = await _showTransactionForm(
    context,
    customer,
    storeId: storeId,
    createdBy: createdBy,
    transactionType: 'payment',
  );
  if (result == null) return;

  try {
    await CustomerTransactionRepository().createPayment(
      storeId: storeId,
      customerId: customerId,
      amountFils: result.amount,
      createdBy: createdBy,
    );

    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('تم تسجيل المدفوعة')),
    );
  } catch (e) {
    if (!context.mounted) return;
    final message = e.toString().contains('Must be > 0')
        ? 'المبلغ يجب أن يكون أكبر من صفر'
        : 'تعذر تسجيل المدفوعة';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }
}