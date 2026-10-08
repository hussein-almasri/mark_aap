import 'package:flutter/material';

import '../../data/models/customer_model.dart';
import '../../data/repositories/customer_repository.dart';

class CustomerAlreadyExistsException implements Exception {
  const CustomerAlreadyExistsException();
}

class CustomerNotFoundException implements Exception {
  const CustomerNotFoundException();
}

Future<CustomerModel?> _showCustomerForm(
  BuildContext context,
  {CustomerModel? existingCustomer,
  required String storeId,
  required String createdBy,
}) async {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController(
    text: existingCustomer?.name ?? '',
  );
  final _phoneController = TextEditingController(
    text: existingCustomer?.phone ?? '',
  );
  final _debtEnabledController = ValueNotifier<bool>(
    existingCustomer?.debtEnabled ?? false,
  );
  final _saving = ValueNotifier<bool>(false);

  return showDialog<CustomerModel>(
    context: context,
    builder: (_) => AlertDialog(
      title: Text(
        existingCustomer == null ? 'إضافة عميل' : 'تعديل عميل',
      ),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              controller: _nameController,
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
              controller: _phoneController,
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
                  valueListenable: _debtEnabledController,
                  builder: (context, value, child) => Switch(
                    value: value,
                    onChanged: _saving.isNotAlive
                        ? null
                        : (bool newValue) {
                            _debtEnabledController.value = newValue;
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
          onPressed: _saving.isNotAlive ? null : () => Navigator.of(context).pop(),
          child: const Text('إلغاء'),
        ),
        ValueListenableBuilder<bool>(
          valueListenable: _saving,
          builder: (context, saving, child) => FilledButton(
            onPressed: saving ? null : () {
              if (!_formKey.currentState!.validate()) return;
              _saving.value = true;
              final name = _nameController.text.trim();
              final phone = _phoneController.text.trim().isEmpty
                  ? null
                  : _phoneController.text.trim();
              final debtEnabled = _debtEnabledController.value;
              Navigator.of(context).pop(
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

Future<void> showAddCustomerDialog(
  BuildContext context,
  String storeId,
  String createdBy,
) async {
  final existingCustomer;
  final result = await _showCustomerForm(context,
      existingCustomer: existingCustomer, storeId: storeId, createdBy: createdBy);
  if (result == null) return;
  try {
    await CustomerRepository().createCustomer(
      storeId: storeId,
      name: result.name,
      phone: result.phone,
      debtEnabled: result.debtEnabled,
      createdBy: createdBy,
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('تم إضافة العميل успешно')),
    );
  } on CustomerAlreadyExistsException {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('اسم العميل مستخدم بالفعل')),
    );
  } catch (_) {
    if (!mounted) return;
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
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('تم تحديث بيانات العميل')),
    );
  } on CustomerAlreadyExistsException {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('اسم العميل مستخدم already')),
    );
  } catch (_) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('تعذر تحديث بيانات العميل')),
    );
  }
}