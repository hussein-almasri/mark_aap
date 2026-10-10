import 'package:cloud_firestore/cloud_firestore.dart' show Timestamp;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/utils/price_amount.dart';
import '../../../data/models/purchase_invoice_model.dart';
import '../../../data/models/user_model.dart';
import '../../../data/repositories/purchase_invoice_repository.dart';
import 'purchase_invoice_details_screen.dart';
import 'purchase_invoice_form_screen.dart';

/// Lists the store's purchase invoices and routes to create/details.
///
/// Both admins and employees can view and create invoices — the Firestore
/// rules gate both on `isFinancialStoreMember`, so no extra role check is
/// applied here beyond what the rules enforce.
class PurchaseInvoiceListScreen extends StatefulWidget {
  const PurchaseInvoiceListScreen({
    required this.user,
    this.repository,
    super.key,
  });

  final UserModel user;
  final PurchaseInvoiceRepository? repository;

  @override
  State<PurchaseInvoiceListScreen> createState() =>
      _PurchaseInvoiceListScreenState();
}

class _PurchaseInvoiceListScreenState extends State<PurchaseInvoiceListScreen> {
  late final PurchaseInvoiceRepository _repository =
      widget.repository ?? PurchaseInvoiceRepository();

  List<PurchaseInvoiceModel>? _invoices;
  bool _isLoading = true;
  String? _loadError;
  bool _isOpeningForm = false;

  @override
  void initState() {
    super.initState();
    _loadInvoices();
  }

  Future<void> _loadInvoices() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _loadError = null;
    });
    try {
      final invoices = await _repository.listInvoices(widget.user.storeId);
      if (!mounted) return;
      setState(() {
        _invoices = invoices;
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loadError = 'تعذر تحميل قائمة فواتير المشتريات.';
        _isLoading = false;
      });
    }
  }

  Future<void> _openCreateForm() async {
    // Keep the entry point disabled for the whole create + reload window so a
    // second form cannot be opened on top of the first.
    if (_isOpeningForm) return;
    setState(() => _isOpeningForm = true);
    try {
      final created = await Navigator.of(context).push<bool>(
        MaterialPageRoute(
          builder: (_) => PurchaseInvoiceFormScreen(user: widget.user),
        ),
      );
      // Only refresh after an actual create; cancelling must not reload.
      if (created == true && mounted) await _loadInvoices();
    } finally {
      if (mounted) setState(() => _isOpeningForm = false);
    }
  }

  void _openDetails(PurchaseInvoiceModel invoice) {
    Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => PurchaseInvoiceDetailsScreen(
          user: widget.user,
          invoiceId: invoice.invoiceId,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('فواتير المشتريات')),
      floatingActionButton: _invoices == null || _loadError != null
          ? null
          : FloatingActionButton.extended(
              onPressed: _isOpeningForm ? null : _openCreateForm,
              icon: const Icon(Icons.add),
              label: const Text('فاتورة جديدة'),
            ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _loadError != null
          ? _buildLoadFailure()
          : _buildInvoiceList(),
    );
  }

  Widget _buildLoadFailure() => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(_loadError!),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: _loadInvoices,
            child: const Text('إعادة المحاولة'),
          ),
        ],
      ),
    ),
  );

  Widget _buildInvoiceList() {
    final invoices = _invoices!;
    if (invoices.isEmpty) {
      return const Center(child: Text('لا توجد فواتير مشتريات بعد.'));
    }
    final sorted = [...invoices]
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
      itemCount: sorted.length,
      itemBuilder: (context, index) => _buildInvoiceCard(sorted[index]),
    );
  }

  Widget _buildInvoiceCard(PurchaseInvoiceModel invoice) {
    final isActive = invoice.status == PurchaseInvoiceStatus.active;
    final statusLabel = isActive ? 'نشطة' : 'ملغاة';
    final statusColor = isActive
        ? Theme.of(context).colorScheme.primary
        : Theme.of(context).colorScheme.error;
    final supplierNumber = invoice.supplierInvoiceNumber;

    return Card(
      child: ListTile(
        title: Text(invoice.companyName),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (supplierNumber != null && supplierNumber.isNotEmpty)
              Text('رقم فاتورة المورد: $supplierNumber'),
            Text(
              '${PriceAmount.formatJod2(invoice.totalAmountFils)}'
              ' • ${_formatDate(invoice.createdAt)}',
            ),
          ],
        ),
        trailing: Text(
          statusLabel,
          style: TextStyle(color: statusColor, fontWeight: FontWeight.w600),
        ),
        onTap: () => _openDetails(invoice),
      ),
    );
  }

  String _formatDate(Timestamp timestamp) =>
      DateFormat('dd/MM/yyyy - HH:mm').format(timestamp.toDate());
}
