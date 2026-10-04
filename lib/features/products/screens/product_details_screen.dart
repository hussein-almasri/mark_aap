import 'package:flutter/material.dart';

import '../../../core/utils/price_amount.dart';
import '../../../data/models/price_history_model.dart';
import '../../../data/models/product_model.dart';
import '../../../data/models/user_model.dart';
import '../../../data/repositories/product_price_repository.dart';
import 'product_form_screen.dart';

class ProductDetailsScreen extends StatefulWidget {
  const ProductDetailsScreen({
    required this.user,
    required this.product,
    super.key,
  });

  final UserModel user;
  final ProductModel product;

  @override
  State<ProductDetailsScreen> createState() => _ProductDetailsScreenState();
}

class _ProductDetailsScreenState extends State<ProductDetailsScreen> {
  final _prices = ProductPriceRepository();
  bool _priceOperationInProgress = false;

  Future<void> _changePrice({required bool selling}) async {
    if (_priceOperationInProgress) return;
    setState(() => _priceOperationInProgress = true);
    try {
      final amount = await showDialog<int>(
        context: context,
        builder: (_) => _PriceEditDialog(selling: selling),
      );
      if (amount == null || !mounted) return;

      if (selling) {
        await _prices.changeSellingPrice(
          storeId: widget.user.storeId,
          productId: widget.product.id,
          userId: widget.user.uid,
          sellingPrice: amount,
        );
      } else {
        await _prices.changePurchasePrice(
          storeId: widget.user.storeId,
          productId: widget.product.id,
          userId: widget.user.uid,
          purchasePrice: amount,
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('تعذر تغيير السعر: $error')));
      }
    } finally {
      if (mounted) {
        setState(() => _priceOperationInProgress = false);
      }
    }
  }

  Future<void> _showHistory() async {
    try {
      final history = await _prices.getPriceHistory(
        storeId: widget.user.storeId,
        productId: widget.product.id,
      );
      if (!mounted) return;
      await showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        builder: (context) => SafeArea(
          child: ListView(
            shrinkWrap: true,
            children: [
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text(
                  'سجل الأسعار',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
              ),
              if (history.isEmpty)
                const ListTile(title: Text('لا يوجد سجل أسعار')),
              for (final item in history)
                ListTile(
                  title: Text(
                    item.priceType == ProductPriceType.purchase
                        ? 'شراء'
                        : 'بيع',
                  ),
                  subtitle: Text(
                    item.createdAt?.toDate().toLocal().toString() ?? '',
                  ),
                  trailing: Text(PriceAmount.formatJod(item.price)),
                ),
            ],
          ),
        ),
      );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('تعذر تحميل سجل الأسعار: $error')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('تفاصيل المنتج'),
      actions: widget.user.isAdmin
          ? [
              IconButton(
                tooltip: 'تعديل المنتج',
                icon: const Icon(Icons.edit),
                onPressed: () => Navigator.of(context).push<void>(
                  MaterialPageRoute(
                    builder: (_) => ProductFormScreen(
                      user: widget.user,
                      product: widget.product,
                    ),
                  ),
                ),
              ),
            ]
          : null,
    ),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text(
          widget.product.name,
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 6),
        Text('الباركود: ${widget.product.barcode}'),
        const Divider(height: 32),
        FutureBuilder(
          future: _prices.getSellingPrice(
            storeId: widget.user.storeId,
            productId: widget.product.id,
          ),
          builder: (context, snapshot) => ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('سعر البيع'),
            trailing: Text(
              snapshot.hasData
                  ? PriceAmount.formatJod(snapshot.data!.sellingPrice)
                  : '—',
            ),
            onTap: widget.user.isAdmin && !_priceOperationInProgress
                ? () => _changePrice(selling: true)
                : null,
          ),
        ),
        if (widget.user.isAdmin) ...[
          FutureBuilder(
            future: _prices.getProductCost(
              storeId: widget.user.storeId,
              productId: widget.product.id,
            ),
            builder: (context, snapshot) => ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('سعر الشراء'),
              trailing: Text(
                snapshot.hasData
                    ? PriceAmount.formatJod(snapshot.data!.purchasePrice)
                    : '—',
              ),
              onTap: _priceOperationInProgress
                  ? null
                  : () => _changePrice(selling: false),
            ),
          ),
          OutlinedButton.icon(
            onPressed: _showHistory,
            icon: const Icon(Icons.history),
            label: const Text('عرض سجل الأسعار'),
          ),
        ],
      ],
    ),
  );
}

class _PriceEditDialog extends StatefulWidget {
  const _PriceEditDialog({required this.selling});

  final bool selling;

  @override
  State<_PriceEditDialog> createState() => _PriceEditDialogState();
}

class _PriceEditDialogState extends State<_PriceEditDialog> {
  final _controller = TextEditingController();
  bool _completed = false;

  void _cancel() {
    if (_completed) return;
    _completed = true;
    Navigator.of(context).pop<int>();
  }

  void _save() {
    if (_completed) return;
    try {
      final amount = PriceAmount.parseJodToFils(_controller.text);
      if (widget.selling && amount == 0) return;
      _completed = true;
      Navigator.of(context).pop(amount);
    } on FormatException {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('أدخل مبلغاً صحيحاً حتى ثلاثة منازل عشرية'),
        ),
      );
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.selling ? 'تغيير سعر البيع' : 'تغيير سعر الشراء'),
    content: TextField(
      controller: _controller,
      autofocus: true,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      decoration: const InputDecoration(labelText: 'المبلغ بالدينار الأردني'),
    ),
    actions: [
      TextButton(onPressed: _cancel, child: const Text('إلغاء')),
      FilledButton(onPressed: _save, child: const Text('حفظ')),
    ],
  );
}
