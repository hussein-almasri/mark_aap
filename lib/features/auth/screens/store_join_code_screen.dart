import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../../data/models/user_model.dart';
import '../../../data/services/store_join_code_service.dart';

class StoreJoinCodeScreen extends StatefulWidget {
  const StoreJoinCodeScreen({required this.user, super.key});

  final UserModel user;

  @override
  State<StoreJoinCodeScreen> createState() => _StoreJoinCodeScreenState();
}

class _StoreJoinCodeScreenState extends State<StoreJoinCodeScreen> {
  final StoreJoinCodeService _service = StoreJoinCodeService();
  String? _joinCode;
  String? _errorMessage;
  bool _isLoading = true;
  bool _isRotating = false;

  @override
  void initState() {
    super.initState();
    if (!widget.user.isAdmin) {
      _isLoading = false;
      return;
    }
    _loadOrCreateCode();
  }

  Future<void> _loadOrCreateCode() async {
    try {
      final code = await _service.ensureJoinCode(widget.user.storeId);
      if (!mounted) return;
      setState(() {
        _joinCode = code;
        _errorMessage = null;
        _isLoading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _errorMessage = _messageFor(error);
        _isLoading = false;
      });
    }
  }

  Future<void> _rotateCode() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('تغيير كود الانضمام؟'),
        content: const Text('سيصبح الكود الحالي غير صالح بعد التغيير.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('تغيير الكود'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() {
      _isRotating = true;
      _errorMessage = null;
    });
    try {
      final code = await _service.rotateJoinCode(widget.user.storeId);
      if (!mounted) return;
      setState(() => _joinCode = code);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم تغيير كود الانضمام بنجاح')),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _errorMessage = _messageFor(error));
    } finally {
      if (mounted) setState(() => _isRotating = false);
    }
  }

  String _messageFor(Object error) {
    if (error is FirebaseException) {
      if (error.code == 'permission-denied') {
        return 'ليس لديك صلاحية إدارة كود هذا المتجر.';
      }
      if (error.code == 'unavailable' ||
          error.code == 'network-request-failed') {
        return 'تعذر الاتصال. تحقق من الإنترنت ثم حاول مرة أخرى.';
      }
    }
    return 'تعذر تحميل أو تغيير كود الانضمام. حاول مرة أخرى.';
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.user.isAdmin) {
      return Scaffold(
        appBar: AppBar(title: const Text('كود انضمام الموظفين')),
        body: const Center(child: Text('هذه الصفحة متاحة للأدمن فقط.')),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('كود انضمام الموظفين')),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Icon(Icons.key_rounded, size: 56),
                const SizedBox(height: 16),
                const Text(
                  'كود انضمام الموظفين',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 20),
                if (_isLoading)
                  const Center(child: CircularProgressIndicator())
                else if (_joinCode != null)
                  SelectableText(
                    _joinCode!,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      letterSpacing: 2,
                    ),
                  ),
                if (_errorMessage != null) ...[
                  const SizedBox(height: 16),
                  Text(
                    _errorMessage!,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                  if (!_isLoading && _joinCode == null)
                    TextButton(
                      onPressed: _loadOrCreateCode,
                      child: const Text('إعادة المحاولة'),
                    ),
                ],
                const SizedBox(height: 24),
                OutlinedButton.icon(
                  onPressed: _isLoading || _isRotating || _joinCode == null
                      ? null
                      : _rotateCode,
                  icon: _isRotating
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.refresh_rounded),
                  label: const Text('تغيير الكود'),
                ),
                const SizedBox(height: 8),
                const Text(
                  'عند تغيير الكود، لن يعمل الكود السابق للانضمام.',
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
