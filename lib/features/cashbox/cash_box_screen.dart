import 'package:flutter/material.dart';

import '../../../core/utils/price_amount.dart';
import '../../../data/models/cash_box_models.dart';
import '../../../data/models/user_model.dart';
import '../../../data/repositories/cash_box_repository.dart';

/// Shop cash box: current balance, opening balance, deposit totals, effective
/// withdrawals and the merged movement ledger. Admins may also record a
/// deposit and set/amend the opening balance.
class CashBoxScreen extends StatefulWidget {
  const CashBoxScreen({required this.user, this.repository, super.key});

  final UserModel user;
  final CashBoxRepository? repository;

  @override
  State<CashBoxScreen> createState() => _CashBoxScreenState();
}

class _CashBoxScreenState extends State<CashBoxScreen> {
  late final CashBoxRepository _repository =
      widget.repository ?? CashBoxRepository();

  CashBoxSnapshot? _snapshot;
  Object? _error;
  bool _loading = false;

  bool get _isAdmin => widget.user.isAdmin;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final snapshot = await _repository.loadCashBox(widget.user.storeId);
      if (!mounted) return;
      setState(() => _snapshot = snapshot);
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _recordDeposit() async {
    final saved = await _showDepositDialog(context);
    if (saved == null || !mounted) return;
    try {
      await _repository.createDeposit(
        storeId: widget.user.storeId,
        amountFils: saved.amountFils,
        note: saved.reason!,
        operationId: saved.operationId,
        createdBy: widget.user.uid,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم تسجيل الإيداع النقدي.')),
      );
      await _load();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_errorMessage(error))),
      );
    }
  }

  Future<void> _editOpeningBalance() async {
    final existing = _snapshot?.openingBalance;
    final saved = await _showOpeningBalanceDialog(
      context,
      existing: existing,
    );
    if (saved == null || !mounted) return;
    try {
      if (existing == null) {
        await _repository.setOpeningBalance(
          storeId: widget.user.storeId,
          openingBalanceFils: saved.amountFils,
          operationId: saved.operationId,
          createdBy: widget.user.uid,
        );
      } else {
        await _repository.amendOpeningBalance(
          storeId: widget.user.storeId,
          openingBalanceFils: saved.amountFils,
          operationId: saved.operationId,
          amendedBy: widget.user.uid,
          reason: saved.reason!,
        );
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم حفظ الرصيد الافتتاحي.')),
      );
      await _load();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_errorMessage(error))),
      );
    }
  }

  String _errorMessage(Object error) {
    if (error is CashBoxOpeningBalanceAlreadySetException) {
      return 'الرصيد الافتتاحي مسجل بالفعل؛ لا يمكن تعيينه مرة أخرى.';
    }
    if (error is CashBoxOpeningBalanceNotSetException) {
      return 'الرصيد الافتتاحي غير مسجل بعد.';
    }
    if (error is CashBoxMismatchException) {
      return 'تعذر إتمام العملية؛ حاول مرة أخرى بمعرّف جديد.';
    }
    if (error is CashBoxDataException) return error.message;
    if (error is ArgumentError) return error.message ?? 'قيمة غير صحيحة.';
    if (error is FormatException) return 'قيمة غير صحيحة.';
    return 'تعذر تنفيذ العملية: $error';
  }

  @override
  Widget build(BuildContext context) {
    final snapshot = _snapshot;
    final summary = snapshot?.summary;
    final openingBalance = snapshot?.openingBalance;

    return Scaffold(
      appBar: AppBar(title: const Text('رَفّ | صندوق النقد')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (_error != null) ...[
              _ErrorBanner(
                message: _errorMessage(_error!),
                onRetry: _load,
              ),
              const SizedBox(height: 12),
            ],
            if (summary != null) ...[
              _BalanceCard(summary: summary),
              const SizedBox(height: 12),
            ],
            if (openingBalance == null && _error == null) ...[
              _MissingOpeningBanner(
                isAdmin: _isAdmin,
                onSet: _isAdmin ? _editOpeningBalance : null,
              ),
              const SizedBox(height: 12),
            ],
            if (openingBalance != null) ...[
              _OpeningCard(
                openingBalance: openingBalance,
                isAdmin: _isAdmin,
                onAmend: _isAdmin ? _editOpeningBalance : null,
              ),
              const SizedBox(height: 12),
            ],
            if (_isAdmin) ...[
              FilledButton.icon(
                onPressed: _loading ? null : _recordDeposit,
                icon: const Icon(Icons.add_circle_outline),
                label: const Text('تسجيل إيداع نقدي'),
              ),
              const SizedBox(height: 16),
            ],
            Text(
              'سجل حركات الصندوق',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            if (_loading && snapshot == null)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (summary != null && summary.movements.isEmpty)
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('لا توجد حركات مسجلة بعد.'),
                ),
              )
            else if (summary != null)
              ...summary.movements.map(
                (movement) => _MovementTile(movement: movement),
              ),
          ],
        ),
      ),
    );
  }

  Future<_OpeningBalanceInput?> _showDepositDialog(BuildContext context) {
    final amountController = TextEditingController();
    final noteController = TextEditingController();
    final formKey = GlobalKey<FormState>();

    return showDialog<_OpeningBalanceInput>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('إيداع نقدي في الصندوق'),
        content: Form(
          key: formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: amountController,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    labelText: 'المبلغ (د.أ)',
                    hintText: 'مثال: 10.00',
                    border: OutlineInputBorder(),
                    suffixText: 'د.أ',
                  ),
                  validator: _amountValidator,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: noteController,
                  decoration: const InputDecoration(
                    labelText: 'سبب الإيداع / ملاحظة',
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) {
                    final text = value?.trim() ?? '';
                    if (text.isEmpty) return 'الملاحظة مطلوبة.';
                    if (text.length > 500) {
                      return 'الملاحظة لا تتجاوز 500 حرف.';
                    }
                    return null;
                  },
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () {
              if (!formKey.currentState!.validate()) return;
              final fils = PriceAmount.parseJodToFils(
                amountController.text.trim(),
              );
              Navigator.of(dialogContext).pop(
                _OpeningBalanceInput(
                  amountFils: fils,
                  reason: noteController.text.trim(),
                  operationId:
                      'deposit_${DateTime.now().millisecondsSinceEpoch}',
                ),
              );
            },
            child: const Text('حفظ'),
          ),
        ],
      ),
    );
  }

  Future<_OpeningBalanceInput?> _showOpeningBalanceDialog(
    BuildContext context, {
    required OpeningBalanceModel? existing,
  }) {
    final amountController = TextEditingController();
    final reasonController = TextEditingController();
    final formKey = GlobalKey<FormState>();
    final isAmendment = existing != null;
    if (isAmendment) {
      amountController.text = PriceAmount.formatJod2(
        existing.openingBalanceFils,
        includeCurrency: false,
      );
    }

    return showDialog<_OpeningBalanceInput>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(isAmendment ? 'تعديل الرصيد الافتتاحي' : 'تعيين الرصيد الافتتاحي'),
        content: Form(
          key: formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (isAmendment) ...[
                  Text(
                    'الرصيد الافتتاحي الحالي: '
                    '${PriceAmount.formatJod2(existing.openingBalanceFils)}',
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'التعديل مسجَّل في سجل تدقيقي ولا يمكن التراجع عنه.',
                    style: TextStyle(color: Colors.red),
                  ),
                  const SizedBox(height: 12),
                ],
                TextFormField(
                  controller: amountController,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    labelText: 'الرصيد الافتتاحي (د.أ)',
                    hintText: 'مثال: 50.00',
                    border: OutlineInputBorder(),
                    suffixText: 'د.أ',
                  ),
                  validator: _amountValidator,
                ),
                if (isAmendment) ...[
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: reasonController,
                    decoration: const InputDecoration(
                      labelText: 'سبب التعديل',
                      border: OutlineInputBorder(),
                    ),
                    validator: (value) {
                      final text = value?.trim() ?? '';
                      if (text.isEmpty) return 'سبب التعديل مطلوب.';
                      if (text.length > 500) {
                        return 'السبب لا يتجاوز 500 حرف.';
                      }
                      return null;
                    },
                  ),
                ],
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () {
              if (!formKey.currentState!.validate()) return;
              final fils = PriceAmount.parseJodToFils(
                amountController.text.trim(),
              );
              Navigator.of(dialogContext).pop(
                _OpeningBalanceInput(
                  amountFils: fils,
                  reason: isAmendment ? reasonController.text.trim() : null,
                  operationId:
                      '${isAmendment ? "amend" : "set"}_opening_'
                      '${DateTime.now().millisecondsSinceEpoch}',
                ),
              );
            },
            child: const Text('حفظ'),
          ),
        ],
      ),
    );
  }

  static String? _amountValidator(String? value) {
    final text = value?.trim() ?? '';
    if (text.isEmpty) return 'المبلغ مطلوب.';
    if (!RegExp(r'^\d+(\.\d{1,3})?$').hasMatch(text)) {
      return 'مبلغ غير صحيح؛ يقبل ثلاثة أعداد عشرية كحد أقصى.';
    }
    int fils;
    try {
      fils = PriceAmount.parseJodToFils(text);
    } on FormatException {
      return 'مبلغ غير صحيح.';
    }
    if (fils <= 0) return 'يجب أن يكون أكبر من صفر.';
    return null;
  }
}

