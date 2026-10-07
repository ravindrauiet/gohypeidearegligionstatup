import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/backend_service.dart';
import 'pandit_dashboard_screen.dart';
import 'pandit_registration_screen.dart';

final RegExp _emailPattern = RegExp(r'^[\w.+-]+@([\w-]+\.)+[\w-]{2,}$');

class PanditLoginScreen extends StatefulWidget {
  /// Optional email to prefill (e.g. when redirected from registration
  /// because the account already exists).
  final String? initialEmail;

  const PanditLoginScreen({super.key, this.initialEmail});

  @override
  State<PanditLoginScreen> createState() => _PanditLoginScreenState();
}

class _PanditLoginScreenState extends State<PanditLoginScreen> {
  static const String _demoEmail = 'rishiraj@astroai.com';
  static const String _demoPassword = 'pandit123';

  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _emailController;
  final _passwordController = TextEditingController();
  final _passwordFocus = FocusNode();
  bool _isLoading = false;
  bool _obscurePassword = true;
  String? _errorText;

  @override
  void initState() {
    super.initState();
    _emailController = TextEditingController(text: widget.initialEmail ?? '');
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _passwordFocus.dispose();
    super.dispose();
  }

  void _fillDemoCredentials() {
    setState(() {
      _emailController.text = _demoEmail;
      _passwordController.text = _demoPassword;
      _errorText = null;
    });
  }

  Future<void> _login() async {
    FocusScope.of(context).unfocus();
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();

    setState(() {
      _isLoading = true;
      _errorText = null;
    });

    final backendService = Provider.of<BackendService>(context, listen: false);
    Map<String, dynamic>? pandit;
    try {
      pandit = await backendService.loginPandit(email: email, password: password);
    } catch (_) {
      pandit = null;
    }

    if (!mounted) return;
    setState(() => _isLoading = false);

    if (pandit != null) {
      final name = (pandit['full_name'] ?? 'Pandit Ji').toString();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Welcome back, $name!'),
          backgroundColor: const Color(0xFF059669),
        ),
      );
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => const PanditDashboardScreen()),
      );
    } else {
      setState(() {
        _errorText = backendService.lastError ??
            'Login failed. Please check your email and password, or your internet connection, and try again.';
      });
    }
  }

  Future<void> _openRegistration() async {
    // Registration pops with `true` on success, or with the email (String)
    // when that account already exists and should log in instead.
    final result = await Navigator.push<Object?>(
      context,
      MaterialPageRoute(
        builder: (context) => const PanditRegistrationScreen(returnResultToCaller: true),
      ),
    );
    if (!mounted) return;
    if (result == true) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => const PanditDashboardScreen()),
      );
    } else if (result is String && result.isNotEmpty) {
      setState(() {
        _emailController.text = result;
        _passwordController.clear();
        _errorText = null;
      });
      _passwordFocus.requestFocus();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1E1A38),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E1A38),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white),
          tooltip: 'Back',
          onPressed: () => Navigator.maybePop(context),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Center(
                child: CircleAvatar(
                  radius: 40,
                  backgroundColor: Color(0xFFFFD700),
                  child: Icon(Icons.auto_awesome_rounded, color: Colors.black, size: 44),
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'CosmicGuide Pandit Partner Portal',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 4),
              const Text(
                'Exclusive Astrologer Account Login',
                textAlign: TextAlign.center,
                style: TextStyle(color: Color(0xFFFFD700), fontSize: 13, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 28),
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(24),
                ),
                child: Form(
                  key: _formKey,
                  child: AutofillGroup(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Text(
                          'PANDIT ACCOUNT LOGIN',
                          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900, color: Colors.grey, letterSpacing: 1.0),
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: _emailController,
                          keyboardType: TextInputType.emailAddress,
                          textInputAction: TextInputAction.next,
                          autofillHints: const [AutofillHints.email, AutofillHints.username],
                          enabled: !_isLoading,
                          onFieldSubmitted: (_) => _passwordFocus.requestFocus(),
                          validator: (v) {
                            final value = (v ?? '').trim();
                            if (value.isEmpty) return 'Please enter your email';
                            if (!_emailPattern.hasMatch(value)) return 'Please enter a valid email';
                            return null;
                          },
                          decoration: InputDecoration(
                            labelText: 'Registered Pandit Email',
                            prefixIcon: const Icon(Icons.email_outlined),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                          ),
                        ),
                        const SizedBox(height: 14),
                        TextFormField(
                          controller: _passwordController,
                          focusNode: _passwordFocus,
                          obscureText: _obscurePassword,
                          textInputAction: TextInputAction.done,
                          autofillHints: const [AutofillHints.password],
                          enabled: !_isLoading,
                          onFieldSubmitted: (_) => _login(),
                          validator: (v) => (v ?? '').trim().isEmpty ? 'Please enter your password' : null,
                          decoration: InputDecoration(
                            labelText: 'Pandit Password',
                            prefixIcon: const Icon(Icons.lock_outline),
                            suffixIcon: IconButton(
                              icon: Icon(_obscurePassword ? Icons.visibility_off : Icons.visibility),
                              tooltip: _obscurePassword ? 'Show password' : 'Hide password',
                              onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                            ),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                          ),
                        ),
                        if (_errorText != null) ...[
                          const SizedBox(height: 12),
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.red.withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Icon(Icons.error_outline_rounded, color: Colors.red, size: 18),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    _errorText!,
                                    style: const TextStyle(color: Colors.red, fontSize: 12, height: 1.4),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                        const SizedBox(height: 20),
                        SizedBox(
                          height: 52,
                          child: ElevatedButton(
                            onPressed: _isLoading ? null : _login,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFFE83D66),
                              disabledBackgroundColor: const Color(0xFFE83D66).withValues(alpha: 0.6),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                            ),
                            child: _isLoading
                                ? const SizedBox(
                                    width: 22,
                                    height: 22,
                                    child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.4),
                                  )
                                : const FittedBox(
                                    fit: BoxFit.scaleDown,
                                    child: Text(
                                      'Login to Pandit Dashboard',
                                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                                    ),
                                  ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        TextButton(
                          onPressed: _isLoading ? null : _fillDemoCredentials,
                          child: const Text(
                            'Use demo Pandit account',
                            style: TextStyle(color: Colors.grey, fontSize: 12),
                          ),
                        ),
                        TextButton(
                          onPressed: _isLoading ? null : _openRegistration,
                          child: const Text(
                            "Don't have a Pandit Account? Register Here",
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Color(0xFF9C27B0), fontWeight: FontWeight.bold),
                          ),
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
    );
  }
}
