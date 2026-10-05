import 'package:flutter/material.dart';

import '../../../data/models/company_model.dart';
import '../../../data/models/user_model.dart';
import '../../../data/repositories/company_repository.dart';

class CompanyManagementScreen extends StatefulWidget {
  const CompanyManagementScreen({required this.user, this.repository, super.key});

  final UserModel user;
  final CompanyRepository? repository;

  @override
  State<CompanyManagementScreen> createState() =>
      _CompanyManagementScreenState();
}

class _CompanyManagementScreenState extends State<CompanyManagementScreen> {
  late final CompanyRepository _repository =
      widget.repository ?? CompanyRepository();
  List<CompanyModel>? _companies;
  final Set<String> _processingCompanyIds = {};
  bool _isLoading = true;
  bool _isSaving = false;
  String? _loadError;

  @override
  void initState() {
    super.initState();
    if (widget.user.isAdmin) _loadCompanies();
  }

  Future<void> _loadCompanies() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _loadError = null;
    });
    try {
      final companies = await _repository.listCompanies(widget.user.storeId);
      if (!mounted) return;
      setState(() {
        _companies = companies;
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loadError = 'تعذر تحميل قائمة الشركات.';
        _isLoading = false;
      });
    }
  }

  Future<void> _addCompany() async {
    final details = await _showCompanyForm();
    if (details == null || !mounted) return;
    setState(() => _isSaving = true);
    try {
      await _repository.createCompany(
        storeId: widget.user.storeId,
        name: details.name,
        phone: details.phone,
      );
      await _loadCompanies();
    } on CompanyAlreadyExistsException {
      _showMessage('اسم الشركة مستخدم بالفعل.');
    } catch (_) {
      _showMessage('تعذر إضافة الشركة. حاول مرة أخرى.');
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _editCompany(CompanyModel company) async {
    final details = await _showCompanyForm(company: company);
    if (details == null || !mounted) return;
    setState(() => _isSaving = true);
    try {
      await _repository.updateCompany(
        storeId: widget.user.storeId,
        companyId: company.companyId,
        name: details.name,
        phone: details.phone,
        isActive: company.isActive,
      );
      await _loadCompanies();
    } on CompanyAlreadyExistsException {
      _showMessage('اسم الشركة مستخدم بالفعل.');
    } catch (_) {
      _showMessage('تعذر حفظ بيانات الشركة. حاول مرة أخرى.');
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _changeCompanyStatus(CompanyModel company) async {
    if (_processingCompanyIds.contains(company.companyId)) return;
    final activate = !company.isActive;
    final action = activate ? 'إعادة تفعيل' : 'إيقاف';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('$action الشركة؟'),
        content: Text('هل تريد $action ${company.name}؟'),
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
        _processingCompanyIds.contains(company.companyId)) {
      return;
    }

    setState(() => _processingCompanyIds.add(company.companyId));
    try {
      await _repository.setCompanyActive(
        storeId: widget.user.storeId,
        companyId: company.companyId,
        isActive: activate,
      );
      await _loadCompanies();
    } catch (_) {
      _showMessage('تعذر تغيير حالة الشركة. حاول مرة أخرى.');
    } finally {
      if (mounted) {
        setState(() => _processingCompanyIds.remove(company.companyId));
      }
    }
  }

  Future<({String name, String? phone})?> _showCompanyForm({
    CompanyModel? company,
  }) => showDialog<({String name, String? phone})>(
    context: context,
    builder: (_) => _CompanyFormDialog(company: company),
  );

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.user.isAdmin) {
      return Scaffold(
        appBar: AppBar(title: const Text('إدارة الشركات')),
        body: const Center(child: Text('هذه الصفحة متاحة للأدمن فقط.')),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('إدارة الشركات')),
      floatingActionButton: _companies == null || _loadError != null
          ? null
          : FloatingActionButton.extended(
              onPressed: _isSaving ? null : _addCompany,
              icon: const Icon(Icons.add),
              label: const Text('إضافة شركة'),
            ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _loadError != null
          ? _buildLoadFailure()
          : _buildCompanyList(),
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
            onPressed: _loadCompanies,
            child: const Text('إعادة المحاولة'),
          ),
        ],
      ),
    ),
  );

  Widget _buildCompanyList() {
    final companies = _companies!;
    return companies.isEmpty
        ? const Center(child: Text('لا توجد شركات مسجلة بعد.'))
        : ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
            itemCount: companies.length,
            itemBuilder: (context, index) => _buildCompanyCard(companies[index]),
          );
  }

  Widget _buildCompanyCard(CompanyModel company) {
    final isProcessing = _processingCompanyIds.contains(company.companyId);
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          children: [
            ListTile(
              title: Text(company.name),
              subtitle: company.phone == null || company.phone!.isEmpty
                  ? null
                  : Text(company.phone!),
              trailing: Text(
                company.isActive ? 'نشطة' : 'غير نشطة',
                style: TextStyle(
                  color: company.isActive
                      ? Theme.of(context).colorScheme.primary
                      : Theme.of(context).colorScheme.error,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsetsDirectional.only(end: 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  OutlinedButton.icon(
                    onPressed: _isSaving ? null : () => _editCompany(company),
                    icon: const Icon(Icons.edit_outlined),
                    label: const Text('تعديل'),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                    onPressed: isProcessing
                        ? null
                        : () => _changeCompanyStatus(company),
                    icon: isProcessing
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Icon(
                            company.isActive
                                ? Icons.pause_circle_outline
                                : Icons.play_circle_outline,
                          ),
                    label: Text(company.isActive ? 'إيقاف' : 'إعادة تفعيل'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CompanyFormDialog extends StatefulWidget {
  const _CompanyFormDialog({this.company});

  final CompanyModel? company;

  @override
  State<_CompanyFormDialog> createState() => _CompanyFormDialogState();
}

class _CompanyFormDialogState extends State<_CompanyFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name = TextEditingController(
    text: widget.company?.name ?? '',
  );
  late final TextEditingController _phone = TextEditingController(
    text: widget.company?.phone ?? '',
  );
  bool _saving = false;

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    super.dispose();
  }

  void _submit() {
    if (_saving || !_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    Navigator.of(context).pop((
      name: _name.text.trim(),
      phone: _phone.text.trim().isEmpty ? null : _phone.text.trim(),
    ));
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.company == null ? 'إضافة شركة' : 'تعديل الشركة'),
    content: Form(
      key: _formKey,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextFormField(
            controller: _name,
            maxLength: 120,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: 'اسم الشركة',
              border: OutlineInputBorder(),
            ),
            validator: (value) {
              final name = value?.trim() ?? '';
              if (name.isEmpty) return 'اسم الشركة مطلوب.';
              if (name.length > 120) return 'الحد الأقصى 120 حرفاً.';
              return null;
            },
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _phone,
            keyboardType: TextInputType.phone,
            decoration: const InputDecoration(
              labelText: 'رقم الهاتف (اختياري)',
              border: OutlineInputBorder(),
            ),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: _saving ? null : () => Navigator.of(context).pop(),
        child: const Text('إلغاء'),
      ),
      FilledButton(
        onPressed: _saving ? null : _submit,
        child: _saving
            ? const SizedBox.square(
                dimension: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Text('حفظ'),
      ),
    ],
  );
}
