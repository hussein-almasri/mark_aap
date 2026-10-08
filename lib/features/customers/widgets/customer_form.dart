import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../../data/models/customer_model.dart';
import '../../../data/repositories/customer_repository.dart';

class CustomerAlreadyExistsException implements Exception {
  const CustomerAlreadyExistsException();
}

class CustomerNotFoundException implements Exception {
  const CustomerNotFoundException();
}

Future<CustomerModel?> _showCustomerForm(
  BuildContext context, {
  CustomerModel? existingCustomer,
  required String storeId,
  required String createdBy,
}) async {
  final formKey = GlobalKey<FormState>();
  final nameController = TextEditingController(
    text: existingCustomer?.name ?? '',
  );
  final phoneController = TextEditingController(
    text: existingCustomer?.phone ?? '',
  );
  final debtEnabledController = ValueNotifier<bool>(
    existingCustomer?.debtEnabled ?? false,
  );
  final saving = ValueNotifier<bool>(false);

  final result = await showDialog<CustomerModel>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(
        existingCustomer == null ? 'إضافة عميل' : 'تعديل عميل',
      ),
      content: Form(
        key: formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              controller: nameController,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'اسم العميل',
                border: OutlineInputBorder(),
              ),
              validator: (value) {
                final name = value?.trim() ?? '';
                if (name.isEmpty) return 'اسم العميل مطلوب.';
                if (name.length > 120) return 'الحد الأقصى 120 حرفاً.';
                return null;
              },
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: phoneController,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(
                labelText: 'رقم الهاتف (اختياري)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                const Text('تمكين الدين'),
                ValueListenableBuilder<bool>(
                  valueListenable: debtEnabledController,
                  builder: (context, value, child) => Switch(
                    value: value,
                    onChanged: saving.value
                        ? null
                        : (bool newValue) {
                            debtEnabledController.value = newValue;
                          },
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: saving.value ? null : () => Navigator.of(dialogContext).pop(),
          child: const Text('إلغاء'),
        ),
        ValueListenableBuilder<bool>(
          valueListenable: saving,
          builder: (context, isSaving, child) => FilledButton(
            onPressed: isSaving
                ? null
                : () {
                    if (!formKey.currentState!.validate()) return;
                    saving.value = true;
                    final name = nameController.text.trim();
                    final phone = phoneController.text.trim().isEmpty
                        ? null
                        : phoneController.text.trim();
                    final debtEnabled = debtEnabledController.value;
                    Navigator.of(dialogContext).pop(
                      CustomerModel(
                        customerId: existingCustomer?.customerId ?? '',
                        name: name,
                        phone: phone,
                        debtEnabled: debtEnabled,
                        isActive: true,
                        createdAt: Timestamp.now(),
                        updatedAt: Timestamp.now(),
                        createdBy: createdBy,
                        updatedBy: createdBy,
                      ),
                    );
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
  debtEnabledController.dispose();
  saving.dispose();
  nameController.dispose();
  phoneController.dispose();
  return result;
}

Future<void> showAddCustomerDialog(
  BuildContext context,
  String storeId,
  String createdBy,
) async {
  final result = await _showCustomerForm(context,
      storeId: storeId, createdBy: createdBy);
  if (result == null) return;
  try {
    await CustomerRepository().createCustomer(
      storeId: storeId,
      name: result.name,
      phone: result.phone,
      debtEnabled: result.debtEnabled,
      createdBy: createdBy,
    );
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('تم إضافة العميل بنجاح')),
    );
  } on CustomerAlreadyExistsException {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('اسم العميل مستخدم بالفعل')),
    );
  } catch (_) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('تعذر إضافة العميل')),
    );
  }
}

Future<void> showEditCustomerDialog(
  BuildContext context,
  String storeId,
  String customerId,
  String updatedBy,
) async {
  final repo = CustomerRepository();
  final customer = await repo.getCustomer(storeId, customerId);
  final result = await _showCustomerForm(context,
      existingCustomer: customer, storeId: storeId, createdBy: updatedBy);
  if (result == null) return;
  try {
    await repo.updateCustomer(
      storeId: storeId,
      customerId: customerId,
      name: result.name,
      phone: result.phone,
      debtEnabled: result.debtEnabled,
      updatedBy: updatedBy,
    );
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('تم تحديث بيانات العميل')),
    );
  } on CustomerAlreadyExistsException {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('اسم العميل مستخدم بالفعل')),
    );
  } catch (_) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('تعذر تحديث بيانات العميل')),
    );
  }
}