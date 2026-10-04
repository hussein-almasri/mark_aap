import 'package:flutter/material.dart';

import '../../../data/models/product_model.dart';
import '../../../data/models/user_model.dart';
import '../../../data/repositories/product_price_repository.dart';
import '../../../data/repositories/product_repository.dart';
import '../../../core/utils/price_amount.dart';
import 'product_form_screen.dart';
import 'product_details_screen.dart';
import 'barcode_scanner_screen.dart';

class ProductListScreen extends StatefulWidget {
  const ProductListScreen({required this.user, super.key});

  final UserModel user;

  @override
  State<ProductListScreen> createState() => _ProductListScreenState();
}

class _ProductListScreenState extends State<ProductListScreen> {
  final _searchController = TextEditingController();
  final _products = ProductRepository();
  final _prices = ProductPriceRepository();
  late Future<List<ProductModel>> _result;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _result = _load();
  }

  Future<List<ProductModel>> _load() =>
      _products.searchProducts(storeId: widget.user.storeId, query: _query);

  void _search(String value) {
    setState(() {
      _query = value;
      _result = _load();
    });
  }

  Future<void> _openForm([ProductModel? product]) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => ProductFormScreen(user: widget.user, product: product),
      ),
    );
    if (mounted) _search(_query);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('المنتجات')),
      floatingActionButton: widget.user.isAdmin
          ? FloatingActionButton.extended(
              onPressed: () => _openForm(),
              icon: const Icon(Icons.add),
              label: const Text('إضافة منتج'),
            )
          : null,
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              controller: _searchController,
              textInputAction: TextInputAction.search,
              onSubmitted: _search,
              decoration: InputDecoration(
                hintText: 'ابحث بالاسم أو الباركود',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: IconButton(
                  tooltip: 'مسح الباركود',
                  icon: const Icon(Icons.qr_code_scanner),
                  onPressed: () async {
                    final barcode = await Navigator.of(context).push<String>(
                      MaterialPageRoute(
                        builder: (_) => const BarcodeScannerScreen(),
                      ),
                    );
                    if (barcode != null && mounted) {
                      _searchController.text = barcode;
                      _search(barcode);
                    }
                  },
                ),
                border: const OutlineInputBorder(),
              ),
            ),
          ),
          Expanded(
            child: FutureBuilder<List<ProductModel>>(
              future: _result,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return _Message(
                    text: 'تعذر تحميل المنتجات: ${snapshot.error}',
                  );
                }
                final items = snapshot.data ?? const <ProductModel>[];
                if (items.isEmpty) {
                  return const _Message(text: 'لا توجد منتجات');
                }
                return RefreshIndicator(
                  onRefresh: () async => _search(_query),
                  child: ListView.builder(
                    padding: const EdgeInsets.only(bottom: 88),
                    itemCount: items.length,
                    itemBuilder: (context, index) {
                      final product = items[index];
                      return ListTile(
                        title: Text(product.name),
                        subtitle: Text('الباركود: ${product.barcode}'),
                        trailing: FutureBuilder(
                          future: _prices.getSellingPrice(
                            storeId: widget.user.storeId,
                            productId: product.id,
                          ),
                          builder: (context, priceSnapshot) => Text(
                            priceSnapshot.hasData
                                ? PriceAmount.formatJod(
                                    priceSnapshot.data!.sellingPrice,
                                  )
                                : '—',
                          ),
                        ),
                        onTap: () => Navigator.of(context).push<void>(
                          MaterialPageRoute(
                            builder: (_) => ProductDetailsScreen(
                              user: widget.user,
                              product: product,
                            ),
                          ),
                        ),
                        onLongPress: widget.user.isAdmin
                            ? () => _openForm(product)
                            : null,
                      );
                    },
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(padding: const EdgeInsets.all(24), child: Text(text)),
  );
}
