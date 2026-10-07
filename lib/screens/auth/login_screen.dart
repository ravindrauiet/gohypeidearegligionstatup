import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:fluttertoast/fluttertoast.dart';
import '../../services/backend_service.dart';
import '../../utils/app_routes.dart';
import '../../utils/validators.dart';
import '../../widgets/google_logo_widget.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  bool _sheetOpen = false;

  /// Google Sign-In is not wired up yet (no google_sign_in package / backend
  /// endpoint). Instead of silently creating a throw-away account, explain and
  /// fall back to email sign-in so the user's data is actually saved.
  void _handleGoogleLogin() {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(
          content: Text(
            'Google sign-in is coming soon. Please continue with email to keep your data saved.',
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
    _showEmailAuthModal();
  }

  Future<void> _showEmailAuthModal({bool signUp = false}) async {
    if (_sheetOpen) return;
    _sheetOpen = true;
    final success = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: const Color(0xFFFCF7F1),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (_) => _EmailAuthSheet(initialSignUp: signUp),
    );
    _sheetOpen = false;

    if (!mounted) return;
    final backendService = context.read<BackendService>();
    // Also handles the sheet being dismissed while a request was finishing.
    if (success != true && !backendService.isAuthenticated) return;
    Fluttertoast.showToast(
      msg: 'Signed in successfully!',
      backgroundColor: Colors.black,
      textColor: Colors.white,
    );
    // Clear the whole entry stack so back never returns to the login screen.
    Navigator.pushNamedAndRemoveUntil(
      context,
      AuthFlow.routeAfterLogin(backendService),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // 1. Fullscreen Celestial Background
          Positioned.fill(
            child: Image.asset(
              'assets/images/login_bg.jpg',
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) {
                return Container(
                  color: const Color(0xFF1B1636),
                );
              },
            ),
          ),

          // 2. Main Content (scrollable so short screens / landscape never overflow)
          SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) => SingleChildScrollView(
                padding:
                    const EdgeInsets.symmetric(horizontal: 28, vertical: 20),
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    minHeight:
                        (constraints.maxHeight - 40).clamp(0, double.infinity),
                  ),
                  child: IntrinsicHeight(
                    child: Column(
                      children: [
                        const SizedBox(height: 40),
                        const _BrandTitle(),
                        const Spacer(),
                        const SizedBox(height: 32),

                        // Descriptive Subtitle
                        const Text(
                          'Sign in to save your Kundli securely and pick up right where you left off on any device.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 15,
                            color: Colors.white,
                            fontWeight: FontWeight.w500,
                            height: 1.45,
                            shadows: [
                              Shadow(color: Colors.black45, blurRadius: 8),
                            ],
                          ),
                        ),

                        const SizedBox(height: 28),

                        // Button 1: Continue with Google
                        _AuthOptionButton(
                          onPressed: _handleGoogleLogin,
                          icon: const GoogleLogoWidget(size: 24),
                          label: 'Continue with Google',
                        ),

                        const SizedBox(height: 16),

                        // Button 2: Login with Email
                        _AuthOptionButton(
                          onPressed: () => _showEmailAuthModal(),
                          icon: const Icon(Icons.mail_outline_rounded,
                              color: Colors.black, size: 22),
                          label: 'Login with Email',
                        ),

                        const SizedBox(height: 12),

                        TextButton(
                          onPressed: () => _showEmailAuthModal(signUp: true),
                          style: TextButton.styleFrom(
                              foregroundColor: Colors.white),
                          child: const Text.rich(
                            TextSpan(
                              text: 'New here? ',
                              children: [
                                TextSpan(
                                  text: 'Create an account',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    decoration: TextDecoration.underline,
                                    decorationColor: Colors.white,
                                  ),
                                ),
                              ],
                            ),
                            style: TextStyle(
                              fontSize: 14,
                              shadows: [
                                Shadow(color: Colors.black54, blurRadius: 8),
                              ],
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
        ],
      ),
    );
  }
}

class _BrandTitle extends StatelessWidget {
  const _BrandTitle();

  @override
  Widget build(BuildContext context) {
    const shadow = [Shadow(color: Colors.black54, blurRadius: 12)];
    return FittedBox(
      fit: BoxFit.scaleDown,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'Cosmic',
            style: TextStyle(
              fontSize: 38,
              fontWeight: FontWeight.w900,
              color: Colors.white,
              letterSpacing: -0.5,
              shadows: shadow,
            ),
          ),
          const SizedBox(width: 6),
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: const Color(0xFFFFD700),
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFFFFD700).withValues(alpha: 0.6),
                  blurRadius: 12,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: const Icon(
              Icons.explore_rounded,
              color: Colors.black,
              size: 22,
            ),
          ),
          const SizedBox(width: 6),
          const Text(
            'Guide',
            style: TextStyle(
              fontSize: 38,
              fontWeight: FontWeight.w900,
              color: Color(0xFFFFD700),
              letterSpacing: -0.5,
              shadows: shadow,
            ),
          ),
        ],
      ),
    );
  }
}

