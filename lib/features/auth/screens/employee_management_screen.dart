import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../../data/models/employee_summary.dart';
import '../../../data/models/user_model.dart';
import '../../../data/repositories/employee_repository.dart';

class EmployeeManagementScreen extends StatefulWidget {
  const EmployeeManagementScreen({
    required this.user,
    this.repository,
    super.key,
  });

  final UserModel user;
  final EmployeeRepository? repository;

  @override
  State<EmployeeManagementScreen> createState() =>
      _EmployeeManagementScreenState();
}

class _EmployeeManagementScreenState extends State<EmployeeManagementScreen> {
  late final EmployeeRepository _repository =
      widget.repository ?? EmployeeRepository();
  List<EmployeeSummary>? _employees;
  final Set<String> _processingEmployeeUids = {};
  final Map<String, String> _operationErrors = {};
  String? _loadError;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    if (widget.user.isAdmin) {
      _loadEmployees();
    } else {
      _isLoading = false;
    }
  }

  Future<void> _loadEmployees({bool showLoading = true}) async {
    if (showLoading && mounted) {
      setState(() {
        _isLoading = true;
        _loadError = null;
      });
    }

    try {
      final employees = await _repository.listEmployees(widget.user.storeId);
      if (!mounted) return;
      setState(() {
        _employees = employees;
        _loadError = null;
        _isLoading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loadError = _loadErrorMessage(error);
        _isLoading = false;
      });
    }
  }

  Future<void> _changeEmployeeStatus(EmployeeSummary employee) async {
    if (_processingEmployeeUids.contains(employee.uid)) return;
    final activate = !employee.isActive;
    final action = activate ? 'إعادة تفعيل' : 'إيقاف';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('$action الموظف؟'),
        content: Text('هل تريد $action ${employee.name}؟'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(action),
          ),
        ],
      ),
    );
    if (confirmed != true ||
        !mounted ||
        _processingEmployeeUids.contains(employee.uid)) {
      return;
    }

    setState(() {
      _processingEmployeeUids.add(employee.uid);
      _operationErrors.remove(employee.uid);
    });
    try {
      await _repository.setEmployeeActive(
        widget.user.storeId,
        employee.uid,
        activate,
      );
      if (!mounted) return;
      setState(() {
        _employees = _employees
            ?.map(
              (item) => item.uid == employee.uid
                  ? EmployeeSummary(
                      uid: item.uid,
                      name: item.name,
                      email: item.email,
                      isActive: activate,
                    )
                  : item,
            )
            .toList();
      });
      await _loadEmployees(showLoading: false);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _operationErrors[employee.uid] = _operationErrorMessage(error);
      });
    } finally {
      if (mounted) {
        setState(() => _processingEmployeeUids.remove(employee.uid));
      }
    }
  }

  String _loadErrorMessage(Object error) {
    if (error is FirebaseException &&
        (error.code == 'unavailable' ||
            error.code == 'network-request-failed')) {
      return 'تعذر الاتصال. تحقق من الإنترنت ثم حاول مرة أخرى.';
    }
    return 'تعذر تحميل قائمة الموظفين.';
  }

  String _operationErrorMessage(Object error) {
    if (error is FirebaseException && error.code == 'permission-denied') {
      return 'ليس لديك صلاحية تغيير حالة هذا الموظف.';
    }
    if (error is FirebaseException &&
        (error.code == 'unavailable' ||
            error.code == 'network-request-failed')) {
      return 'تعذر الاتصال. لم يتم تغيير حالة الموظف.';
    }
    return 'تعذر تغيير حالة الموظف. حاول مرة أخرى.';
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.user.isAdmin) {
      return Scaffold(
        appBar: AppBar(title: const Text('إدارة الموظفين')),
        body: const Center(child: Text('هذه الصفحة متاحة للأدمن فقط.')),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('إدارة الموظفين')),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _employees == null
          ? _buildLoadFailure()
          : _buildEmployeeList(),
    );
  }

  Widget _buildLoadFailure() => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(_loadError ?? 'تعذر تحميل قائمة الموظفين.'),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: _loadEmployees,
            child: const Text('إعادة المحاولة'),
          ),
        ],
      ),
    ),
  );

  Widget _buildEmployeeList() {
    final employees = _employees!;
    return Column(
      children: [
        if (_loadError != null)
          MaterialBanner(
            content: Text(_loadError!),
            actions: [
              TextButton(
                onPressed: () => _loadEmployees(showLoading: false),
                child: const Text('إعادة المحاولة'),
              ),
            ],
          ),
        Expanded(
          child: employees.isEmpty
              ? const Center(child: Text('لا يوجد موظفون مسجلون بعد.'))
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: employees.length,
                  itemBuilder: (context, index) =>
                      _buildEmployeeCard(employees[index]),
                ),
        ),
      ],
    );
  }

  Widget _buildEmployeeCard(EmployeeSummary employee) {
    final isProcessing = _processingEmployeeUids.contains(employee.uid);
    final isActive = employee.isActive;
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          children: [
            ListTile(
              title: Text(employee.name),
              subtitle: Text(employee.email),
              trailing: Text(
                isActive ? 'نشط' : 'غير نشط',
                style: TextStyle(
                  color: isActive
                      ? Theme.of(context).colorScheme.primary
                      : Theme.of(context).colorScheme.error,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: Padding(
                padding: const EdgeInsetsDirectional.only(end: 16),
                child: OutlinedButton.icon(
                  onPressed: isProcessing
                      ? null
                      : () => _changeEmployeeStatus(employee),
                  icon: isProcessing
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Icon(
                          isActive
                              ? Icons.pause_circle_outline
                              : Icons.play_circle_outline,
                        ),
                  label: Text(isActive ? 'إيقاف' : 'إعادة تفعيل'),
                ),
              ),
            ),
            if (_operationErrors[employee.uid] case final error?)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: Text(
                    error,
                    style: TextStyle(color: Theme.of(context).colorScheme.error),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