class _OpeningBalanceInput {
  const _OpeningBalanceInput({
    required this.amountFils,
    required this.reason,
    required this.operationId,
  });

  final int amountFils;
  final String? reason;
  final String operationId;
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Card(
    color: Theme.of(context).colorScheme.errorContainer,
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'تعذر حساب رصيد الصندوق',
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: 4),
          Text(message),
          const SizedBox(height: 8),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton(onPressed: onRetry, child: const Text('إعادة المحاولة')),
          ),
        ],
      ),
    ),
  );
}

class _MissingOpeningBanner extends StatelessWidget {
  const _MissingOpeningBanner({required this.isAdmin, this.onSet});

  final bool isAdmin;
  final VoidCallback? onSet;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'الرصيد الافتتاحي للصندوق غير محدد بعد.',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          Text(
            isAdmin
                ? 'حدّد الرصيد الافتتاحي لبدء حساب رصيد الصندوق.'
                : 'على المدير تحديد الرصيد الافتتاحي.',
          ),
          if (isAdmin) ...[
            const SizedBox(height: 8),
            FilledButton(onPressed: onSet, child: const Text('تعيين الرصيد الافتتاحي')),
          ],
        ],
      ),
    ),
  );
}

class _BalanceCard extends StatelessWidget {
  const _BalanceCard({required this.summary});

