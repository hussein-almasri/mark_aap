import 'package:flutter/material.dart';

import '../../../core/utils/price_amount.dart';
import '../../../data/models/company_model.dart';
import '../../../data/models/user_model.dart';
import '../../../data/repositories/company_repository.dart';
import '../../../data/repositories/purchase_invoice_repository.dart';
import '../purchase_invoice_form_validator.dart';

/// Full-screen form for creating a purchase invoice.
///
/// Only active companies can be selected. The user enters the total in JOD
/// (two decimals) and splits it across shop cash / outside cash / supplier
/// debt; the split is validated live against the total using integer فلس
/// arithmetic. Saving mints one [operationId] and delegates to the existing
/// `PurchaseInvoiceRepository.createInvoice` — no Firestore logic lives here.
class PurchaseInvoiceFormScreen extends StatefulWidget {
  const PurchaseInvoiceFormScreen({
    required this.user,
    this.invoiceRepository,
    this.companyRepository,
    super.key,
  });

  final UserModel user;
  final PurchaseInvoiceRepository? invoiceRepository;
  final CompanyRepository? companyRepository;

  @override
  State<PurchaseInvoiceFormScreen> createState() =>
      _PurchaseInvoiceFormScreenState();
}

class _PurchaseInvoiceFormScreenState extends State<PurchaseInvoiceFormScreen> {
  late final PurchaseInvoiceRepository _invoices =
      widget.invoiceRepository ?? PurchaseInvoiceRepository();
  late final CompanyRepository _companies =
      widget.companyRepository ?? CompanyRepository();

  final _formKey = GlobalKey<FormState>();
  final _totalController = TextEditingController();
  final _shopCashController = TextEditingController();
  final _outsideCashController = TextEditingController();
  final _supplierDebtController = TextEditingController();
  final _supplierNumberController = TextEditingController();
  final _notesController = TextEditingController();

