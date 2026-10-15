import 'package:cloud_firestore/cloud_firestore.dart' show Timestamp;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/utils/price_amount.dart';
import '../../../data/models/supplier_debt_model.dart';
import '../../../data/models/supplier_payment_model.dart';
import '../../../data/models/user_model.dart';
import '../../../data/repositories/purchase_invoice_repository.dart';
import '../../../data/repositories/supplier_payment_repository.dart';
import '../supplier_payment_form_validator.dart';

/// Full-screen form for recording a supplier payment against open debts.
///
/// The debts come from [SupplierPaymentRepository.listOpenDebtsForCompany] for
/// the company reached from the debt list — already only invoices that are
/// `OPEN` with a positive balance. The user **selects** which invoices to settle
/// (checkbox per invoice, at most 5, so the same invoice can never be picked
/// twice) instead of typing an invoice number, then allocates the JOD amount
/// across the selected invoices with integer فلس arithmetic.
///
/// Each option is labelled by the supplier's own invoice number when the
/// purchase invoice carries one, otherwise by «فاتورة بدون رقم» (the supplier
/// number is optional at invoice creation), together with the creation date and
/// the remaining balance so invoices stay distinguishable. The number is a
/// display aid only — allocations always reference the real internal
/// [SupplierDebtModel.invoiceId]. Saving is blocked unless the allocations sum
/// exactly to the payment amount, and one cached `operationId` is reused across
/// retries so a failed save resumes idempotently instead of posting twice.
class SupplierPaymentFormScreen extends StatefulWidget {
  const SupplierPaymentFormScreen({
    required this.user,
    required this.companyId,
    required this.companyName,
    this.paymentRepository,
    this.invoiceRepository,
    super.key,
  });

  final UserModel user;
  final String companyId;
  final String companyName;
  final SupplierPaymentRepository? paymentRepository;

  /// Read-only source for each invoice's optional `supplierInvoiceNumber`,
  /// which the supplier debt documents do not carry.
  final PurchaseInvoiceRepository? invoiceRepository;

  @override
  State<SupplierPaymentFormScreen> createState() =>
      _SupplierPaymentFormScreenState();
}

class _SupplierPaymentFormScreenState extends State<SupplierPaymentFormScreen> {
  late final SupplierPaymentRepository _payments =
      widget.paymentRepository ?? SupplierPaymentRepository();
  late final PurchaseInvoiceRepository _invoices =
      widget.invoiceRepository ?? PurchaseInvoiceRepository();

  final _formKey = GlobalKey<FormState>();
  final _amountController = TextEditingController();
  final _notesController = TextEditingController();
  final List<TextEditingController> _allocationControllers = [];

  List<SupplierDebtModel> _debts = [];
  final List<bool> _selected = [];

  /// Invoice id → supplier invoice number, or `null` when the invoice has no
  /// number (or could not be read). Missing values render as
  /// «فاتورة بدون رقم».
  final Map<String, String?> _supplierNumbers = {};

  bool _isLoadingDebts = true;
  String? _debtsError;
  bool _isSaving = false;

  /// Whether the cross-field summary error may be shown. It stays hidden until
  /// the first save attempt so an untouched form does not open with a red error.
  bool _showErrors = false;
  SupplierPaymentSource _source = SupplierPaymentSource.shopCash;

  /// Minted once per logical payment and reused across retries, so a failed
  /// save that is retried resumes the same operation instead of creating a
  /// second one.
  String? _operationId;

