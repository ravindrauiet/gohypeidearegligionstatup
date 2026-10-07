import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:fluttertoast/fluttertoast.dart';
import '../../services/backend_service.dart';
import '../../utils/app_routes.dart';
import '../../utils/validators.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isPasswordVisible = false;
  bool _isSubmitting = false;
  String? _errorMessage;

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _register() async {
    if (_isSubmitting) return;
    FocusScope.of(context).unfocus();
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    final backendService = context.read<BackendService>();
    bool success = false;
    try {
      success = await backendService.register(
        _nameController.text.trim(),
        _emailController.text.trim().toLowerCase(),
        _passwordController.text,
      );
    } catch (e) {
      debugPrint('Registration failed: $e');
    }

    if (!mounted) return;

    if (success) {
      Fluttertoast.showToast(
        msg: 'Account created successfully!',
        backgroundColor: Colors.black,
        textColor: Colors.white,
      );
      Navigator.pushNamedAndRemoveUntil(
        context,
        AuthFlow.routeAfterLogin(backendService),
        (route) => false,
      );
    } else {
      setState(() {
        _isSubmitting = false;
        _errorMessage = backendService.lastError ??
            'Registration failed. This email may already be registered, or you may be offline.';
      });
    }
  }

  void _goToLogin() {
    final navigator = Navigator.of(context);
    // If we came from the login screen, just go back to it instead of
    // stacking a second login screen on top.
    if (navigator.canPop()) {
      navigator.pop();
    } else {
      navigator.pushReplacementNamed(AppRoutes.login);
    }
  }

  InputDecoration _decoration(String label, IconData icon, {Widget? suffix}) {
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(16),
      borderSide: BorderSide(color: Colors.black.withValues(alpha: 0.1)),
    );
    return InputDecoration(
      labelText: label,
      filled: true,
      fillColor: Colors.white,
      prefixIcon: Icon(icon, color: Colors.black54),
      suffixIcon: suffix,
      border: border,
      enabledBorder: border,
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_isSubmitting,
      child: Scaffold(
        backgroundColor: const Color(0xFFFCF7F1),
        appBar: AppBar(
          backgroundColor: const Color(0xFFFCF7F1),
          elevation: 0,
          scrolledUnderElevation: 0,
          leading: IconButton(
            tooltip: 'Back',
            icon: const Icon(Icons.arrow_back_ios_new, color: Colors.black),
            onPressed: _isSubmitting ? null : _goToLogin,
          ),
        ),
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24.0),
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            child: AutofillGroup(
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Create Account',
                      style: TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                          color: Colors.black),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Join CosmicGuide to save your Kundli & readings securely.',
                      style:
                          TextStyle(fontSize: 14, color: Colors.grey.shade700),
                    ),
                    const SizedBox(height: 32),

                    // Name
                    TextFormField(
                      controller: _nameController,
                      enabled: !_isSubmitting,
                      textCapitalization: TextCapitalization.words,
                      textInputAction: TextInputAction.next,
                      autofillHints: const [AutofillHints.name],
                      decoration:
                          _decoration('Full Name', Icons.person_outline),
                      validator: Validators.name,
                    ),
                    const SizedBox(height: 16),

                    // Email
                    TextFormField(
                      controller: _emailController,
                      enabled: !_isSubmitting,
                      keyboardType: TextInputType.emailAddress,
                      textInputAction: TextInputAction.next,
                      autocorrect: false,
                      autofillHints: const [AutofillHints.email],
                      decoration:
                          _decoration('Email Address', Icons.email_outlined),
                      validator: Validators.email,
                    ),
                    const SizedBox(height: 16),

                    // Password with visibility toggle
                    TextFormField(
                      controller: _passwordController,
                      enabled: !_isSubmitting,
                      obscureText: !_isPasswordVisible,
                      textInputAction: TextInputAction.done,
                      autocorrect: false,
                      enableSuggestions: false,
                      autofillHints: const [AutofillHints.newPassword],
                      onFieldSubmitted: (_) => _register(),
                      decoration: _decoration(
                        'Password',
                        Icons.lock_outline,
                        suffix: IconButton(
                          tooltip: _isPasswordVisible
                              ? 'Hide password'
                              : 'Show password',
                          icon: Icon(
                              _isPasswordVisible
                                  ? Icons.visibility
                                  : Icons.visibility_off,
                              color: Colors.black87),
                          onPressed: () => setState(
                              () => _isPasswordVisible = !_isPasswordVisible),
                        ),
                      ),
                      validator: (val) => Validators.password(val, isNew: true),
                    ),

                    if (_errorMessage != null) ...[
                      const SizedBox(height: 14),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(Icons.error_outline,
                              color: Colors.redAccent, size: 18),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _errorMessage!,
                              style: const TextStyle(
                                  color: Colors.redAccent, fontSize: 13),
                            ),
                          ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 28),

                    // Register Button
                    SizedBox(
                      width: double.infinity,
                      height: 54,
                      child: ElevatedButton(
                        onPressed: _isSubmitting ? null : _register,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.black,
                          disabledBackgroundColor: Colors.black54,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(30)),
                        ),
                        child: _isSubmitting
                            ? const SizedBox(
                                width: 24,
                                height: 24,
                                child: CircularProgressIndicator(
                                    color: Colors.white, strokeWidth: 2))
                            : const Text('Create Account',
                                style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold)),
                      ),
                    ),
                    const SizedBox(height: 12),

                    Center(
                      child: TextButton(
                        onPressed: _isSubmitting ? null : _goToLogin,
                        style:
                            TextButton.styleFrom(foregroundColor: Colors.black),
                        child: Text.rich(
                          TextSpan(
                            text: 'Already have an account? ',
                            style: TextStyle(color: Colors.grey.shade700),
                            children: const [
                              TextSpan(
                                text: 'Sign In',
                                style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: Colors.black),
                              ),
                            ],
                          ),
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
    );
  }
}
