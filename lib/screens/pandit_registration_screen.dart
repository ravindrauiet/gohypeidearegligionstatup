import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../services/backend_service.dart';
import '../widgets/ui/app_ui.dart';
import 'pandit_dashboard_screen.dart';
import 'pandit_login_screen.dart';

final RegExp _emailPattern = RegExp(r'^[\w.+-]+@([\w-]+\.)+[\w-]{2,}$');

class PanditRegistrationScreen extends StatefulWidget {
  /// When true (opened from the Pandit login screen), a successful
  /// registration pops with `true` so the caller can open the dashboard
  /// instead of stacking a second dashboard/login route.
  final bool returnResultToCaller;

  const PanditRegistrationScreen({super.key, this.returnResultToCaller = false});

  @override
  State<PanditRegistrationScreen> createState() => _PanditRegistrationScreenState();
}

class _PanditRegistrationScreenState extends State<PanditRegistrationScreen> {
  static const List<String> _stepTitles = ['Account', 'Profile', 'Practice'];

  /// One form per step so each step validates only its own fields.
  final List<GlobalKey<FormState>> _formKeys = List.generate(3, (_) => GlobalKey<FormState>());
  int _step = 0;

  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _expController = TextEditingController();
  final TextEditingController _rateController = TextEditingController();
  final TextEditingController _bioController = TextEditingController();

  String _selectedSpecialty = 'Vedic Kundli & Guna Milan';
  String _selectedField = 'Vedic Kundli';
  final Set<String> _selectedLanguages = {'Hindi', 'English'};
  bool _obscurePassword = true;
  bool _isSubmitting = false;
  bool _languageError = false;
  String? _submitError;

  static const List<String> _specialties = [
    'Vedic Kundli & Guna Milan',
    'Love & Relationship Synastry',
    'Career, Business & Financial Wealth',
    'D9 Navamsha & Marriage Alignment',
    '24/7 Spiritual Guidance',
  ];

  /// Consultation categories – these must match the filter chips that
  /// seekers use in the Chat tab so the Pandit shows up under the right filter.
  static const Map<String, IconData> _fields = {
    'Vedic Kundli': Icons.auto_awesome_rounded,
    'Love & Relationships': Icons.favorite_rounded,
    'Career & Wealth': Icons.work_rounded,
    '24/7 Guidance': Icons.support_agent_rounded,
  };