  final CashBoxSummary summary;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('الرصيد الحالي', style: theme.textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              PriceAmount.formatJod2(summary.currentBalanceFils),
              style: theme.textTheme.headlineMedium?.copyWith(
                color: summary.currentBalanceFils < 0
                    ? theme.colorScheme.error
                    : null,
                fontWeight: FontWeight.bold,
              ),
            ),
            const Divider(height: 24),
            _SummaryRow(
              label: 'مجموع الإيداعات',
              value: PriceAmount.formatJod2(summary.totalDepositsFils),
              color: Colors.green,
            ),
            _SummaryRow(
              label: 'مجموع السحوبات الفعّالة',
              value: PriceAmount.formatJod2(summary.totalWithdrawalsFils),
              color: theme.colorScheme.error,
            ),
          ],
        ),
      ),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 2),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label),
        Text(value, style: TextStyle(color: color, fontWeight: FontWeight.w600)),
      ],
    ),
  );
}

class _OpeningCard extends StatelessWidget {
  const _OpeningCard({
    required this.openingBalance,
    required this.isAdmin,
    this.onAmend,
  });

  final OpeningBalanceModel openingBalance;
  final bool isAdmin;
  final VoidCallback? onAmend;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'الرصيد الافتتاحي',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              Text(PriceAmount.formatJod2(openingBalance.openingBalanceFils)),
            ],
          ),
          if (openingBalance.wasAmended) ...[
            const SizedBox(height: 4),
            Text(
              'عُدّل سابقاً: ${openingBalance.amendedReason ?? ''}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
          if (isAdmin && onAmend != null) ...[
            const SizedBox(height: 4),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: TextButton(onPressed: onAmend, child: const Text('تعديل مُدقَّق')),
            ),
          ],
        ],
      ),
    ),
  );
}

class _MovementTile extends StatelessWidget {
  const _MovementTile({required this.movement});

  final CashBoxMovement movement;

  @override
  Widget build(BuildContext context) {
    final isMoneyIn = movement.isMoneyIn;
    final sign = isMoneyIn ? '+' : '-';
    final color = isMoneyIn ? Colors.green : Theme.of(context).colorScheme.error;
    final date = movement.createdAt.toDate();

    return Card(
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: color.withValues(alpha: 0.12),
          child: Icon(
            isMoneyIn ? Icons.arrow_downward : Icons.arrow_upward,
            color: color,
          ),
        ),
        title: Text(movement.typeLabel),
        subtitle: Text(
          [
            movement.note ?? '',
            movement.createdBy,
            '${date.year}/${date.month.toString().padLeft(2, '0')}/'
                '${date.day.toString().padLeft(2, '0')}',
          ].where((part) => part.isNotEmpty).join(' • '),
        ),
        trailing: Text(
          '$sign${PriceAmount.formatJod2(movement.amountFils, includeCurrency: false)} د.أ',
          style: TextStyle(color: color, fontWeight: FontWeight.bold),
        ),
      ),
    );
  }
}
