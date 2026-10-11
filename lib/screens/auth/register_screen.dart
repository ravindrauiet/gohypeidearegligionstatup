import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:fluttertoast/fluttertoast.dart';
import '../../services/backend_service.dart';
import '../../utils/app_routes.dart';
import '../../utils/validators.dart';
import '../../widgets/cosmic_background.dart';

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

  static const _fieldText = TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w500);

  @override
  Widget build(BuildContext context) {
    final muted = Colors.white.withValues(alpha: 0.78);
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light.copyWith(
        statusBarColor: Colors.transparent,
        systemNavigationBarColor: cosmicNight,
        systemNavigationBarIconBrightness: Brightness.light,
      ),
      child: PopScope(
        canPop: !_isSubmitting,
        child: Scaffold(
          backgroundColor: cosmicNight,
          extendBodyBehindAppBar: true,
          appBar: AppBar(
            backgroundColor: Colors.transparent,
            foregroundColor: Colors.white,
            elevation: 0,
            scrolledUnderElevation: 0,
            systemOverlayStyle: SystemUiOverlayStyle.light,
            leading: IconButton(
              tooltip: 'Back',
              icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white),
              onPressed: _isSubmitting ? null : _goToLogin,
            ),
          ),
          body: Stack(
            fit: StackFit.expand,
            children: [
              const ExcludeSemantics(child: CosmicBackground(accent: Color(0xFFFFA45C), epoch: 0)),
              SafeArea(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                  keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 480),
                      child: CosmicFormTheme(
                        child: AutofillGroup(
                          child: Form(
                            key: _formKey,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const ExcludeSemantics(child: CosmicMark(size: 34)),
                                const SizedBox(height: 14),
                                const Text(
                                  'Create Account',
                                  style: TextStyle(
                                    fontSize: 30,
                                    fontWeight: FontWeight.w800,
                                    color: Colors.white,
                                    letterSpacing: -0.4,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  'Join CosmicGuide to save your Kundli & readings securely.',
                                  style: TextStyle(fontSize: 15, color: muted, height: 1.45),
                                ),
                                const SizedBox(height: 24),
                                Container(
                                  padding: const EdgeInsets.fromLTRB(16, 18, 16, 10),
                                  decoration: BoxDecoration(
                                    color: cosmicSheet.withValues(alpha: 0.72),
                                    borderRadius: BorderRadius.circular(28),
                                    border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
                                    boxShadow: const [
                                      BoxShadow(color: Color(0x80050314), blurRadius: 30, offset: Offset(0, 14)),
                                    ],
                                  ),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      // Name
                                      TextFormField(
                                        controller: _nameController,
                                        enabled: !_isSubmitting,
                                        style: _fieldText,
                                        textCapitalization: TextCapitalization.words,
                                        textInputAction: TextInputAction.next,
                                        autofillHints: const [AutofillHints.name],
                                        decoration: cosmicInputDecoration('Full Name', Icons.person_outline),
                                        validator: Validators.name,
                                      ),
                                      const SizedBox(height: 14),

                                      // Email
                                      TextFormField(
                                        controller: _emailController,
                                        enabled: !_isSubmitting,
                                        style: _fieldText,
                                        keyboardType: TextInputType.emailAddress,
                                        textInputAction: TextInputAction.next,
                                        autocorrect: false,
                                        autofillHints: const [AutofillHints.email],
                                        decoration: cosmicInputDecoration('Email Address', Icons.email_outlined),
                                        validator: Validators.email,
                                      ),
                                      const SizedBox(height: 14),

                                      // Password with visibility toggle
                                      TextFormField(
                                        controller: _passwordController,
                                        enabled: !_isSubmitting,
                                        style: _fieldText,
                                        obscureText: !_isPasswordVisible,
                                        textInputAction: TextInputAction.done,
                                        autocorrect: false,
                                        enableSuggestions: false,
                                        autofillHints: const [AutofillHints.newPassword],
                                        onFieldSubmitted: (_) => _register(),
                                        decoration: cosmicInputDecoration(
                                          'Password',
                                          Icons.lock_outline,
                                          suffix: IconButton(
                                            tooltip: _isPasswordVisible ? 'Hide password' : 'Show password',
                                            icon: Icon(
                                              _isPasswordVisible ? Icons.visibility : Icons.visibility_off,
                                              color: Colors.white.withValues(alpha: 0.82),
                                            ),
                                            onPressed: () => setState(() => _isPasswordVisible = !_isPasswordVisible),
                                          ),
                                        ),
                                        validator: (val) => Validators.password(val, isNew: true),
                                      ),

                                      if (_errorMessage != null) ...[
                                        const SizedBox(height: 14),
                                        Container(
                                          padding: const EdgeInsets.all(12),
                                          decoration: BoxDecoration(
                                            color: cosmicError.withValues(alpha: 0.12),
                                            borderRadius: BorderRadius.circular(14),
                                            border: Border.all(color: cosmicError.withValues(alpha: 0.5)),
                                          ),
                                          child: Row(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              const Icon(Icons.error_outline, color: cosmicError, size: 18),
                                              const SizedBox(width: 8),
                                              Expanded(
                                                child: Text(
                                                  _errorMessage!,
                                                  style: const TextStyle(
                                                    color: Color(0xFFFFC9C9),
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
                                      const SizedBox(height: 22),

                                      // Register Button
                                      CosmicPrimaryButton(
                                        label: 'Create Account',
                                        onPressed: _isSubmitting ? null : _register,
                                        loading: _isSubmitting,
                                      ),
                                      const SizedBox(height: 6),

                                      Center(
                                        child: TextButton(
                                          onPressed: _isSubmitting ? null : _goToLogin,
                                          style: TextButton.styleFrom(
                                            foregroundColor: Colors.white,
                                            minimumSize: const Size(48, 44),
                                          ),
                                          child: Text.rich(
                                            TextSpan(
                                              text: 'Already have an account? ',
                                              style: TextStyle(fontSize: 14.5, color: muted),
                                              children: const [
                                                TextSpan(
                                                  text: 'Sign In',
                                                  style: TextStyle(
                                                    fontWeight: FontWeight.w800,
                                                    color: cosmicGoldLight,
                                                    decoration: TextDecoration.underline,
                                                    decorationColor: cosmicGoldLight,
                                                  ),
                                                ),
                                              ],
                                            ),
                                            textAlign: TextAlign.center,
                                          ),
                                        ),
                                      ),
                                    ],
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
              ),
            ],
          ),
        ),
      ),
    );
  }
}
