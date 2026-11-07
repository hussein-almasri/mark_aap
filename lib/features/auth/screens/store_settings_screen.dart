import 'package:cloud_firestore/cloud_firestore.dart' show Timestamp;
import 'package:flutter/material.dart';

import '../../../data/models/store_model.dart';
import '../../../data/models/user_model.dart';
import '../../../data/repositories/store_repository.dart';
import 'store_join_code_screen.dart';

class StoreSettingsScreen extends StatefulWidget {
  const StoreSettingsScreen({required this.user, this.repository, super.key});

  final UserModel user;
  final StoreRepository? repository;

  @override
  State<StoreSettingsScreen> createState() => _StoreSettingsScreenState();
}

class _StoreSettingsScreenState extends State<StoreSettingsScreen> {
  late final StoreRepository _repository =
      widget.repository ?? StoreRepository();

  StoreModel? _store;
  bool _isLoading = true;
  bool _isSaving = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadStore();
  }

  Future<void> _loadStore() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      final store = await _repository.getStore(widget.user.storeId);
      if (!mounted) return;
      setState(() {
        _store = store;
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'تعذر تحميل بيانات المتجر.';
        _isLoading = false;
      });
    }
  }

  Future<void> _editStoreName() async {
    final store = _store;
    if (!widget.user.isAdmin || store == null || _isSaving) return;

    final name = await showDialog<String>(
      context: context,
      builder: (_) => _StoreNameDialog(initialName: store.name),
    );
    if (name == null || !mounted) return;

    setState(() {
      _isSaving = true;
      _errorMessage = null;
    });
    try {
      await _repository.updateStoreName(
        storeId: widget.user.storeId,
        name: name,
      );
      final updatedStore = await _repository.getStore(widget.user.storeId);
      if (!mounted) return;
      setState(() {
        _store = updatedStore;
        _isSaving = false;
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('تم حفظ اسم المتجر')));
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'تعذر حفظ اسم المتجر. تحقق من الصلاحية والاتصال.';
        _isSaving = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('إعدادات المتجر'),
      actions: [
        IconButton(
          tooltip: 'تحديث',
          onPressed: _isLoading || _isSaving ? null : _loadStore,
          icon: const Icon(Icons.refresh),
        ),
      ],
    ),
    body: _isLoading
        ? const Center(child: CircularProgressIndicator())
        : _errorMessage != null && _store == null
        ? _buildLoadFailure()
        : _buildSettings(),
  );

  Widget _buildLoadFailure() => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(_errorMessage!),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: _loadStore,
            child: const Text('إعادة المحاولة'),
          ),
        ],
      ),
    ),
  );

  Widget _buildSettings() {
    final store = _store!;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: Column(
            children: [
              ListTile(
                leading: const Icon(Icons.store_outlined),
                title: const Text('اسم المتجر'),
                subtitle: Text(store.name),
                trailing: widget.user.isAdmin
                    ? IconButton(
                        tooltip: 'تعديل اسم المتجر',
                        onPressed: _isSaving ? null : _editStoreName,
                        icon: const Icon(Icons.edit_outlined),
                      )
                    : null,
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.tag_outlined),
                title: const Text('معرّف المتجر'),
                subtitle: SelectableText(store.id),
              ),
              if (store.createdAt case final createdAt?) ...[
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.calendar_today_outlined),
                  title: const Text('تاريخ إنشاء المتجر'),
                  subtitle: Text(_formatDate(createdAt)),
                ),
              ],
            ],
          ),
        ),
        if (widget.user.isAdmin) ...[
          const SizedBox(height: 8),
          Card(
            child: ListTile(
              leading: const Icon(Icons.key_outlined),
              title: const Text('كود انضمام الموظفين'),
              subtitle: const Text('إدارة الكود من شاشة كود الانضمام الحالية'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push<void>(
                MaterialPageRoute(
                  builder: (_) => StoreJoinCodeScreen(user: widget.user),
                ),
              ),
            ),
          ),
        ],
        if (_isSaving) ...[
          const SizedBox(height: 16),
          const Center(child: CircularProgressIndicator()),
        ],
        if (_errorMessage != null) ...[
          const SizedBox(height: 12),
          Text(
            _errorMessage!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ],
      ],
    );
  }

  String _formatDate(Timestamp timestamp) {
    final date = timestamp.toDate();
    return '${date.day.toString().padLeft(2, '0')}/'
        '${date.month.toString().padLeft(2, '0')}/${date.year}';
  }
}

class _StoreNameDialog extends StatefulWidget {
  const _StoreNameDialog({required this.initialName});

  final String initialName;

  @override
  State<_StoreNameDialog> createState() => _StoreNameDialogState();
}

class _StoreNameDialogState extends State<_StoreNameDialog> {
  final _formKey = GlobalKey<FormState>();
  late final _controller = TextEditingController(text: widget.initialName);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _save() {
    if (_formKey.currentState!.validate()) {
      Navigator.of(context).pop(_controller.text.trim());
    }
  }

  String? _validateStoreName(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'اسم المتجر مطلوب';
    }
    if (value.trim().length > 120) {
      return 'اسم المتجر يجب ألا يتجاوز 120 حرفًا';
    }
    return null;
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('تعديل اسم المتجر'),
    content: Form(
      key: _formKey,
      child: TextFormField(
        controller: _controller,
        autofocus: true,
        maxLength: 120,
        textInputAction: TextInputAction.done,
        decoration: const InputDecoration(
          labelText: 'اسم المتجر',
          border: OutlineInputBorder(),
        ),
        validator: _validateStoreName,
        onFieldSubmitted: (_) => _save(),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('إلغاء'),
      ),
      FilledButton(onPressed: _save, child: const Text('حفظ')),
    ],
  );
}
