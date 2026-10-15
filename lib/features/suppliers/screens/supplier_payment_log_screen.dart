import 'package:cloud_firestore/cloud_firestore.dart' show Timestamp;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/utils/price_amount.dart';
import '../../../data/models/supplier_payment_model.dart';
import '../../../data/models/user_model.dart';
import '../../../data/repositories/supplier_payment_repository.dart';
import 'supplier_payment_details_screen.dart';

/// Lists the store's supplier payments, newest first.
///
/// Both admins and employees can view payments — the Firestore rules gate both
/// on `isFinancialStoreMember`, so no extra role check is applied here beyond
/// what the rules enforce. Tapping a payment routes to the read-only details
/// screen; this screen offers no cancel action.
class SupplierPaymentLogScreen extends StatefulWidget {
  const SupplierPaymentLogScreen({
    required this.user,
    this.repository,
    super.key,
  });

  final UserModel user;
  final SupplierPaymentRepository? repository;

  @override
  State<SupplierPaymentLogScreen> createState() =>
      _SupplierPaymentLogScreenState();
}

class _SupplierPaymentLogScreenState extends State<SupplierPaymentLogScreen> {
  late final SupplierPaymentRepository _repository =
      widget.repository ?? SupplierPaymentRepository();

  List<SupplierPaymentModel>? _payments;
  bool _isLoading = true;
  String? _loadError;

  @override
  void initState() {
    super.initState();
    _loadPayments();
  }

  Future<void> _loadPayments() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _loadError = null;
    });
    try {
      final payments = await _repository.listPayments(widget.user.storeId);
      if (!mounted) return;
      setState(() {
        _payments = payments;
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loadError = 'تعذر تحميل سجل دفعات الموردين.';
        _isLoading = false;
      });
    }
  }

  void _openDetails(SupplierPaymentModel payment) {
    Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => SupplierPaymentDetailsScreen(
          user: widget.user,
          paymentId: payment.paymentId,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('سجل دفعات الموردين')),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _loadError != null
          ? _buildLoadFailure()
          : _buildPaymentList(),
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
            onPressed: _loadPayments,
            child: const Text('إعادة المحاولة'),
          ),
        ],
      ),
    ),
  );

  Widget _buildPaymentList() {
    final payments = _payments!;
    if (payments.isEmpty) {
      return const Center(child: Text('لا توجد دفعات مسجلة بعد.'));
    }
    // `listPayments` returns oldest-first; reverse for newest-first display.
    final sorted = [...payments]
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      itemCount: sorted.length,
      itemBuilder: (context, index) => _buildPaymentCard(sorted[index]),
    );
  }

  Widget _buildPaymentCard(SupplierPaymentModel payment) {
    final isActive = payment.status == SupplierPaymentStatus.active;
    final statusLabel = isActive ? 'نشطة' : 'ملغاة';
    final statusColor = isActive
        ? Theme.of(context).colorScheme.primary
        : Theme.of(context).colorScheme.error;
    return Card(
      child: ListTile(
        title: Text(payment.companyName),
        subtitle: Text(
          '${PriceAmount.formatJod2(payment.amountFils)}'
          ' • ${_sourceLabel(payment.source)}'
          ' • ${_formatDate(payment.createdAt)}',
        ),
        trailing: Text(
          statusLabel,
          style: TextStyle(color: statusColor, fontWeight: FontWeight.w600),
        ),
        onTap: () => _openDetails(payment),
      ),
    );
  }

  String _sourceLabel(SupplierPaymentSource source) => switch (source) {
    SupplierPaymentSource.shopCash => 'كاش الصندوق',
    SupplierPaymentSource.outsideCash => 'كاش خارج الصندوق',
  };

  String _formatDate(Timestamp timestamp) =>
      DateFormat('dd/MM/yyyy - HH:mm').format(timestamp.toDate());
}
