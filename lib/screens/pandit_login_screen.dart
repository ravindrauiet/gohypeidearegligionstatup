import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/backend_service.dart';
import '../widgets/ui/app_ui.dart';
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
      showAppSnack(context, 'Welcome back, $name!');
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
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          tooltip: 'Back',
          onPressed: () => Navigator.maybePop(context),
        ),
        title: const Text('Partner login'),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(AppSpacing.page, AppSpacing.xs, AppSpacing.page, AppSpacing.xl),
                child: Form(
                  key: _formKey,
                  child: AutofillGroup(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const _BrandHeader(),
                        const SizedBox(height: AppSpacing.xl),
                        AppCard(
                          padding: const EdgeInsets.all(AppSpacing.md),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              const Text('Account details', style: AppText.subtitle),
                              const SizedBox(height: 2),
                              Text('Use the email you registered as a partner.',
                                  style: AppText.caption.copyWith(color: AppColors.textSecondary)),
                              const SizedBox(height: AppSpacing.md),
                              TextFormField(
                                controller: _emailController,
                                keyboardType: TextInputType.emailAddress,
                                textInputAction: TextInputAction.next,
                                autofillHints: const [AutofillHints.email, AutofillHints.username],
                                enabled: !_isLoading,
                                autovalidateMode: AutovalidateMode.onUserInteraction,
                                onFieldSubmitted: (_) => _passwordFocus.requestFocus(),
                                validator: (v) {
                                  final value = (v ?? '').trim();
                                  if (value.isEmpty) return 'Please enter your email';
                                  if (!_emailPattern.hasMatch(value)) return 'Please enter a valid email';
                                  return null;
                                },
                                decoration: const InputDecoration(
                                  labelText: 'Email',
                                  prefixIcon: Icon(Icons.mail_outline_rounded),
                                ),
                              ),
                              const SizedBox(height: AppSpacing.sm),
                              TextFormField(
                                controller: _passwordController,
                                focusNode: _passwordFocus,
                                obscureText: _obscurePassword,
                                textInputAction: TextInputAction.done,
                                autofillHints: const [AutofillHints.password],
                                enabled: !_isLoading,
                                autovalidateMode: AutovalidateMode.onUserInteraction,
                                onFieldSubmitted: (_) => _login(),
                                validator: (v) => (v ?? '').trim().isEmpty ? 'Please enter your password' : null,
                                decoration: InputDecoration(
                                  labelText: 'Password',
                                  prefixIcon: const Icon(Icons.lock_outline_rounded),
                                  suffixIcon: IconButton(
                                    icon: Icon(
                                        _obscurePassword ? Icons.visibility_off_outlined : Icons.visibility_outlined),
                                    tooltip: _obscurePassword ? 'Show password' : 'Hide password',
                                    onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                                  ),
                                ),
                              ),
                              if (_errorText != null) ...[
                                const SizedBox(height: AppSpacing.sm),
                                _ErrorBanner(message: _errorText!),
                              ],
                            ],
                          ),
                        ),
                        const SizedBox(height: AppSpacing.md),
                        AppCard(
                          padding: EdgeInsets.zero,
                          child: Column(
                            children: [
                              AppListRow(
                                icon: Icons.person_add_alt_1_rounded,
                                color: AppColors.primary,
                                title: 'New partner? Create an account',
                                subtitle: 'Register to start taking live consultations',
                                onTap: _isLoading ? null : _openRegistration,
                              ),
                              const Divider(height: 1),
                              AppListRow(
                                icon: Icons.science_outlined,
                                color: AppColors.info,
                                title: 'Use demo partner account',
                                subtitle: 'Fills in sample login details',
                                onTap: _isLoading ? null : _fillDemoCredentials,
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
            _StickyBar(
              child: AppButton(
                label: 'Log in',
                icon: Icons.login_rounded,
                loading: _isLoading,
                onPressed: _isLoading ? null : _login,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BrandHeader extends StatelessWidget {
  const _BrandHeader();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 52,
          height: 52,
          decoration:
              BoxDecoration(gradient: AppColors.cosmicGradient, borderRadius: BorderRadius.circular(AppRadius.lg)),
          child: const Icon(Icons.auto_awesome_rounded, color: AppColors.gold, size: 26),
        ),
        const SizedBox(width: AppSpacing.sm),
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('CosmicGuide Partner', style: AppText.headline, maxLines: 1, overflow: TextOverflow.ellipsis),
              SizedBox(height: 2),
              Text('Manage your consultations, queue and earnings.',
                  style: AppText.body, maxLines: 2, overflow: TextOverflow.ellipsis),
            ],
          ),
        ),
      ],
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  final String message;
  const _ErrorBanner({required this.message});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      liveRegion: true,
      child: Container(
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
              child: Text(message, style: AppText.caption.copyWith(color: AppColors.danger, height: 1.4)),
            ),
          ],
        ),
      ),
    );
  }
}

class _StickyBar extends StatelessWidget {
  final Widget child;
  const _StickyBar({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(AppSpacing.page, AppSpacing.sm, AppSpacing.page, AppSpacing.sm),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: child,
    );
  }
}
