import 'package:flutter/material.dart';

import '../../../data/repositories/customer_repository.dart'
    show CustomerAlreadyExistsException, CustomerRepository;

/// Raw values captured by the add/edit dialog.
///
/// Deliberately not a [CustomerModel]: that model's constructor rejects an
/// empty `customerId` (customer_model.dart `_requireId`), which is exactly what
/// the add flow has. Building one inside the dialog's save handler therefore
/// threw an `ArgumentError` before `Navigator.pop` could run, leaving the
/// dialog open with a disabled spinner button forever. This is only a data
/// carrier and cannot throw.
class CustomerDraft {
  const CustomerDraft({
    required this.name,
    required this.phone,
    required this.debtEnabled,
  });

  final String name;
  final String? phone;
  final bool debtEnabled;
}

Future<CustomerDraft?> _showCustomerForm(
  BuildContext context, {
  required String title,
  String? initialName,
  String? initialPhone,
  bool initialDebtEnabled = false,
}) {
  return showDialog<CustomerDraft>(
    context: context,
    builder: (dialogContext) => _CustomerFormDialog(
      title: title,
      initialName: initialName,
      initialPhone: initialPhone,
      initialDebtEnabled: initialDebtEnabled,
    ),
  );
}

class _CustomerFormDialog extends StatefulWidget {
  const _CustomerFormDialog({
    required this.title,
    this.initialName,
    this.initialPhone,
    this.initialDebtEnabled = false,
  });

  final String title;
  final String? initialName;
  final String? initialPhone;
  final bool initialDebtEnabled;

  @override
  State<_CustomerFormDialog> createState() => _CustomerFormDialogState();
}

class _CustomerFormDialogState extends State<_CustomerFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _phoneController;
  bool _debtEnabled = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.initialName ?? '');
    _phoneController = TextEditingController(text: widget.initialPhone ?? '');
    _debtEnabled = widget.initialDebtEnabled;
  }

  @override
  void dispose() {
    // Owned here rather than in the calling function, so the controllers are
    // released only after the child TextFormFields have unregistered from them.
    _nameController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  void _submit() {
    if (_saving) return;
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    final rawPhone = _phoneController.text.trim();
    Navigator.of(context).pop(
      CustomerDraft(
        name: _nameController.text.trim(),
        phone: rawPhone.isEmpty ? null : rawPhone,
        debtEnabled: _debtEnabled,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
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
                Switch(
                  value: _debtEnabled,
                  onChanged:
                      _saving ? null : (v) => setState(() => _debtEnabled = v),
                ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
          child: const Text('إلغاء'),
        ),
        FilledButton(
          onPressed: _saving ? null : _submit,
          child: _saving
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('حفظ'),
        ),
      ],
    );
  }
}

/// Shows the add-customer dialog, then performs the Firestore write.
///
/// Returns `true` only when a customer was actually created, so the caller can
/// decide whether a list refresh is warranted. Cancel returns `false` and
/// performs no Firestore work at all.
Future<bool> showAddCustomerDialog(
  BuildContext context,
  String storeId,
  String createdBy,
) async {
  final draft = await _showCustomerForm(context, title: 'إضافة عميل');
  if (draft == null) return false;
  try {
    await CustomerRepository().createCustomer(
      storeId: storeId,
      name: draft.name,
      phone: draft.phone,
      debtEnabled: draft.debtEnabled,
      createdBy: createdBy,
    );
    if (!context.mounted) return true;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('تم إضافة العميل بنجاح')),
    );
    return true;
  } on CustomerAlreadyExistsException {
    if (!context.mounted) return false;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('اسم العميل مستخدم بالفعل')),
    );
    return false;
  } catch (_) {
    if (!context.mounted) return false;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('تعذر إضافة العميل. تحقق من الاتصال وحاول مرة أخرى.'),
      ),
    );
    return false;
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
  if (!context.mounted) return;
  final draft = await _showCustomerForm(
    context,
    title: 'تعديل عميل',
    initialName: customer.name,
    initialPhone: customer.phone,
    initialDebtEnabled: customer.debtEnabled,
  );
  if (draft == null) return;
  try {
    await repo.updateCustomer(
      storeId: storeId,
      customerId: customerId,
      name: draft.name,
      phone: draft.phone,
      debtEnabled: draft.debtEnabled,
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