  @override
  void initState() {
    super.initState();
    _amountController.addListener(_onChanged);
    _notesController.addListener(_onChanged);
    _loadDebts();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _amountController.dispose();
    _notesController.dispose();
    for (final controller in _allocationControllers) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _loadDebts() async {
    if (!mounted) return;
    setState(() {
      _isLoadingDebts = true;
      _debtsError = null;
    });
    try {
      final debts = await _payments.listOpenDebtsForCompany(
        widget.user.storeId,
        widget.companyId,
      );
      // Resolve supplier numbers before revealing the form so labels render
      // complete on first paint. Failures fall back per invoice, never throw.
      final numbers = await _resolveSupplierNumbers(debts);
      if (!mounted) return;
      setState(() {
        for (final controller in _allocationControllers) {
          controller.dispose();
        }
        _allocationControllers
          ..clear()
          ..addAll(
            debts.map((_) => TextEditingController()..addListener(_onChanged)),
          );
        _debts = debts;
        _selected
          ..clear()
          ..addAll(List.filled(debts.length, false));
        _supplierNumbers
          ..clear()
          ..addEntries(numbers.entries);
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

  /// Best-effort lookup of each debt invoice's optional supplier number.
  ///
  /// A single-document `get` per invoice (allowed by `isFinancialStoreMember`
  /// read rules); a missing or unreadable invoice yields `null` so its row falls
  /// back to «فاتورة بدون رقم» instead of failing the whole form.
  Future<Map<String, String?>> _resolveSupplierNumbers(
    List<SupplierDebtModel> debts,
  ) async {
    final result = <String, String?>{};
    await Future.wait(
      debts.map((debt) async {
        String? number;
        try {
          final invoice = await _invoices.getInvoice(
            widget.user.storeId,
            debt.invoiceId,
          );
          number = invoice.supplierInvoiceNumber;
        } catch (_) {
          number = null;
        }
        result[debt.invoiceId] =
            (number == null || number.trim().isEmpty) ? null : number.trim();
      }),
    );
    return result;
  }

  String _invoiceLabel(SupplierDebtModel debt) {
    final number = _supplierNumbers[debt.invoiceId];
    if (number == null || number.isEmpty) return 'فاتورة بدون رقم';
    return number;
  }

  void _toggleSelection(int index, bool selected) {
    if (_isSaving) return;
    if (selected) {
      final alreadySelected = _selected.where((value) => value).length;
      if (alreadySelected >= 5) {
        _showMessage('الحد الأقصى 5 فواتير في الدفعة الواحدة.');
        return;
      }
    }
    setState(() {
      _selected[index] = selected;
      // Deselecting clears the amount so a later re-selection starts clean.
      if (!selected) _allocationControllers[index].clear();
    });
  }

  int? get _amountFils =>
      SupplierPaymentFormValidator.tryParseJodField(_amountController.text);

  /// Allocated فلس per debt: unselected debts always count as `0`, while a
  /// selected debt yields `null` when its text is unparsable so the payment is
  /// treated as invalid and saving stays disabled.
  List<int?> get _allocationFils => [
    for (var index = 0; index < _debts.length; index++)
      _selected[index]
          ? SupplierPaymentFormValidator.tryParseJodField(
              _allocationControllers[index].text,
            )
          : 0,
  ];

  /// Per-debt remaining balance, used as the allocation upper bound.
  List<int> get _remainingFils => [
    for (final debt in _debts) debt.remainingAmountFils,
  ];

  int get _allocatedTotal => _allocationFils.fold<int>(
    0,
    (sum, value) => sum + (value ?? 0),
  );

  /// The cross-field error for the current input; `null` when valid.
  String? get _paymentError {
    final amount = _amountFils;
    final allocations = _allocationFils;
    if (amount == null || allocations.any((value) => value == null)) {
      return 'تحقق من المبالغ المُدخلة.';
    }
    final selectedCount = _selected.where((value) => value).length;
    if (selectedCount == 0) return 'اختر فاتورة واحدة على الأقل.';
    if (selectedCount > 5) return 'الحد الأقصى 5 فواتير.';
    for (var index = 0; index < _debts.length; index++) {
      if (_selected[index] && allocations[index]! <= 0) {
        return 'أدخل مبلغ التخصيص للفاتورة المختارة.';
      }
    }
    return SupplierPaymentFormValidator.validatePayment(
      amountFils: amount,
      allocationFils: allocations.cast<int>(),
      remainingFils: _remainingFils,
    );
  }

  bool get _canSave =>
      !_isSaving && !_isLoadingDebts && _debtsError == null && _debts.isNotEmpty;

  Future<void> _save() async {
    if (!_canSave) return;
    if (!_formKey.currentState!.validate()) return;
    if (_paymentError != null) {
      setState(() => _showErrors = true);
      return;
    }

    final amount = _amountFils!;
    final selectedIndices = [
      for (var index = 0; index < _debts.length; index++)
        if (_selected[index]) index,
    ];
    // Allocations always reference the real internal invoice id, whether or not
    // the supplier printed a number on it.
    final allocationDebts = [for (final index in selectedIndices) _debts[index]];
    final allocationAmounts = [
      for (final index in selectedIndices)
        SupplierPaymentFormValidator.tryParseJodField(
          _allocationControllers[index].text,
        )!,
    ];

    setState(() => _isSaving = true);
    // Reuse the cached operationId so retrying this same logical payment
    // resumes idempotently instead of minting a second operation.
    _operationId ??= _payments.newOperationId(widget.user.storeId);
    var succeeded = false;
    try {
      await _payments.createPayment(
        storeId: widget.user.storeId,
        companyId: widget.companyId,
        companyName: widget.companyName,
        amountFils: amount,
        source: _source,
        allocationCount: allocationDebts.length,
        allocation1InvoiceId: allocationDebts[0].invoiceId,
        allocation1AmountFils: allocationAmounts[0],
        allocation2InvoiceId: allocationDebts.length > 1
            ? allocationDebts[1].invoiceId
            : null,
        allocation2AmountFils: allocationAmounts.length > 1
            ? allocationAmounts[1]
            : null,
        allocation3InvoiceId: allocationDebts.length > 2
            ? allocationDebts[2].invoiceId
            : null,
        allocation3AmountFils: allocationAmounts.length > 2
            ? allocationAmounts[2]
            : null,
        allocation4InvoiceId: allocationDebts.length > 3
            ? allocationDebts[3].invoiceId
            : null,
        allocation4AmountFils: allocationAmounts.length > 3
            ? allocationAmounts[3]
            : null,
        allocation5InvoiceId: allocationDebts.length > 4
            ? allocationDebts[4].invoiceId
            : null,
        allocation5AmountFils: allocationAmounts.length > 4
            ? allocationAmounts[4]
            : null,
        notes: _cleanOptional(_notesController.text),
        createdBy: widget.user.uid,
        operationId: _operationId!,
      );
      succeeded = true;
      if (!mounted) return;
      _showMessage('تم تسجيل الدفعة بنجاح');
      Navigator.of(context).pop(true);
    } on PaymentAllocationMismatchException {
      _showMessage('تم تسجيل هذه الدفعة مسبقاً؛ لم تُنشأ دفعة جديدة.');
    } catch (_) {
      _showMessage('تعذر حفظ الدفعة. تحقق من الاتصال وحاول مرة أخرى.');
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
      appBar: AppBar(title: Text('دفعة إلى ${widget.companyName}')),
      body: SafeArea(
        child: _isLoadingDebts
            ? const Center(child: CircularProgressIndicator())
            : _debtsError != null
            ? _buildDebtsFailure()
            : _debts.isEmpty
            ? const Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Text('لا توجد ديون متبقية لهذا المورد.'),
                ),
              )
            : _buildForm(),
      ),
      bottomNavigationBar: _buildSaveBar(),
    );
  }

  Widget _buildDebtsFailure() => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(_debtsError!),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: _loadDebts,
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
        TextFormField(
          controller: _amountController,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(
            labelText: 'مبلغ الدفعة (د.أ)',
            hintText: 'مثال: 125.50',
            border: OutlineInputBorder(),
            suffixText: 'د.أ',
          ),
          validator: SupplierPaymentFormValidator.validateAmountField,
        ),
        const SizedBox(height: 16),
        _buildSourceField(),
        const SizedBox(height: 16),
        const Text(
          'اختيار الفواتير وتوزيع المبلغ',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 4),
        const Text(
          'اختر من ديون المورد المفتوحة (بحد أقصى 5 فواتير).',
          style: TextStyle(fontSize: 12, color: Colors.grey),
        ),
        const SizedBox(height: 8),
        for (var index = 0; index < _debts.length; index++)
          _buildDebtRow(index),
        const SizedBox(height: 12),
        _buildSummary(),
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

  Widget _buildSourceField() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Text(
        'مصدر الدفع',
        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
      ),
      const SizedBox(height: 8),
      SegmentedButton<SupplierPaymentSource>(
        segments: const [
          ButtonSegment(
            value: SupplierPaymentSource.shopCash,
            label: Text('كاش الصندوق'),
          ),
          ButtonSegment(
            value: SupplierPaymentSource.outsideCash,
            label: Text('كاش خارج الصندوق'),
          ),
        ],
        selected: {_source},
        onSelectionChanged: _isSaving
            ? null
            : (selection) => setState(() => _source = selection.first),
      ),
    ],
  );

  /// One selectable invoice: label (supplier number or «فاتورة بدون رقم»),
  /// creation date and remaining balance, plus the amount field once selected.
  Widget _buildDebtRow(int index) {
    final debt = _debts[index];
    final label = _invoiceLabel(debt);
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          CheckboxListTile(
            value: _selected[index],
            controlAffinity: ListTileControlAffinity.leading,
            dense: true,
            onChanged: _isSaving
                ? null
                : (value) => _toggleSelection(index, value ?? false),
            title: Text(label),
            subtitle: Text(
              '${_formatDate(debt.createdAt)}'
              ' • المتبقي: ${PriceAmount.formatJod2(debt.remainingAmountFils)}',
            ),
          ),
          if (_selected[index])
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: TextFormField(
                controller: _allocationControllers[index],
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  labelText: 'مبلغ التخصيص (د.أ)',
                  hintText: '0.00',
                  border: OutlineInputBorder(),
                  suffixText: 'د.أ',
                ),
                validator: (value) {
                  if (!_selected[index]) return null;
                  if ((value?.trim() ?? '').isEmpty) {
                    return 'أدخل مبلغ التخصيص.';
                  }
                  return SupplierPaymentFormValidator.validateAllocationField(
                    value,
                    maxFils: debt.remainingAmountFils,
                    label: label,
                  );
                },
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSummary() {
    final amount = _amountFils;
    final error = _showErrors ? _paymentError : null;
    final colorScheme = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _summaryRow('مبلغ الدفعة', _formatFils(amount)),
            _summaryRow('مجموع المخصص', _formatFils(_allocatedTotal)),
            _summaryRow(
              'المتبقي',
              _formatFils(amount == null ? null : amount - _allocatedTotal),
              bold: true,
            ),
            if (error != null) ...[
              const SizedBox(height: 8),
              Text(
                error,
                style: TextStyle(
                  color: colorScheme.error,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _formatFils(int? fils) =>
      fils == null ? '—' : PriceAmount.formatJod2(fils);

  Widget _summaryRow(String label, String value, {bool bold = false}) =>
      Padding(
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
              value,
              style: TextStyle(
                fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ],
        ),
      );

  Widget _buildSaveBar() => Padding(
    padding: const EdgeInsets.all(16),
    child: FilledButton(
      onPressed: _canSave ? _save : null,
      child: _isSaving
          ? const SizedBox.square(
              dimension: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Text('حفظ الدفعة'),
    ),
  );

  String _formatDate(Timestamp timestamp) =>
      DateFormat('dd/MM/yyyy - HH:mm').format(timestamp.toDate());
}