  static const List<String> _languages = [
    'Hindi',
    'English',
    'Sanskrit',
    'Bengali',
    'Tamil',
    'Telugu',
    'Marathi',
    'Gujarati',
    'Kannada',
    'Punjabi',
  ];

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _nameController.dispose();
    _expController.dispose();
    _rateController.dispose();
    _bioController.dispose();
    super.dispose();
  }

  bool _validateStep(int step) {
    final formValid = _formKeys[step].currentState?.validate() ?? false;
    if (step == 1) {
      setState(() => _languageError = _selectedLanguages.isEmpty);
      return formValid && _selectedLanguages.isNotEmpty;
    }
    return formValid;
  }

  void _next() {
    FocusScope.of(context).unfocus();
    if (!_validateStep(_step)) return;
    if (_step < _stepTitles.length - 1) {
      setState(() {
        _step++;
        _submitError = null;
      });
    } else {
      _submitRegistration();
    }
  }

  void _back() {
    if (_step == 0) {
      Navigator.maybePop(context);
    } else {
      FocusScope.of(context).unfocus();
      setState(() => _step--);
    }
  }

  void _goToLogin() {
    if (widget.returnResultToCaller) {
      // Opened from the login screen – just go back to it.
      Navigator.pop(context, false);
    } else {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => const PanditLoginScreen()),
      );
    }
  }

  Future<void> _submitRegistration() async {
    FocusScope.of(context).unfocus();
    // Every step must be valid (earlier steps were validated on Continue, but
    // re-check in case the user navigated back and edited a field).
    for (var i = 0; i < _stepTitles.length; i++) {
      if (i == _step) continue;
      final emptyOrInvalid = switch (i) {
        0 => !_emailPattern.hasMatch(_emailController.text.trim()) || _passwordController.text.trim().length < 6,
        1 => _nameController.text.trim().length < 3 || _selectedLanguages.isEmpty,
        _ => false,
      };
      if (emptyOrInvalid) {
        setState(() => _step = i);
        WidgetsBinding.instance.addPostFrameCallback((_) => _validateStep(i));
        showAppSnack(context, 'Please fix the highlighted fields.', error: true);
        return;
      }
    }
    if (!_validateStep(_step)) {
      showAppSnack(context, 'Please fix the highlighted fields.', error: true);
      return;
    }

    setState(() {
      _isSubmitting = true;
      _submitError = null;
    });
    final backendService = Provider.of<BackendService>(context, listen: false);
    final email = _emailController.text.trim();

    // Keep languages in the canonical order shown in the UI.
    final languages = _languages.where(_selectedLanguages.contains).join(', ');

    Map<String, dynamic>? result;
    try {
      result = await backendService.registerPanditAccount(
        email: email,
        password: _passwordController.text.trim(),
        fullName: _nameController.text.trim(),
        specialty: _selectedSpecialty,
        field: _selectedField,
        experienceYears: int.parse(_expController.text.trim()),
        languages: languages,
        ratePerMin: double.parse(_rateController.text.trim()),
        bio: _bioController.text.trim(),
      );
    } catch (_) {
      result = null;
    }

    if (!mounted) return;
    setState(() => _isSubmitting = false);

    if (result != null && result['error'] == 'PANDIT_ALREADY_EXISTS') {
      showAppSnack(
        context,
        (result['message'] ?? 'This email is already registered as a Pandit. Please login.').toString(),
        error: true,
      );
      if (widget.returnResultToCaller) {
        // Return the email so the login screen can prefill it.
        Navigator.pop(context, email);
      } else {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => PanditLoginScreen(initialEmail: email)),
        );
      }
    } else if (result != null && result['error'] != null) {
      // Validation / server refusal (e.g. INVALID_EMAIL, WEAK_PASSWORD).
      final code = result['error'].toString().toUpperCase();
      setState(() {
        _submitError =
            (result!['message'] ?? backendService.lastError ?? 'Registration failed. Please review your details.')
                .toString();
        // Account problems are fixed on the first step.
        if (code.contains('EMAIL') || code.contains('PASSWORD')) _step = 0;
      });
    } else if (result != null) {
      showAppSnack(context, 'Registered as Pandit successfully! Opening your dashboard...');
      if (widget.returnResultToCaller) {
        Navigator.pop(context, true);
      } else {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => const PanditDashboardScreen()),
        );
      }
    } else {
      setState(() {
        _submitError = backendService.lastError ?? 'Registration failed. Please check your connection and try again.';
      });
    }
  }

  // ---------------------------------------------------------------------------
  // Steps
  // ---------------------------------------------------------------------------

  Widget _accountStep() {
    return Form(
      key: _formKeys[0],
      child: AutofillGroup(
        child: _Section(
          title: 'Login details',
          subtitle: 'You will use these to sign in to the partner app.',
          children: [
            TextFormField(
              controller: _emailController,
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.next,
              autofillHints: const [AutofillHints.email],
              autovalidateMode: AutovalidateMode.onUserInteraction,
              validator: (v) {
                final value = (v ?? '').trim();
                if (value.isEmpty) return 'Please enter email';
                if (!_emailPattern.hasMatch(value)) return 'Please enter a valid email';
                return null;
              },
              decoration: const InputDecoration(
                labelText: 'Email',
                hintText: 'name@example.com',
                prefixIcon: Icon(Icons.mail_outline_rounded),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            TextFormField(
              controller: _passwordController,
              obscureText: _obscurePassword,
              textInputAction: TextInputAction.done,
              autofillHints: const [AutofillHints.newPassword],
              autovalidateMode: AutovalidateMode.onUserInteraction,
              onFieldSubmitted: (_) => _next(),
              validator: (v) => (v ?? '').trim().length < 6 ? 'Password must be at least 6 characters' : null,
              decoration: InputDecoration(
                labelText: 'Create password',
                helperText: 'Minimum 6 characters',
                prefixIcon: const Icon(Icons.lock_outline_rounded),
                suffixIcon: IconButton(
                  icon: Icon(_obscurePassword ? Icons.visibility_off_outlined : Icons.visibility_outlined),
                  tooltip: _obscurePassword ? 'Show password' : 'Hide password',
                  onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _profileStep() {
    return Form(
      key: _formKeys[1],
      child: Column(
        children: [
          _Section(
            title: 'About you',
            subtitle: 'Seekers see this on your profile card.',
            children: [
              TextFormField(
                controller: _nameController,
                textCapitalization: TextCapitalization.words,
                textInputAction: TextInputAction.next,
                autovalidateMode: AutovalidateMode.onUserInteraction,
                validator: (v) => (v ?? '').trim().length < 3 ? 'Please enter your full name' : null,
                decoration: const InputDecoration(
                  labelText: 'Full name',
                  hintText: 'e.g. Pt. Rishiraj Sharma',
                  prefixIcon: Icon(Icons.person_outline_rounded),
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              DropdownButtonFormField<String>(
                initialValue: _selectedSpecialty,
                isExpanded: true,
                items: _specialties
                    .map((s) => DropdownMenuItem(
                          value: s,
                          child: Text(s, maxLines: 1, overflow: TextOverflow.ellipsis),
                        ))
                    .toList(),
                onChanged: (val) {
                  if (val != null) setState(() => _selectedSpecialty = val);
                },
                decoration: const InputDecoration(
                  labelText: 'Primary specialty',
                  prefixIcon: Icon(Icons.workspace_premium_outlined),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          _Section(
            title: 'Consultation category',
            subtitle: 'Seekers will find you under this filter in the Chat tab.',
            children: [
              Wrap(
                spacing: AppSpacing.xs,
                runSpacing: AppSpacing.xs,
                children: _fields.entries
                    .map((entry) => _ChoicePill(
                          label: entry.key,
                          icon: entry.value,
                          selected: _selectedField == entry.key,
                          onTap: () => setState(() => _selectedField = entry.key),
                        ))
                    .toList(),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          _Section(
            title: 'Languages you speak',
            subtitle: 'Select all that apply.',
            children: [
              Wrap(
                spacing: AppSpacing.xs,
                runSpacing: AppSpacing.xs,
                children: _languages.map((lang) {
                  final selected = _selectedLanguages.contains(lang);
                  return _ChoicePill(
                    label: lang,
                    selected: selected,
                    icon: selected ? Icons.check_rounded : null,
                    onTap: () => setState(() {
                      if (selected) {
                        _selectedLanguages.remove(lang);
                      } else {
                        _selectedLanguages.add(lang);
                      }
                      _languageError = _selectedLanguages.isEmpty;
                    }),
                  );
                }).toList(),
              ),
              if (_languageError)
                Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.xs, left: 4),
                  child: Text('Select at least one language', style: AppText.caption.copyWith(color: AppColors.danger)),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _practiceStep() {
    return Form(
      key: _formKeys[2],
      child: Column(
        children: [
          _Section(
            title: 'Experience & pricing',
            subtitle: 'Your per-minute rate is charged to seekers during live chat.',
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _expController,
                      keyboardType: TextInputType.number,
                      textInputAction: TextInputAction.next,
                      autovalidateMode: AutovalidateMode.onUserInteraction,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(2)],
                      validator: (v) {
                        final n = int.tryParse((v ?? '').trim());
                        if (n == null) return 'Required';
                        if (n < 0 || n > 70) return '0 - 70';
                        return null;
                      },
                      decoration:
                          const InputDecoration(labelText: 'Experience', hintText: 'e.g. 15', suffixText: 'yrs'),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: TextFormField(
                      controller: _rateController,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      textInputAction: TextInputAction.next,
                      autovalidateMode: AutovalidateMode.onUserInteraction,
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(RegExp(r'^\d{0,4}(\.\d{0,2})?')),
                      ],
                      validator: (v) {
                        final n = double.tryParse((v ?? '').trim());
                        if (n == null) return 'Required';
                        if (n < 1 || n > 1000) return '₹1 - ₹1000';
                        return null;
                      },
                      decoration: const InputDecoration(
                          labelText: 'Rate', hintText: 'e.g. 21', prefixText: '₹ ', suffixText: '/min'),
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          _Section(
            title: 'Bio & background',
            subtitle: 'Describe your experience, remedies and Kundli expertise.',
            children: [
              TextFormField(
                controller: _bioController,
                maxLines: 5,
                maxLength: 500,
                textCapitalization: TextCapitalization.sentences,
                autovalidateMode: AutovalidateMode.onUserInteraction,
                validator: (v) => (v ?? '').trim().length < 20 ? 'Please write at least 20 characters' : null,
                decoration: const InputDecoration(
                  hintText: 'e.g. 15 years of Vedic practice, specialising in marriage and career charts...',
                  alignLabelWithHint: true,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isLast = _step == _stepTitles.length - 1;
    final steps = [_accountStep, _profileStep, _practiceStep];

    return PopScope(
      canPop: _step == 0 && !_isSubmitting,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && !_isSubmitting && _step > 0) setState(() => _step--);
      },
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_rounded),
            tooltip: _step == 0 ? 'Back' : 'Previous step',
            onPressed: _isSubmitting ? null : _back,
          ),
          title: const Text('Become a partner', overflow: TextOverflow.ellipsis),
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(56),
            child: _StepIndicator(titles: _stepTitles, current: _step),
          ),
        ),
        body: SafeArea(
          child: Column(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  key: ValueKey(_step),
                  padding: const EdgeInsets.fromLTRB(AppSpacing.page, AppSpacing.md, AppSpacing.page, AppSpacing.xl),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (_step == 0) ...[
                        const _IntroCard(),
                        const SizedBox(height: AppSpacing.md),
                      ],
                      if (_submitError != null) ...[
                        _ErrorBanner(message: _submitError!),
                        const SizedBox(height: AppSpacing.md),
                      ],
                      steps[_step](),
                      if (_step == 0) ...[
                        const SizedBox(height: AppSpacing.sm),
                        Center(
                          child: TextButton(
                            onPressed: _isSubmitting ? null : _goToLogin,
                            style: TextButton.styleFrom(minimumSize: const Size(44, 44)),
                            child: const Text('Already a partner? Log in'),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.fromLTRB(AppSpacing.page, AppSpacing.sm, AppSpacing.page, AppSpacing.sm),
                decoration: const BoxDecoration(
                  color: AppColors.surface,
                  border: Border(top: BorderSide(color: AppColors.border)),
                ),
                child: Row(
                  children: [
                    if (_step > 0) ...[
                      Expanded(
                        flex: 2,
                        child: AppButton(
                          label: 'Back',
                          variant: AppButtonVariant.outline,
                          onPressed: _isSubmitting ? null : _back,
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                    ],
                    Expanded(
                      flex: 3,
                      child: AppButton(
                        label: isLast ? 'Create account' : 'Continue',
                        icon: isLast ? Icons.check_rounded : null,
                        loading: _isSubmitting,
                        onPressed: _isSubmitting ? null : _next,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StepIndicator extends StatelessWidget {
  final List<String> titles;
  final int current;
  const _StepIndicator({required this.titles, required this.current});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Step ${current + 1} of ${titles.length}: ${titles[current]}',
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(AppSpacing.page, 0, AppSpacing.page, AppSpacing.sm),
        child: Row(
          children: [
            for (var i = 0; i < titles.length; i++) ...[
              if (i > 0) const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      height: 4,
                      decoration: BoxDecoration(
                        color: i <= current ? AppColors.primary : AppColors.border,
                        borderRadius: BorderRadius.circular(AppRadius.pill),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '${i + 1}. ${titles[i]}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.caption.copyWith(
                        color: i == current ? AppColors.textPrimary : AppColors.textTertiary,
                        fontWeight: i == current ? FontWeight.w700 : FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _IntroCard extends StatelessWidget {
  const _IntroCard();

  @override
  Widget build(BuildContext context) {
    return AppCard(
      gradient: AppColors.cosmicGradient,
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(AppRadius.md),
            ),
            child: const Icon(Icons.auto_awesome_rounded, color: AppColors.gold),
          ),
          const SizedBox(width: AppSpacing.sm),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('CosmicGuide Partner Program',
                    style: TextStyle(color: AppColors.textOnDark, fontSize: 15, fontWeight: FontWeight.w700)),
                SizedBox(height: 2),
                Text('Consult seekers live and view their Kundli charts. Takes about 2 minutes.',
                    style: TextStyle(color: AppColors.textOnDarkMuted, fontSize: 12, height: 1.35)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  final String title;
  final String? subtitle;
  final List<Widget> children;
  const _Section({required this.title, this.subtitle, required this.children});

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title, style: AppText.subtitle),
          if (subtitle != null) ...[
            const SizedBox(height: 2),
            Text(subtitle!, style: AppText.caption.copyWith(color: AppColors.textSecondary)),
          ],
          const SizedBox(height: AppSpacing.md),
          ...children,
        ],
      ),
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
        decoration: BoxDecoration(color: AppColors.dangerSoft, borderRadius: BorderRadius.circular(AppRadius.md)),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.error_outline_rounded, color: AppColors.danger, size: 18),
            const SizedBox(width: AppSpacing.xs),
            Expanded(child: Text(message, style: AppText.caption.copyWith(color: AppColors.danger, height: 1.4))),
          ],
        ),
      ),
    );
  }
}

/// Selectable pill (same look as `AppFilterChip`) whose label can shrink with
/// an ellipsis, so long categories never overflow at large text sizes.
class _ChoicePill extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final IconData? icon;

  const _ChoicePill({required this.label, required this.selected, required this.onTap, this.icon});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.pill),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          constraints: const BoxConstraints(minHeight: 44),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: selected ? AppColors.primarySoft : AppColors.surface,
            borderRadius: BorderRadius.circular(AppRadius.pill),
            border: Border.all(color: selected ? AppColors.primary : AppColors.border, width: selected ? 1.4 : 1),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            if (icon != null) ...[
              Icon(icon, size: 16, color: selected ? AppColors.primary : AppColors.textSecondary),
              const SizedBox(width: 6),
            ],
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                  color: selected ? AppColors.primaryDark : AppColors.textPrimary,
                ),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}
