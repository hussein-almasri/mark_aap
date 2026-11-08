import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart' show Timestamp;
import 'package:flutter/material.dart';

import '../../../core/utils/data_load_diagnostics.dart';
import '../../../core/utils/price_amount.dart';
import '../../../data/models/financial_operation_model.dart';
import '../../../data/models/user_model.dart';
import '../../../data/repositories/financial_operation_repository.dart';
import '../../../shared/widgets/raff_ui.dart';
import '../../../data/repositories/user_repository.dart';

class OperationsLogScreen extends StatefulWidget {
  const OperationsLogScreen({
    required this.user,
    this.repository,
    this.userRepository,
    super.key,
  });

  final UserModel user;
  final FinancialOperationRepository? repository;
  final UserRepository? userRepository;

  @override
  State<OperationsLogScreen> createState() => _OperationsLogScreenState();
}

class _OperationsLogScreenState extends State<OperationsLogScreen> {
  late final FinancialOperationRepository _repository =
      widget.repository ?? FinancialOperationRepository();
  late final UserRepository _userRepository =
      widget.userRepository ?? UserRepository();

  List<FinancialOperationLogEntry>? _entries;
  Map<String, String?> _userNames = {};
  FinancialOperationType? _selectedType;
  DateTimeRange? _dateRange;
  bool _isLoading = true;
  String? _loadError;

  @override
  void initState() {
    super.initState();
    _loadOperations();
  }

  Future<void> _loadOperations() async {
    if (!mounted) return;
    unawaited(
      DataLoadDiagnostics.inspectMemberships(
        user: widget.user,
        source: 'operationsLog',
      ),
    );
    setState(() {
      _isLoading = true;
      _loadError = null;
    });
    try {
      final entries = await _repository.listOperations(
        storeId: widget.user.storeId,
        isAdmin: widget.user.isAdmin,
        currentUserId: widget.user.uid,
      );
      final names = <String, String?>{};
      await Future.wait(
        entries.map((entry) => entry.operation.createdBy).toSet().map((
          uid,
        ) async {
          names[uid] = uid == widget.user.uid
              ? widget.user.name
              : await _userRepository.getDisplayName(uid: uid);
        }),
      );
      if (!mounted) return;
      setState(() {
        _entries = entries;
        _userNames = names;
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loadError = 'تعذر تحميل سجل العمليات.';
        _isLoading = false;
      });
    }
  }