  List<CompanyModel>? _activeCompanies;
  CompanyModel? _selectedCompany;
  bool _isLoadingCompanies = true;
  String? _companiesError;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    for (final controller in [
      _totalController,
      _shopCashController,
      _outsideCashController,
      _supplierDebtController,
    ]) {
      controller.addListener(_onAmountsChanged);
    }
    _loadCompanies();
  }

  void _onAmountsChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _totalController.dispose();
    _shopCashController.dispose();
    _outsideCashController.dispose();
    _supplierDebtController.dispose();
    _supplierNumberController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _loadCompanies() async {
    if (!mounted) return;
    setState(() {
      _isLoadingCompanies = true;
      _companiesError = null;
    });
    try {
      final companies = await _companies.listActiveCompanies(
        widget.user.storeId,
      );
      if (!mounted) return;
      setState(() {
        _activeCompanies = companies;
        _isLoadingCompanies = false;
        if (_selectedCompany == null && companies.isNotEmpty) {
          _selectedCompany = companies.first;
        }
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _companiesError = 'تعذر تحميل قائمة الشركات النشطة.';
        _isLoadingCompanies = false;
      });
    }
  }

  bool get _canSave =>
      !_isSaving &&
      !_isLoadingCompanies &&
      _companiesError == null &&
      (_activeCompanies?.isNotEmpty ?? false);

  Future<void> _save() async {
    if (!_canSave) return;
    if (!_formKey.currentState!.validate()) return;

    final company = _selectedCompany;
    if (company == null) {
      _showMessage('اختر شركة أولاً.');
      return;
    }

    final total = PurchaseInvoiceFormValidator.tryParseJodField(
      _totalController.text,
    );
    final shopCash = PurchaseInvoiceFormValidator.tryParseJodField(
      _shopCashController.text,
    );
    final outsideCash = PurchaseInvoiceFormValidator.tryParseJodField(
      _outsideCashController.text,
    );
    final supplierDebt = PurchaseInvoiceFormValidator.tryParseJodField(
      _supplierDebtController.text,
    );
    if (total == null || shopCash == null || outsideCash == null || supplierDebt == null) {
      _showMessage('تحقق من المبالغ المُدخلة.');
      return;
    }

    final splitError = PurchaseInvoiceFormValidator.validateSplit(
      totalFils: total,
      shopCashFils: shopCash,
      outsideCashFils: outsideCash,
      supplierDebtFils: supplierDebt,
    );
    if (splitError != null) {
      _showMessage(splitError);
      return;
    }

    setState(() => _isSaving = true);
    // Mint one operation id per confirmed submission so retrying this same
    // logical create cannot post a second invoice.
    final operationId = _invoices.newOperationId(widget.user.storeId);
    var succeeded = false;
    try {
      await _invoices.createInvoice(
        storeId: widget.user.storeId,
        companyId: company.companyId,
        companyName: company.name,
        totalAmountFils: total,
        shopCashAmountFils: shopCash,
        outsideCashAmountFils: outsideCash,
        supplierDebtAmountFils: supplierDebt,
        supplierInvoiceNumber: _cleanOptional(_supplierNumberController.text),
        notes: _cleanOptional(_notesController.text),
        photoIds: const [],
        createdBy: widget.user.uid,
        operationId: operationId,
      );
      succeeded = true;
      if (!mounted) return;
      _showMessage('تم إنشاء الفاتورة بنجاح');
      Navigator.of(context).pop(true);
    } on InvoiceAlreadyExistsException {
      _showMessage('تم إنشاء هذه الفاتورة مسبقاً؛ لم تُنشأ فاتورة جديدة.');
    } catch (_) {
      _showMessage('تعذر حفظ الفاتورة. تحقق من الاتصال وحاول مرة أخرى.');
    } finally {
      if (!succeeded && mounted) setState(() => _isSaving = false);
    }
  }

  static String? _cleanOptional(String value) {
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('فاتورة شراء جديدة')),
      body: SafeArea(
        child: _isLoadingCompanies
            ? const Center(child: CircularProgressIndicator())
            : _companiesError != null
            ? _buildCompaniesFailure()
            : (_activeCompanies?.isEmpty ?? true)
            ? const Center(child: Text('لا توجد شركات نشطة. أضف شركة أولاً.'))
            : _buildForm(),
      ),
      bottomNavigationBar: _buildSaveBar(),
    );
  }

  Widget _buildCompaniesFailure() => Center(
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

  Widget _buildForm() => Form(
    key: _formKey,
    child: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _buildCompanyField(),
        const SizedBox(height: 12),
        TextFormField(
          controller: _supplierNumberController,
          decoration: const InputDecoration(
            labelText: 'رقم فاتورة المورد (اختياري)',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        TextFormField(
          controller: _totalController,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(
            labelText: 'الإجمالي (د.أ)',
            hintText: 'مثال: 125.50',
            border: OutlineInputBorder(),
            suffixText: 'د.أ',
          ),
          validator: PurchaseInvoiceFormValidator.validateTotalField,
        ),
        const SizedBox(height: 16),
        const Text(
          'تقسيم الإجمالي',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        _buildSplitField(
          controller: _shopCashController,
          label: 'كاش الصندوق',
        ),
        const SizedBox(height: 12),
        _buildSplitField(
          controller: _outsideCashController,
          label: 'كاش خارج الصندوق',
        ),
        const SizedBox(height: 12),
        _buildSplitField(
          controller: _supplierDebtController,
          label: 'دين المورد',
        ),
        const SizedBox(height: 12),
        _buildSplitHint(),
        const SizedBox(height: 16),
        TextFormField(
          controller: _notesController,
          maxLength: 500,
          decoration: const InputDecoration(
            labelText: 'ملاحظات (اختياري)',
            border: OutlineInputBorder(),
          ),
        ),
      ],
    ),
  );

  Widget _buildCompanyField() => DropdownButtonFormField<CompanyModel>(
    initialValue: _selectedCompany,
    decoration: const InputDecoration(
      labelText: 'الشركة',
      border: OutlineInputBorder(),
    ),
    items: _activeCompanies!
        .map(
          (company) => DropdownMenuItem<CompanyModel>(
            value: company,
            child: Text(company.name, overflow: TextOverflow.ellipsis),
          ),
        )
        .toList(),
    onChanged: _isSaving
        ? null
        : (company) => setState(() => _selectedCompany = company),
    validator: (company) => company == null ? 'اختر شركة.' : null,
  );

  Widget _buildSplitField({
    required TextEditingController controller,
    required String label,
  }) => TextFormField(
    controller: controller,
    keyboardType: const TextInputType.numberWithOptions(decimal: true),
    decoration: InputDecoration(
      labelText: label,
      hintText: '0.00',
      border: const OutlineInputBorder(),
      suffixText: 'د.أ',
    ),
    validator: (value) =>
        PurchaseInvoiceFormValidator.validateSplitField(value, label: label),
  );

  Widget _buildSplitHint() {
    final total = PurchaseInvoiceFormValidator.tryParseJodField(
      _totalController.text,
    );
    final shopCash = PurchaseInvoiceFormValidator.tryParseJodField(
      _shopCashController.text,
    );
    final outsideCash = PurchaseInvoiceFormValidator.tryParseJodField(
      _outsideCashController.text,
    );
    final supplierDebt = PurchaseInvoiceFormValidator.tryParseJodField(
      _supplierDebtController.text,
    );
    if (total == null ||
        shopCash == null ||
        outsideCash == null ||
        supplierDebt == null) {
      return const SizedBox.shrink();
    }

    final error = PurchaseInvoiceFormValidator.validateSplit(
      totalFils: total,
      shopCashFils: shopCash,
      outsideCashFils: outsideCash,
      supplierDebtFils: supplierDebt,
    );
    final sum = shopCash + outsideCash + supplierDebt;
    final colorScheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('مجموع الأجزاء: ${PriceAmount.formatJod2(sum)}'),
        const SizedBox(height: 4),
        Text(
          error ?? 'التقسيم مطابق للإجمالي',
          style: TextStyle(
            color: error == null ? colorScheme.primary : colorScheme.error,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  Widget _buildSaveBar() => Padding(
    padding: const EdgeInsets.all(16),
    child: FilledButton(
      onPressed: _canSave ? _save : null,
      child: _isSaving
          ? const SizedBox.square(
              dimension: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Text('حفظ الفاتورة'),
    ),
  );
}
