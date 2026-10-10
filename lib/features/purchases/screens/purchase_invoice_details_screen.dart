import 'package:cloud_firestore/cloud_firestore.dart' show Timestamp;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/utils/price_amount.dart';
import '../../../data/models/purchase_invoice_model.dart';
import '../../../data/models/user_model.dart';
import '../../../data/repositories/purchase_invoice_repository.dart';

/// Read-only detail view of one purchase invoice.
///
/// Shows the total, the three-way split, notes, company data, date and status.
/// Deliberately has **no** cancel button: the cancellation path is not built or
/// tested yet, so exposing it here would offer an action the rules and
/// repository cannot yet back.
class PurchaseInvoiceDetailsScreen extends StatefulWidget {
  const PurchaseInvoiceDetailsScreen({
    required this.user,
    required this.invoiceId,
    this.repository,
    super.key,
  });

  final UserModel user;
  final String invoiceId;
  final PurchaseInvoiceRepository? repository;

  @override
  State<PurchaseInvoiceDetailsScreen> createState() =>
      _PurchaseInvoiceDetailsScreenState();
}

class _PurchaseInvoiceDetailsScreenState
    extends State<PurchaseInvoiceDetailsScreen> {
  late final PurchaseInvoiceRepository _repository =
      widget.repository ?? PurchaseInvoiceRepository();

  PurchaseInvoiceModel? _invoice;
  bool _isLoading = true;
  String? _loadError;

  @override
  void initState() {
    super.initState();
    _loadInvoice();
  }

  Future<void> _loadInvoice() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _loadError = null;
    });
    try {
      final invoice = await _repository.getInvoice(
        widget.user.storeId,
        widget.invoiceId,
      );
      if (!mounted) return;
      setState(() {
        _invoice = invoice;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadError = _describeError(e);
        _isLoading = false;
      });
    }
  }

  /// Surfaces only the failure kind — never document contents or ids.
  String _describeError(Object error) {
    final text = error.toString().toLowerCase();
    if (text.contains('permission') || text.contains('insufficient')) {
      return 'لا توجد صلاحية لعرض هذه الفاتورة';
    }
    if (text.contains('not found') || text.contains('does not exist')) {
      return 'الفاتورة غير موجودة';
    }
    if (text.contains('unavailable') ||
        text.contains('network') ||
        text.contains('timeout')) {
      return 'تعذر الاتصال بالخادم. تحقق من اتصال الإنترنت';
    }
    return 'تعذر تحميل الفاتورة. حاول مرة أخرى';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('تفاصيل الفاتورة')),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _loadError != null
          ? _buildLoadFailure()
          : _buildDetails(),
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
            onPressed: _loadInvoice,
            child: const Text('إعادة المحاولة'),
          ),
        ],
      ),
    ),
  );

  Widget _buildDetails() {
    final invoice = _invoice!;
    final isActive = invoice.status == PurchaseInvoiceStatus.active;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeaderCard(invoice, isActive),
          const SizedBox(height: 16),
          _buildSplitCard(invoice),
          if (invoice.notes != null && invoice.notes!.isNotEmpty) ...[
            const SizedBox(height: 16),
            _buildNotesCard(invoice),
          ],
        ],
      ),
    );
  }

  Widget _buildHeaderCard(PurchaseInvoiceModel invoice, bool isActive) {
    final supplierNumber = invoice.supplierInvoiceNumber;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    invoice.companyName,
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                Text(
                  isActive ? 'نشطة' : 'ملغاة',
                  style: TextStyle(
                    color: isActive
                        ? Theme.of(context).colorScheme.primary
                        : Theme.of(context).colorScheme.error,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _infoRow(Icons.business_outlined, 'الشركة: ${invoice.companyName}'),
            if (supplierNumber != null && supplierNumber.isNotEmpty)
              _infoRow(
                Icons.confirmation_number_outlined,
                'رقم فاتورة المورد: $supplierNumber',
              ),
            _infoRow(
              Icons.calendar_today_outlined,
              'التاريخ: ${_formatDate(invoice.createdAt)}',
            ),
            _infoRow(Icons.person_outline, 'أُنشئت بواسطة: ${invoice.createdBy}'),
          ],
        ),
      ),
    );
  }

  Widget _buildSplitCard(PurchaseInvoiceModel invoice) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'الإجمالي والتقسيم',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
          const Divider(),
          _amountRow('الإجمالي', invoice.totalAmountFils, bold: true),
          _amountRow('كاش الصندوق', invoice.shopCashAmountFils),
          _amountRow('كاش خارج الصندوق', invoice.outsideCashAmountFils),
          _amountRow('دين المورد', invoice.supplierDebtAmountFils),
        ],
      ),
    ),
  );

  Widget _buildNotesCard(PurchaseInvoiceModel invoice) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'ملاحظات',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          Text(invoice.notes!),
        ],
      ),
    ),
  );

  Widget _infoRow(IconData icon, String text) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Row(
      children: [
        Icon(icon, size: 18),
        const SizedBox(width: 6),
        Expanded(child: Text(text)),
      ],
    ),
  );

  Widget _amountRow(String label, int fils, {bool bold = false}) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: TextStyle(fontWeight: bold ? FontWeight.w700 : FontWeight.w400),
          ),
        ),
        Text(
          PriceAmount.formatJod2(fils),
          style: TextStyle(fontWeight: bold ? FontWeight.w700 : FontWeight.w500),
        ),
      ],
    ),
  );

  String _formatDate(Timestamp timestamp) =>
      DateFormat('dd/MM/yyyy - HH:mm').format(timestamp.toDate());
}
