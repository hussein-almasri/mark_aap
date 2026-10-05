import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../../core/utils/employee_registration_form_validator.dart';
import '../../../data/services/employee_join_code_validator.dart';
import '../services/employee_registration_service.dart';

class EmployeeRegistrationScreen extends StatefulWidget {
  const EmployeeRegistrationScreen({
    this.joinCodeValidator,
    this.registrationService,
    super.key,
  });

  final EmployeeJoinCodeValidator? joinCodeValidator;
  final EmployeeRegistrationService? registrationService;

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
  late final EmployeeRegistrationService _registrationService;
  bool _isLoading = false;
  String? _message;
  bool _isError = false;

  @override
  void initState() {
    super.initState();
    if (widget.registrationService != null) {
      _registrationService = widget.registrationService!;
    } else {
      final joinCodeValidator =
          widget.joinCodeValidator ?? EmployeeJoinCodeValidator();
      _registrationService = EmployeeRegistrationService(
        joinCodeValidator: joinCodeValidator,
        auth: FirebaseEmployeeRegistrationAuth(),
        writer: FirestoreEmployeeRegistrationWriter(),
      );
    }
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

  Future<void> _register() async {
    if (_isLoading) return;
    FocusScope.of(context).unfocus();
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _isLoading = true;
      _message = null;
    });
    try {
      await _registrationService.register(
        displayName: _nameController.text,
        email: _emailController.text,
        password: _passwordController.text,
        joinCode: _joinCodeController.text,
      );
      // AuthGate observes the newly signed-in Firebase user.
    } on InvalidEmployeeJoinCodeException {
      if (mounted) {
        _showMessage('كود الانضمام غير صحيح أو لم يعد فعالًا.', isError: true);
      }
    } on FirebaseAuthException catch (error) {
      if (mounted) {
        _showMessage(employeeAuthErrorMessage(error), isError: true);
      }
    } on EmployeeRegistrationException catch (error) {
      if (!mounted) return;
      final denied =
          error.cause is FirebaseException &&
          (error.cause as FirebaseException).code == 'permission-denied';
      _showMessage(
        error.cleanupError == null
            ? (denied
                  ? 'تعذر إكمال التسجيل بسبب رفض صلاحيات الحفظ.'
                  : 'تعذر إكمال التسجيل. حاول مرة أخرى.')
            : (denied
                  ? 'رفض Firestore حفظ التسجيل، كما تعذر حذف حساب Auth غير المكتمل. تواصل مع المسؤول.'
                  : 'فشل حفظ بيانات التسجيل وتعذر حذف حساب Auth غير المكتمل. تواصل مع المسؤول.'),
        isError: true,
      );
    } catch (_) {
      if (mounted) {
        _showMessage(
          'تعذر إنشاء الحساب. تحقق من الاتصال وحاول مرة أخرى.',
          isError: true,
        );
      }
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
                        if (_message != null) {
                          setState(() {
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
                        onPressed: _isLoading ? null : _register,
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