class _AuthOptionButton extends StatelessWidget {
  const _AuthOptionButton({
    required this.onPressed,
    required this.icon,
    required this.label,
  });

  final VoidCallback onPressed;
  final Widget icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 56,
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.white,
          foregroundColor: Colors.black,
          elevation: 4,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            icon,
            const SizedBox(width: 12),
            Flexible(
              child: Text(
                label,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.black,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Bottom sheet with the email sign-in / sign-up form. Pops `true` on success.
class _EmailAuthSheet extends StatefulWidget {
  const _EmailAuthSheet({required this.initialSignUp});

  final bool initialSignUp;

  @override
  State<_EmailAuthSheet> createState() => _EmailAuthSheetState();
}

class _EmailAuthSheetState extends State<_EmailAuthSheet> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  late bool _isSignUpMode = widget.initialSignUp;
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

  InputDecoration _decoration(String label, IconData icon, {Widget? suffix}) {
    return InputDecoration(
      labelText: label,
      filled: true,
      fillColor: Colors.white,
      prefixIcon: Icon(icon),
      suffixIcon: suffix,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
    );
  }

  Future<void> _submit() async {
    if (_isSubmitting) return;
    FocusScope.of(context).unfocus();
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    final backendService = context.read<BackendService>();
    final email = _emailController.text.trim().toLowerCase();
    final password = _passwordController.text;

    bool success = false;
    try {
      if (_isSignUpMode) {
        success = await backendService.register(
          _nameController.text.trim(),
          email,
          password,
        );
      } else {
        // The backend creates the account on first login, so no client-side
        // "auto-register" retry is needed (it used to mask wrong passwords).
        success = await backendService.login(email, password);
      }
    } catch (e) {
      debugPrint('Email auth failed: $e');
      success = false;
    }

    if (!mounted) return;

    if (success) {
      Navigator.of(context).pop(true);
      return;
    }

    setState(() {
      _isSubmitting = false;
      _errorMessage = backendService.lastError ??
          (_isSignUpMode
              ? 'Could not create your account. This email may already be registered, or you may be offline.'
              : 'Sign in failed. Please check your password and internet connection.');
    });
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;

    return PopScope(
      // Block dismissing the sheet mid-request.
      canPop: !_isSubmitting,
      child: Padding(
        padding: EdgeInsets.only(bottom: bottomInset),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
          child: AutofillGroup(
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.grey.shade400,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Header Title
                  Text(
                    _isSignUpMode ? 'Create New Account' : 'Welcome Back',
                    style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: Colors.black),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _isSignUpMode
                        ? 'Save your birth details & Kundli securely'
                        : 'Sign in to access your saved Kundli & history',
                    style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
                  ),
                  const SizedBox(height: 20),

                  // Full Name Field (Only in Sign Up Mode)
                  if (_isSignUpMode) ...[
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
                    const SizedBox(height: 14),
                  ],

                  // Email Field
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
                  const SizedBox(height: 14),

                  // Password Field with visibility toggle
                  TextFormField(
                    controller: _passwordController,
                    enabled: !_isSubmitting,
                    obscureText: !_isPasswordVisible,
                    textInputAction: TextInputAction.done,
                    autocorrect: false,
                    enableSuggestions: false,
                    autofillHints: [
                      _isSignUpMode
                          ? AutofillHints.newPassword
                          : AutofillHints.password,
                    ],
                    onFieldSubmitted: (_) => _submit(),
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
                          color: Colors.black87,
                        ),
                        onPressed: () => setState(
                            () => _isPasswordVisible = !_isPasswordVisible),
                      ),
                    ),
                    validator: (val) =>
                        Validators.password(val, isNew: _isSignUpMode),
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

                  const SizedBox(height: 24),

                  // Action Submit Button
                  SizedBox(
                    width: double.infinity,
                    height: 54,
                    child: ElevatedButton(
                      onPressed: _isSubmitting ? null : _submit,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.black,
                        disabledBackgroundColor: Colors.black54,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(27)),
                      ),
                      child: _isSubmitting
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                  color: Colors.white, strokeWidth: 2),
                            )
                          : Text(
                              _isSignUpMode ? 'Create Account' : 'Continue',
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold),
                            ),
                    ),
                  ),

                  const SizedBox(height: 8),

                  // Toggle Sign In / Sign Up Mode
                  Center(
                    child: TextButton(
                      onPressed: _isSubmitting
                          ? null
                          : () => setState(() {
                                _isSignUpMode = !_isSignUpMode;
                                _errorMessage = null;
                              }),
                      style:
                          TextButton.styleFrom(foregroundColor: Colors.black),
                      child: Text.rich(
                        TextSpan(
                          style: const TextStyle(
                              fontSize: 14, color: Colors.black87),
                          children: [
                            TextSpan(
                                text: _isSignUpMode
                                    ? 'Already have an account? '
                                    : "Don't have an account? "),
                            TextSpan(
                              text: _isSignUpMode ? 'Sign In' : 'Sign Up',
                              style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: Colors.black,
                                  decoration: TextDecoration.underline),
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
    );
  }
}
