import 'package:cloud_firestore/cloud_firestore.dart' show Timestamp;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/utils/price_amount.dart';
import '../../../data/models/company_model.dart';
import '../../../data/models/supplier_debt_model.dart';
import '../../../data/models/user_model.dart';
import '../../../data/repositories/company_repository.dart';
import '../../../data/repositories/supplier_payment_repository.dart';
import 'supplier_payment_form_screen.dart';
import 'supplier_payment_log_screen.dart';

/// Lists a supplier's outstanding debts, one step before recording a payment.
///
/// Two states in one screen: when no company is chosen it shows the store's
/// active companies; picking one loads that company's debts that still have a
/// balance (`listOpenDebtsForCompany`). Selecting a company with debts exposes
/// a FAB to record a payment, and the app bar links to the payment log. There
/// is deliberately no cancel action here.
class SupplierDebtListScreen extends StatefulWidget {
  const SupplierDebtListScreen({
    required this.user,
    this.paymentRepository,
    this.companyRepository,
    super.key,
  });

  final UserModel user;
  final SupplierPaymentRepository? paymentRepository;
  final CompanyRepository? companyRepository;

  @override
  State<SupplierDebtListScreen> createState() => _SupplierDebtListScreenState();
}

class _SupplierDebtListScreenState extends State<SupplierDebtListScreen> {
  late final SupplierPaymentRepository _paymentRepository =
      widget.paymentRepository ?? SupplierPaymentRepository();
  late final CompanyRepository _companyRepository =
      widget.companyRepository ?? CompanyRepository();

  List<CompanyModel>? _companies;
  bool _isLoadingCompanies = true;
  String? _companiesError;

  CompanyModel? _selectedCompany;
  List<SupplierDebtModel>? _debts;
  bool _isLoadingDebts = false;
  String? _debtsError;
  bool _isOpeningForm = false;

  @override
  void initState() {
    super.initState();
    _loadCompanies();
  }

  Future<void> _loadCompanies() async {
    if (!mounted) return;
    setState(() {
      _isLoadingCompanies = true;
      _companiesError = null;
    });
    try {
      final companies = await _companyRepository.listActiveCompanies(
        widget.user.storeId,
      );
      if (!mounted) return;
      setState(() {
        _companies = companies;
        _isLoadingCompanies = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _companiesError = 'تعذر تحميل قائمة الموردين.';
        _isLoadingCompanies = false;
      });
    }
  }

  Future<void> _selectCompany(CompanyModel company) async {
    setState(() {
      _selectedCompany = company;
      _debts = null;
      _debtsError = null;
      _isLoadingDebts = true;
    });
    try {
      final debts = await _paymentRepository.listOpenDebtsForCompany(
        widget.user.storeId,
        company.companyId,
      );
      if (!mounted) return;
      setState(() {
        _debts = debts;
        _isLoadingDebts = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _debtsError = 'تعذر تحميل ديون المورد.';
        _isLoadingDebts = false;
      });
    }
  }

  void _clearSelection() {
    setState(() {
      _selectedCompany = null;
      _debts = null;
      _debtsError = null;
      _isLoadingDebts = false;
    });
  }

  Future<void> _openCreateForm() async {
    final company = _selectedCompany;
    if (company == null || _isOpeningForm) return;
    // Keep the entry point disabled for the whole create + reload window so a
    // second form cannot be opened on top of the first.
    setState(() => _isOpeningForm = true);
    try {
      final created = await Navigator.of(context).push<bool>(
        MaterialPageRoute(
          builder: (_) => SupplierPaymentFormScreen(
            user: widget.user,
            companyId: company.companyId,
            companyName: company.name,
            paymentRepository: widget.paymentRepository,
          ),
        ),
      );
      // Only refresh after an actual create; cancelling must not reload.
      if (created == true && mounted) await _selectCompany(company);
    } finally {
      if (mounted) setState(() => _isOpeningForm = false);
    }
  }

