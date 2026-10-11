import 'package:flutter/material.dart';

import '../../../core/utils/price_amount.dart';
import '../../../data/models/supplier_debt_model.dart';
import '../../../data/models/supplier_payment_model.dart';
import '../../../data/models/user_model.dart';
import '../../../data/repositories/supplier_payment_repository.dart';
import '../supplier_payment_form_validator.dart';

/// Full-screen form for recording a supplier payment against open debts.
///
/// The debts come from [SupplierPaymentRepository.listOpenDebtsForCompany] for
/// the company reached from the debt list. The user enters the payment in JOD
/// (two decimals) and allocates it across one or more open debts, up to 5, with
/// integer فلس arithmetic. Saving is blocked unless the allocations sum exactly
/// to the payment amount. Saving reuses one cached `operationId` so a retry of
/// the same logical payment resumes idempotently instead of posting twice.
class SupplierPaymentFormScreen extends StatefulWidget {
  const SupplierPaymentFormScreen({
    required this.user,
    required this.companyId,
    required this.companyName,
    this.paymentRepository,
    super.key,
  });

  final UserModel user;
  final String companyId;
  final String companyName;
  final SupplierPaymentRepository? paymentRepository;

  @override
  State<SupplierPaymentFormScreen> createState() =>
      _SupplierPaymentFormScreenState();
}

class _SupplierPaymentFormScreenState extends State<SupplierPaymentFormScreen> {
  late final SupplierPaymentRepository _payments =
      widget.paymentRepository ?? SupplierPaymentRepository();

  final _formKey = GlobalKey<FormState>();
  final _amountController = TextEditingController();
  final _notesController = TextEditingController();
  final List<TextEditingController> _allocationControllers = [];

  List<SupplierDebtModel> _debts = [];
  bool _isLoadingDebts = true;
  String? _debtsError;
  bool _isSaving = false;
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
      if (!mounted) return;
      setState(() {
        _debts = debts;
        for (final controller in _allocationControllers) {
          controller.dispose();
        }
        _allocationControllers
          ..clear()
          ..addAll(
            debts.map((_) => TextEditingController()..addListener(_onChanged)),
          );
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

  int? get _amountFils =>
      SupplierPaymentFormValidator.tryParseJodField(_amountController.text);

  /// Per-debt allocated فلس; an unparsable field yields `null` so the payment
  /// is treated as invalid and saving stays disabled.
  List<int?> get _allocationFils => [
    for (final controller in _allocationControllers)
      SupplierPaymentFormValidator.tryParseJodField(controller.text),
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
    final remaining = _remainingFils;
    if (amount == null || allocations.any((value) => value == null)) {
      return 'تحقق من المبالغ المُدخلة.';
    }
    return SupplierPaymentFormValidator.validatePayment(
      amountFils: amount,
      allocationFils: allocations.cast<int>(),
      remainingFils: remaining,
    );
  }

  bool get _canSave =>
      !_isSaving && !_isLoadingDebts && _debtsError == null && _debts.isNotEmpty;

  Future<void> _save() async {
    if (!_canSave) return;
    if (!_formKey.currentState!.validate()) return;
    if (_paymentError != null) {
      _showMessage(_paymentError!);
      return;
    }

    final amount = _amountFils!;
    final allocations = _allocationFils.cast<int>();
    final allocationDebts = <SupplierDebtModel>[];
    for (var index = 0; index < allocations.length; index++) {
      if (allocations[index] > 0) allocationDebts.add(_debts[index]);
    }
    final allocationAmounts = [
      for (var index = 0; index < allocations.length; index++)
        if (allocations[index] > 0) allocations[index],
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
          'توزيع المبلغ على الفواتير',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        ..._debts.asMap().entries.map(_buildAllocationField),
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

  Widget _buildAllocationField(MapEntry<int, SupplierDebtModel> entry) {
    final index = entry.key;
    final debt = entry.value;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: TextFormField(
        controller: _allocationControllers[index],
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: InputDecoration(
          labelText: 'فاتورة ${debt.invoiceId}',
          hintText: '0.00',
          border: const OutlineInputBorder(),
          suffixText: 'د.أ',
          helperText: 'المتبقي: ${PriceAmount.formatJod2(debt.remainingAmountFils)}',
        ),
        validator: (value) => SupplierPaymentFormValidator
            .validateAllocationField(
              value,
              maxFils: debt.remainingAmountFils,
              label: 'فاتورة ${debt.invoiceId}',
            ),
      ),
    );
  }

  Widget _buildSummary() {
    final amount = _amountFils;
    final error = _paymentError;
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
}
