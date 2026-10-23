import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:fluttertoast/fluttertoast.dart';
import '../../services/backend_service.dart';
import '../../utils/app_routes.dart';
import '../../utils/validators.dart';
import '../../widgets/ui/app_ui.dart';

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
        backgroundColor: AppColors.textPrimary,
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

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_isSubmitting,
      child: Scaffold(
        backgroundColor: AppColors.surface,
        appBar: AppBar(
          leading: IconButton(
            tooltip: 'Back',
            icon: const Icon(Icons.arrow_back_rounded),
            onPressed: _isSubmitting ? null : _goToLogin,
          ),
        ),
        body: SafeArea(
          top: false,
          child: Column(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  padding:
                      const EdgeInsets.fromLTRB(AppSpacing.page + 4, AppSpacing.xs, AppSpacing.page + 4, AppSpacing.xl),
                  keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 480),
                      child: AutofillGroup(
                        child: Form(
                          key: _formKey,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              const Text('Create Account', style: AppText.display),
                              const SizedBox(height: 6),
                              const Text(
                                'Join CosmicGuide to save your Kundli & readings securely.',
                                style: AppText.body,
                              ),
                              const SizedBox(height: AppSpacing.xl),
                              TextFormField(
                                controller: _nameController,
                                enabled: !_isSubmitting,
                                textCapitalization: TextCapitalization.words,
                                textInputAction: TextInputAction.next,
                                autofillHints: const [AutofillHints.name],
                                decoration: const InputDecoration(
                                  labelText: 'Full Name',
                                  prefixIcon: Icon(Icons.person_outline_rounded),
                                ),
                                validator: Validators.name,
                              ),
                              const SizedBox(height: AppSpacing.sm),
                              TextFormField(
                                controller: _emailController,
                                enabled: !_isSubmitting,
                                keyboardType: TextInputType.emailAddress,
                                textInputAction: TextInputAction.next,
                                autocorrect: false,
                                autofillHints: const [AutofillHints.email],
                                decoration: const InputDecoration(
                                  labelText: 'Email Address',
                                  prefixIcon: Icon(Icons.mail_outline_rounded),
                                ),
                                validator: Validators.email,
                              ),
                              const SizedBox(height: AppSpacing.sm),
                              TextFormField(
                                controller: _passwordController,
                                enabled: !_isSubmitting,
                                obscureText: !_isPasswordVisible,
                                textInputAction: TextInputAction.done,
                                autocorrect: false,
                                enableSuggestions: false,
                                autofillHints: const [AutofillHints.newPassword],
                                onFieldSubmitted: (_) => _register(),
                                decoration: InputDecoration(
                                  labelText: 'Password',
                                  helperText: 'At least 6 characters',
                                  prefixIcon: const Icon(Icons.lock_outline_rounded),
                                  suffixIcon: IconButton(
                                    tooltip: _isPasswordVisible ? 'Hide password' : 'Show password',
                                    icon: Icon(
                                      _isPasswordVisible ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                                      color: AppColors.textTertiary,
                                    ),
                                    onPressed: () => setState(() => _isPasswordVisible = !_isPasswordVisible),
                                  ),
                                ),
                                validator: (val) => Validators.password(val, isNew: true),
                              ),
                              if (_errorMessage != null) ...[
                                const SizedBox(height: AppSpacing.sm),
                                Container(
                                  padding: const EdgeInsets.all(AppSpacing.sm),
                                  decoration: BoxDecoration(
                                    color: AppColors.dangerSoft,
                                    borderRadius: BorderRadius.circular(AppRadius.md),
                                  ),
                                  child: Row(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      const Icon(Icons.error_outline_rounded, color: AppColors.danger, size: 18),
                                      const SizedBox(width: AppSpacing.xs),
                                      Expanded(
                                        child: Text(
                                          _errorMessage!,
                                          style: const TextStyle(
                                            color: AppColors.danger,
                                            fontSize: 13.5,
                                            height: 1.35,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              // Sticky bottom actions.
              DecoratedBox(
                decoration: const BoxDecoration(
                  color: AppColors.surface,
                  border: Border(top: BorderSide(color: AppColors.divider)),
                ),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(AppSpacing.page, AppSpacing.sm, AppSpacing.page, AppSpacing.xs),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 480),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          AppButton(
                            label: 'Create Account',
                            onPressed: _isSubmitting ? null : _register,
                            loading: _isSubmitting,
                          ),
                          TextButton(
                            onPressed: _isSubmitting ? null : _goToLogin,
                            style: TextButton.styleFrom(minimumSize: const Size(48, 44)),
                            child: const Text.rich(
                              TextSpan(
                                text: 'Already have an account? ',
                                style: TextStyle(
                                  fontSize: 14.5,
                                  color: AppColors.textSecondary,
                                  fontWeight: FontWeight.w500,
                                ),
                                children: [
                                  TextSpan(
                                    text: 'Sign In',
                                    style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.primary),
                                  ),
                                ],
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
