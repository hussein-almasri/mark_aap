import 'package:flutter/material.dart';

import '../../../core/utils/price_amount.dart';
import '../../../data/models/product_model.dart';
import '../../../data/models/user_model.dart';
import '../../../data/repositories/product_repository.dart';
import 'barcode_scanner_screen.dart';

class ProductFormScreen extends StatefulWidget {
  const ProductFormScreen({required this.user, this.product, super.key});

  final UserModel user;
  final ProductModel? product;

  @override
  State<ProductFormScreen> createState() => _ProductFormScreenState();
}

class _ProductFormScreenState extends State<ProductFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _barcode = TextEditingController();
  final _purchase = TextEditingController();
  final _selling = TextEditingController();
  final _products = ProductRepository();
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _name.text = widget.product?.name ?? '';
    _barcode.text = widget.product?.barcode ?? '';
  }

  @override
  void dispose() {
    _name.dispose();
    _barcode.dispose();
    _purchase.dispose();
    _selling.dispose();
    super.dispose();
  }

  String? _validatePrice(String? value, {required bool allowZero}) {
    try {
      final amount = PriceAmount.parseJodToFils(value ?? '');
      if (!allowZero && amount == 0) return 'يجب أن يكون السعر أكبر من صفر';
      return null;
    } on FormatException {
      return 'أدخل مبلغاً صحيحاً بالدينار الأردني';
    }
  }

  Future<void> _scanBarcode() async {
    final barcode = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const BarcodeScannerScreen()),
    );
    if (barcode != null && mounted) _barcode.text = barcode;
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      if (widget.product == null) {
        await _products.createProduct(
          storeId: widget.user.storeId,
          userId: widget.user.uid,
          name: _name.text,
          barcode: _barcode.text,
          purchasePrice: PriceAmount.parseJodToFils(_purchase.text),
          sellingPrice: PriceAmount.parseJodToFils(_selling.text),
        );
      } else {
        await _products.updateProduct(
          storeId: widget.user.storeId,
          productId: widget.product!.id,
          name: _name.text,
          barcode: _barcode.text,
        );
      }
      if (mounted) Navigator.of(context).pop();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('تعذر حفظ المنتج: $error')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isNew = widget.product == null;
    return Scaffold(
      appBar: AppBar(title: Text(isNew ? 'إضافة منتج' : 'تعديل المنتج')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            TextFormField(
              controller: _name,
              maxLength: 120,
              decoration: const InputDecoration(
                labelText: 'اسم المنتج',
                border: OutlineInputBorder(),
              ),
              validator: (value) => value == null || value.trim().isEmpty
                  ? 'اسم المنتج مطلوب'
                  : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _barcode,
              maxLength: 128,
              keyboardType: TextInputType.text,
              decoration: InputDecoration(
                labelText: 'الباركود',
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  tooltip: 'مسح الباركود',
                  icon: const Icon(Icons.qr_code_scanner),
                  onPressed: _scanBarcode,
                ),
              ),
              validator: (value) => value == null || value.trim().isEmpty
                  ? 'الباركود مطلوب'
                  : null,
            ),
            if (isNew) ...[
              const SizedBox(height: 12),
              TextFormField(
                controller: _purchase,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  labelText: 'سعر الشراء (د.أ)',
                  border: OutlineInputBorder(),
                ),
                validator: (value) => _validatePrice(value, allowZero: true),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _selling,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  labelText: 'سعر البيع (د.أ)',
                  border: OutlineInputBorder(),
                ),
                validator: (value) => _validatePrice(value, allowZero: false),
              ),
            ],
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _saving ? null : _save,
              child: _saving
                  ? const SizedBox.square(
                      dimension: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('حفظ'),
            ),
          ],
        ),
      ),
    );
  }
}
