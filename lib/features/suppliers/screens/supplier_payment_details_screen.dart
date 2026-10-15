import 'package:cloud_firestore/cloud_firestore.dart' show Timestamp;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/utils/price_amount.dart';
import '../../../data/models/supplier_payment_model.dart';
import '../../../data/models/user_model.dart';
import '../../../data/repositories/supplier_payment_repository.dart';

/// Read-only detail view of one supplier payment.
///
/// Shows the payment amount, the source, status and date, and how the amount
/// was allocated across up to 5 invoices (invoice id + per-allocation amount).
/// Deliberately has **no** cancel button: the cancellation path is not built or
/// tested yet, so exposing it here would offer an action the rules and
/// repository cannot yet back.
class SupplierPaymentDetailsScreen extends StatefulWidget {
  const SupplierPaymentDetailsScreen({
    required this.user,
    required this.paymentId,
    this.repository,
    super.key,
  });

  final UserModel user;
  final String paymentId;
  final SupplierPaymentRepository? repository;

  @override
  State<SupplierPaymentDetailsScreen> createState() =>
      _SupplierPaymentDetailsScreenState();
}

class _SupplierPaymentDetailsScreenState
    extends State<SupplierPaymentDetailsScreen> {
  late final SupplierPaymentRepository _repository =
      widget.repository ?? SupplierPaymentRepository();

  SupplierPaymentModel? _payment;
  bool _isLoading = true;
  String? _loadError;

  @override
  void initState() {
    super.initState();
    _loadPayment();
  }

  Future<void> _loadPayment() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _loadError = null;
    });
    try {
      final payment = await _repository.getPayment(
        widget.user.storeId,
        widget.paymentId,
      );
      if (!mounted) return;
      setState(() {
        _payment = payment;
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
      return 'لا توجد صلاحية لعرض هذه الدفعة';
    }
    if (text.contains('not found') || text.contains('does not exist')) {
      return 'الدفعة غير موجودة';
    }
    if (text.contains('unavailable') ||
        text.contains('network') ||
        text.contains('timeout')) {
      return 'تعذر الاتصال بالخادم. تحقق من اتصال الإنترنت';
    }
    return 'تعذر تحميل الدفعة. حاول مرة أخرى';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('تفاصيل الدفعة')),
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
            onPressed: _loadPayment,
            child: const Text('إعادة المحاولة'),
          ),
        ],
      ),
    ),
  );

  Widget _buildDetails() {
    final payment = _payment!;
    final isActive = payment.status == SupplierPaymentStatus.active;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeaderCard(payment, isActive),
          const SizedBox(height: 16),
          _buildAllocationCard(payment),
          if (payment.notes != null && payment.notes!.isNotEmpty) ...[
            const SizedBox(height: 16),
            _buildNotesCard(payment),
          ],
        ],
      ),
    );
  }

  Widget _buildHeaderCard(SupplierPaymentModel payment, bool isActive) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  payment.companyName,
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
          _infoRow(
            Icons.payments_outlined,
            'المبلغ: ${PriceAmount.formatJod2(payment.amountFils)}',
          ),
          _infoRow(Icons.account_balance_outlined, 'المصدر: ${_sourceLabel(payment.source)}'),
          _infoRow(
            Icons.calendar_today_outlined,
            'التاريخ: ${_formatDate(payment.createdAt)}',
          ),
        ],
      ),
    ),
  );

  Widget _buildAllocationCard(SupplierPaymentModel payment) {
    final allocations = _allocationEntries(payment);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'توزيع الدفعة على الفواتير (${payment.allocationCount})',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            const Divider(),
            ...allocations.map(_buildAllocationRow),
            const Divider(),
            _amountRow('إجمالي المخصص', payment.allocationTotalFils, bold: true),
          ],
        ),
      ),
    );
  }

  Widget _buildAllocationRow(({String invoiceId, int amountFils}) entry) =>
      _amountRow('فاتورة ${entry.invoiceId}', entry.amountFils);

  /// Extracts the populated allocation slots in order, up to [allocationCount].
  List<({String invoiceId, int amountFils})> _allocationEntries(
    SupplierPaymentModel payment,
  ) {
    final all = [
      (invoiceId: payment.allocation1InvoiceId, amountFils: payment.allocation1AmountFils),
      if (payment.allocation2InvoiceId != null)
        (
          invoiceId: payment.allocation2InvoiceId!,
          amountFils: payment.allocation2AmountFils ?? 0,
        ),
      if (payment.allocation3InvoiceId != null)
        (
          invoiceId: payment.allocation3InvoiceId!,
          amountFils: payment.allocation3AmountFils ?? 0,
        ),
      if (payment.allocation4InvoiceId != null)
        (
          invoiceId: payment.allocation4InvoiceId!,
          amountFils: payment.allocation4AmountFils ?? 0,
        ),
      if (payment.allocation5InvoiceId != null)
        (
          invoiceId: payment.allocation5InvoiceId!,
          amountFils: payment.allocation5AmountFils ?? 0,
        ),
    ];
    return all.take(payment.allocationCount).toList();
  }

  Widget _buildNotesCard(SupplierPaymentModel payment) => Card(
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
          Text(payment.notes!),
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
            style: TextStyle(
              fontWeight: bold ? FontWeight.w700 : FontWeight.w400,
            ),
          ),
        ),
        Text(
          PriceAmount.formatJod2(fils),
          style: TextStyle(
            fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
      ],
    ),
  );

  String _sourceLabel(SupplierPaymentSource source) => switch (source) {
    SupplierPaymentSource.shopCash => 'كاش الصندوق',
    SupplierPaymentSource.outsideCash => 'كاش خارج الصندوق',
  };

  String _formatDate(Timestamp timestamp) =>
      DateFormat('dd/MM/yyyy - HH:mm').format(timestamp.toDate());
}
