import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../../core/utils/employee_registration_form_validator.dart';
import '../../../data/services/employee_join_code_validator.dart';

class EmployeeRegistrationScreen extends StatefulWidget {
  const EmployeeRegistrationScreen({this.joinCodeValidator, super.key});

  final EmployeeJoinCodeValidator? joinCodeValidator;

  @override
  State<EmployeeRegistrationScreen> createState() =>
      _EmployeeRegistrationScreenState();
}

class _EmployeeRegistrationScreenState
    extends State<EmployeeRegistrationScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _joinCodeController = TextEditingController();
  final _formValidator = const EmployeeRegistrationFormValidator();
  late final EmployeeJoinCodeValidator _joinCodeValidator;
  bool _isLoading = false;
  bool _isJoinCodeValid = false;
  String? _message;
  bool _isError = false;

  @override
  void initState() {
    super.initState();
    _joinCodeValidator =
        widget.joinCodeValidator ?? EmployeeJoinCodeValidator();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _joinCodeController.dispose();
    super.dispose();
  }

  Future<void> _validateAndContinue() async {
    FocusScope.of(context).unfocus();
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _message = null;
      _isJoinCodeValid = false;
    });
    try {
      final result = await _joinCodeValidator.validate(
        _joinCodeController.text,
      );
      if (!mounted) return;
      switch (result.status) {
        case EmployeeJoinCodeStatus.invalidCode:
          _showMessage('كود الانضمام غير صحيح', isError: true);
          break;
        case EmployeeJoinCodeStatus.missingStore:
          _showMessage('المتجر المرتبط بكود الانضمام غير متاح', isError: true);
          break;
        case EmployeeJoinCodeStatus.valid:
          _showMessage('كود الانضمام صالح. ستتوفر متابعة التسجيل لاحقًا.');
          setState(() => _isJoinCodeValid = true);
          break;
      }
    } on FirebaseException catch (error) {
      if (!mounted) return;
      if (error.code == 'permission-denied') {
        _showMessage(
          'تعذر التحقق من كود الانضمام بسبب صلاحيات القراءة. لا يمكن إكمال التحقق قبل تحديث آمن للصلاحيات.',
          isError: true,
        );
      } else {
        _showMessage(
          'تعذر التحقق من كود الانضمام. حاول مرة أخرى.',
          isError: true,
        );
      }
    } catch (_) {
      if (!mounted) return;
      _showMessage(
        'تعذر التحقق من كود الانضمام. حاول مرة أخرى.',
        isError: true,
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showMessage(String message, {bool isError = false}) {
    setState(() {
      _message = message;
      _isError = isError;
    });
  }

  @override
  Widget build(BuildContext context) => Directionality(
    textDirection: TextDirection.rtl,
    child: Scaffold(
      appBar: AppBar(title: const Text('إنشاء حساب موظف')),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 500),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Icon(Icons.badge_outlined, size: 64),
                    const SizedBox(height: 16),
                    const Text(
                      'إنشاء حساب موظف',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 24),
                    TextFormField(
                      controller: _nameController,
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(
                        labelText: 'الاسم الكامل',
                        prefixIcon: Icon(Icons.person_outline),
                        border: OutlineInputBorder(),
                      ),
                      validator: _formValidator.validateName,
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _emailController,
                      keyboardType: TextInputType.emailAddress,
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(
                        labelText: 'البريد الإلكتروني',
                        prefixIcon: Icon(Icons.email_outlined),
                        border: OutlineInputBorder(),
                      ),
                      validator: _formValidator.validateEmail,
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _passwordController,
                      obscureText: true,
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(
                        labelText: 'كلمة المرور',
                        prefixIcon: Icon(Icons.lock_outline),
                        border: OutlineInputBorder(),
                      ),
                      validator: _formValidator.validatePassword,
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _confirmPasswordController,
                      obscureText: true,
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(
                        labelText: 'تأكيد كلمة المرور',
                        prefixIcon: Icon(Icons.lock_reset_outlined),
                        border: OutlineInputBorder(),
                      ),
                      validator: (value) =>
                          _formValidator.validatePasswordConfirmation(
                            value,
                            _passwordController.text,
                          ),
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _joinCodeController,
                      textCapitalization: TextCapitalization.characters,
                      textInputAction: TextInputAction.done,
                      decoration: const InputDecoration(
                        labelText: 'كود الانضمام',
                        hintText: 'XXXX-XXXX-XXXX-XXXX',
                        prefixIcon: Icon(Icons.key_outlined),
                        border: OutlineInputBorder(),
                      ),
                      validator: _formValidator.validateJoinCode,
                      onChanged: (_) {
                        if (_isJoinCodeValid || _message != null) {
                          setState(() {
                            _isJoinCodeValid = false;
                            _message = null;
                          });
                        }
                      },
                    ),
                    if (_message != null) ...[
                      const SizedBox(height: 16),
                      Text(
                        _message!,
                        textAlign: TextAlign.center,
                        key: const ValueKey('employee-registration-message'),
                        style: TextStyle(
                          color: _isError
                              ? Theme.of(context).colorScheme.error
                              : Theme.of(context).colorScheme.primary,
                        ),
                      ),
                    ],
                    const SizedBox(height: 24),
                    SizedBox(
                      height: 52,
                      child: FilledButton(
                        onPressed: _isLoading || _isJoinCodeValid
                            ? null
                            : _validateAndContinue,
                        child: _isLoading
                            ? const SizedBox.square(
                                dimension: 22,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Text(
                                'إنشاء حساب الموظف',
                                style: TextStyle(fontWeight: FontWeight.bold),
                              ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