  Future<void> _selectDateRange() async {
    final now = DateTime.now();
    final selected = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2000),
      lastDate: DateTime(now.year + 1, 12, 31),
      initialDateRange: _dateRange,
      helpText: 'اختر فترة العمليات',
      saveText: 'تطبيق',
    );
    if (selected == null || !mounted) return;
    setState(() => _dateRange = selected);
  }

  List<FinancialOperationLogEntry> get _filteredEntries {
    return filterOperationsLogEntries(
      entries: _entries ?? const <FinancialOperationLogEntry>[],
      type: _selectedType,
      startDate: _dateRange?.start,
      endDate: _dateRange?.end,
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('سجل العمليات'),
      actions: [
        IconButton(
          tooltip: 'تحديث',
          onPressed: _isLoading ? null : _loadOperations,
          icon: const Icon(Icons.refresh),
        ),
      ],
    ),
    body: _isLoading
        ? const Center(child: CircularProgressIndicator())
        : _loadError != null
        ? _buildLoadFailure()
        : RaffResponsiveContent(child: _buildLog()),
  );

  Widget _buildLoadFailure() => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(_loadError!),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: _loadOperations,
            child: const Text('إعادة المحاولة'),
          ),
        ],
      ),
    ),
  );

  Widget _buildLog() {
    final entries = _filteredEntries;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Wrap(
            spacing: 12,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SizedBox(
                width: 230,
                child: DropdownButtonFormField<FinancialOperationType?>(
                  initialValue: _selectedType,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'نوع العملية',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  items: [
                    const DropdownMenuItem<FinancialOperationType?>(
                      value: null,
                      child: Text('كل الأنواع'),
                    ),
                    ...FinancialOperationType.values.map(
                      (type) => DropdownMenuItem<FinancialOperationType?>(
                        value: type,
                        child: Text(
                          _typeLabel(type),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                  ],
                  onChanged: (type) => setState(() => _selectedType = type),
                ),
              ),
              OutlinedButton.icon(
                onPressed: _selectDateRange,
                icon: const Icon(Icons.date_range),
                label: Text(
                  _dateRange == null
                      ? 'كل التواريخ'
                      : '${_formatDate(_dateRange!.start)} – '
                            '${_formatDate(_dateRange!.end)}',
                ),
              ),
              if (_selectedType != null || _dateRange != null)
                TextButton(
                  onPressed: () => setState(() {
                    _selectedType = null;
                    _dateRange = null;
                  }),
                  child: const Text('مسح الفلاتر'),
                ),
            ],
          ),
        ),
        Expanded(
          child: entries.isEmpty
              ? Center(
                  child: Text(
                    _entries!.isEmpty
                        ? 'لا توجد عمليات مسجلة بعد.'
                        : 'لا توجد عمليات تطابق الفلاتر.',
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                  itemCount: entries.length,
                  itemBuilder: (context, index) =>
                      _buildOperationCard(entries[index]),
                ),
        ),
      ],
    );
  }

  Widget _buildOperationCard(FinancialOperationLogEntry entry) {
    final operation = entry.operation;
    final isCancellation = entry.isCancellation;
    final statusColor = switch (operation.status) {
      FinancialOperationStatus.completed => Theme.of(
        context,
      ).colorScheme.primary,
      FinancialOperationStatus.processing => Theme.of(
        context,
      ).colorScheme.tertiary,
      FinancialOperationStatus.failed => Theme.of(context).colorScheme.error,
    };
    final userName = _userNames[operation.createdBy] ?? 'غير معروف';
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
                    _typeLabel(operation.type),
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  _statusLabel(operation.status),
                  style: TextStyle(
                    color: statusColor,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text('التاريخ: ${_formatTimestamp(operation.createdAt)}'),
            Text('${isCancellation ? 'ألغى العملية' : 'المستخدم'}: $userName'),
            if (entry.amountFils != null)
              Text('المبلغ: ${PriceAmount.formatJod2(entry.amountFils!)}'),
            if (isCancellation) ...[
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.errorContainer,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'تفاصيل الإلغاء',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'سبب الإلغاء: '
                      '${entry.cancellationReason ?? 'غير متوفر'}',
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _typeLabel(FinancialOperationType type) => switch (type) {
    FinancialOperationType.createPurchaseInvoice => 'إنشاء فاتورة مشتريات',
    FinancialOperationType.createSupplierPayment => 'إنشاء دفعة مورد',
    FinancialOperationType.cancelPurchaseInvoice => 'إلغاء فاتورة مشتريات',
    FinancialOperationType.cancelSupplierPayment => 'إلغاء دفعة مورد',
    FinancialOperationType.createManualWithdrawal => 'إنشاء سحب نقدي يدوي',
    FinancialOperationType.cancelManualWithdrawal => 'إلغاء سحب نقدي يدوي',
    FinancialOperationType.setOpeningBalance => 'تحديد الرصيد الافتتاحي',
    FinancialOperationType.amendOpeningBalance => 'تعديل الرصيد الافتتاحي',
    FinancialOperationType.createCashDeposit => 'إيداع نقدي',
  };

  String _statusLabel(FinancialOperationStatus status) => switch (status) {
    FinancialOperationStatus.processing => 'قيد المعالجة',
    FinancialOperationStatus.completed => 'مكتملة',
    FinancialOperationStatus.failed => 'فشلت',
  };

  String _formatDate(DateTime date) =>
      '${date.day.toString().padLeft(2, '0')}/'
      '${date.month.toString().padLeft(2, '0')}/${date.year}';

  String _formatTimestamp(Timestamp timestamp) {
    final date = timestamp.toDate();
    return '${_formatDate(date)} - '
        '${date.hour.toString().padLeft(2, '0')}:'
        '${date.minute.toString().padLeft(2, '0')}';
  }
}

List<FinancialOperationLogEntry> filterOperationsLogEntries({
  required List<FinancialOperationLogEntry> entries,
  FinancialOperationType? type,
  DateTime? startDate,
  DateTime? endDate,
}) {
  final firstDay = startDate == null
      ? null
      : DateTime(startDate.year, startDate.month, startDate.day);
  final afterLastDay = endDate == null
      ? null
      : DateTime(endDate.year, endDate.month, endDate.day + 1);
  final filtered = entries
      .where(
        (entry) =>
            (type == null || entry.operation.type == type) &&
            (firstDay == null ||
                !entry.operation.createdAt.toDate().isBefore(firstDay)) &&
            (afterLastDay == null ||
                entry.operation.createdAt.toDate().isBefore(afterLastDay)),
      )
      .toList();
  filtered.sort(
    (a, b) => b.operation.createdAt.compareTo(a.operation.createdAt),
  );
  return filtered;
}