  void _openLog() {
    Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => SupplierPaymentLogScreen(
          user: widget.user,
          repository: widget.paymentRepository,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          _selectedCompany?.name ?? 'ديون ودفعات الموردين',
        ),
        leading: _selectedCompany == null
            ? null
            : IconButton(
                icon: const Icon(Icons.arrow_forward),
                onPressed: _clearSelection,
              ),
        actions: [
          IconButton(
            icon: const Icon(Icons.receipt_long_outlined),
            tooltip: 'سجل الدفعات',
            onPressed: _openLog,
          ),
        ],
      ),
      floatingActionButton: _buildPaymentFab(),
      body: _buildBody(),
    );
  }

  Widget? _buildPaymentFab() {
    final debts = _debts;
    if (_selectedCompany == null ||
        _isLoadingDebts ||
        _debtsError != null ||
        debts == null ||
        debts.isEmpty) {
      return null;
    }
    return FloatingActionButton.extended(
      onPressed: _isOpeningForm ? null : _openCreateForm,
      icon: const Icon(Icons.add),
      label: const Text('تسجيل دفعة'),
    );
  }

  Widget _buildBody() {
    if (_selectedCompany != null) return _buildDebtView();
    return _buildCompanyView();
  }

  Widget _buildCompanyView() {
    if (_isLoadingCompanies) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_companiesError != null) return _buildCompanyFailure();
    final companies = _companies!;
    if (companies.isEmpty) {
      return const Center(child: Text('لا توجد شركات نشطة بعد.'));
    }
    final sorted = [...companies]
      ..sort((a, b) => a.name.compareTo(b.name));
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      itemCount: sorted.length,
      itemBuilder: (context, index) => _buildCompanyCard(sorted[index]),
    );
  }

  Widget _buildCompanyFailure() => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(_companiesError!),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: _loadCompanies,
            child: const Text('إعادة المحاولة'),
          ),
        ],
      ),
    ),
  );

  Widget _buildCompanyCard(CompanyModel company) => Card(
    child: ListTile(
      title: Text(company.name),
      subtitle: company.phone != null && company.phone!.isNotEmpty
          ? Text(company.phone!)
          : null,
      trailing: const Icon(Icons.chevron_left),
      onTap: () => _selectCompany(company),
    ),
  );

  Widget _buildDebtView() {
    if (_isLoadingDebts) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_debtsError != null) return _buildDebtFailure();
    final debts = _debts!;
    if (debts.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text('لا توجد ديون متبقية لهذا المورد.'),
        ),
      );
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      children: [
        _buildSummaryCard(debts),
        const SizedBox(height: 12),
        ...debts.map(_buildDebtCard),
      ],
    );
  }

  Widget _buildDebtFailure() => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(_debtsError!),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: () => _selectCompany(_selectedCompany!),
            child: const Text('إعادة المحاولة'),
          ),
        ],
      ),
    ),
  );

  Widget _buildSummaryCard(List<SupplierDebtModel> debts) {
    final totalRemaining = debts.fold<int>(
      0,
      (sum, debt) => sum + debt.remainingAmountFils,
    );
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'إجمالي الرصيد المتبقي',
                    style: TextStyle(fontSize: 14, color: Colors.grey),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    PriceAmount.formatJod2(totalRemaining),
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
            Text(
              '${debts.length} فاتورة',
              style: const TextStyle(fontSize: 14, color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDebtCard(SupplierDebtModel debt) {
    final statusLabel = _statusLabel(debt.status);
    final statusColor = debt.status == SupplierDebtStatus.open
        ? Theme.of(context).colorScheme.primary
        : Theme.of(context).colorScheme.error;
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
                    'فاتورة: ${debt.invoiceId}',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Text(
                  statusLabel,
                  style: TextStyle(
                    color: statusColor,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            _amountRow('المبلغ الأصلي', debt.originalAmountFils),
            _amountRow('المتبقي', debt.remainingAmountFils, bold: true),
            const SizedBox(height: 4),
            Text(
              'تاريخ الإنشاء: ${_formatDate(debt.createdAt)}',
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }

  Widget _amountRow(String label, int fils, {bool bold = false}) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 2),
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

  String _statusLabel(SupplierDebtStatus status) => switch (status) {
    SupplierDebtStatus.open => 'مفتوحة',
    SupplierDebtStatus.paid => 'مسددة',
    SupplierDebtStatus.cancelled => 'ملغاة',
  };

  String _formatDate(Timestamp timestamp) =>
      DateFormat('dd/MM/yyyy - HH:mm').format(timestamp.toDate());
}
