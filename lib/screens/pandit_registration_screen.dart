import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../services/backend_service.dart';
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
  final _formKey = GlobalKey<FormState>();

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

  Future<void> _submitRegistration() async {
    FocusScope.of(context).unfocus();
    final formValid = _formKey.currentState?.validate() ?? false;
    setState(() => _languageError = _selectedLanguages.isEmpty);
    if (!formValid || _selectedLanguages.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please fix the highlighted fields.')),
      );
      return;
    }

    setState(() => _isSubmitting = true);
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text((result['message'] ?? 'This email is already registered as a Pandit. Please login.').toString()),
          backgroundColor: const Color(0xFFD95D39),
        ),
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text((result['message'] ?? backendService.lastError ?? 'Registration failed. Please review your details.').toString()),
          backgroundColor: Colors.red,
        ),
      );
    } else if (result != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Registered as Pandit successfully! Opening your dashboard...'),
          backgroundColor: Color(0xFF059669),
        ),
      );
      if (widget.returnResultToCaller) {
        Navigator.pop(context, true);
      } else {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => const PanditDashboardScreen()),
        );
      }
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(backendService.lastError ?? 'Registration failed. Please check your connection and try again.'),
          backgroundColor: Colors.red,
          action: SnackBarAction(label: 'Retry', textColor: Colors.white, onPressed: _submitRegistration),
        ),
      );
    }
  }

  InputDecoration _decoration({String? hint, Widget? suffix}) {
    return InputDecoration(
      hintText: hint,
      suffixIcon: suffix,
      filled: true,
      fillColor: Colors.white,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
    );
  }

  Widget _label(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(text, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFCF7F1),
      appBar: AppBar(
        backgroundColor: const Color(0xFFFCF7F1),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.black),
          tooltip: 'Back',
          onPressed: () => Navigator.maybePop(context),
        ),
        title: const Text(
          'Register as Pandit',
          overflow: TextOverflow.ellipsis,
          style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 18),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header Card
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF1E1A38), Color(0xFF2E2452)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: const BoxDecoration(color: Color(0xFFFFD700), shape: BoxShape.circle),
                        child: const Icon(Icons.star_rounded, color: Colors.black, size: 28),
                      ),
                      const SizedBox(width: 14),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('CosmicGuide Partner Program',
                                style: TextStyle(color: Color(0xFFFFD700), fontSize: 12, fontWeight: FontWeight.bold)),
                            SizedBox(height: 2),
                            Text('Join our Expert Astrologers',
                                style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                            SizedBox(height: 2),
                            Text('Consult with seekers live & inspect authentic Kundli charts',
                                style: TextStyle(color: Colors.white70, fontSize: 11)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 24),

                _label('Pandit Account Email'),
                TextFormField(
                  controller: _emailController,
                  keyboardType: TextInputType.emailAddress,
                  textInputAction: TextInputAction.next,
                  autofillHints: const [AutofillHints.email],
                  validator: (v) {
                    final value = (v ?? '').trim();
                    if (value.isEmpty) return 'Please enter email';
                    if (!_emailPattern.hasMatch(value)) return 'Please enter a valid email';
                    return null;
                  },
                  decoration: _decoration(hint: 'e.g. name@example.com'),
                ),

                const SizedBox(height: 16),

                _label('Create Pandit Password'),
                TextFormField(
                  controller: _passwordController,
                  obscureText: _obscurePassword,
                  textInputAction: TextInputAction.next,
                  autofillHints: const [AutofillHints.newPassword],
                  validator: (v) => (v ?? '').trim().length < 6 ? 'Password must be at least 6 characters' : null,
                  decoration: _decoration(
                    hint: 'Minimum 6 characters',
                    suffix: IconButton(
                      icon: Icon(_obscurePassword ? Icons.visibility_off : Icons.visibility),
                      tooltip: _obscurePassword ? 'Show password' : 'Hide password',
                      onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                    ),
                  ),
                ),

                const SizedBox(height: 16),

                _label('Full Name'),
                TextFormField(
                  controller: _nameController,
                  textCapitalization: TextCapitalization.words,
                  textInputAction: TextInputAction.next,
                  validator: (v) => (v ?? '').trim().length < 3 ? 'Please enter your full name' : null,
                  decoration: _decoration(hint: 'e.g. Pt. Rishiraj Sharma'),
                ),

                const SizedBox(height: 16),

                _label('Primary Specialty'),
                DropdownButtonFormField<String>(
                  initialValue: _selectedSpecialty,
                  isExpanded: true,
                  items: _specialties
                      .map((s) => DropdownMenuItem(
                            value: s,
                            child: Text(s, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13)),
                          ))
                      .toList(),
                  onChanged: (val) {
                    if (val != null) setState(() => _selectedSpecialty = val);
                  },
                  decoration: _decoration(),
                ),

                const SizedBox(height: 16),

                _label('Consultation Category'),
                const Text(
                  'Seekers will find you under this filter in the Chat tab.',
                  style: TextStyle(fontSize: 11, color: Colors.grey),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: _fields.entries.map((entry) {
                    final selected = _selectedField == entry.key;
                    return ChoiceChip(
                      avatar: Icon(entry.value, size: 16, color: selected ? Colors.white : const Color(0xFFE83D66)),
                      label: Text(entry.key),
                      selected: selected,
                      showCheckmark: false,
                      selectedColor: const Color(0xFFE83D66),
                      backgroundColor: Colors.white,
                      labelStyle: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: selected ? Colors.white : Colors.black87,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: BorderSide(color: selected ? const Color(0xFFE83D66) : Colors.grey.shade300),
                      ),
                      onSelected: (_) => setState(() => _selectedField = entry.key),
                    );
                  }).toList(),
                ),

                const SizedBox(height: 16),

                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _label('Experience (Yrs)'),
                          TextFormField(
                            controller: _expController,
                            keyboardType: TextInputType.number,
                            textInputAction: TextInputAction.next,
                            inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(2)],
                            validator: (v) {
                              final n = int.tryParse((v ?? '').trim());
                              if (n == null) return 'Required';
                              if (n < 0 || n > 70) return '0 - 70';
                              return null;
                            },
                            decoration: _decoration(hint: 'e.g. 15'),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _label('Rate (₹/Min)'),
                          TextFormField(
                            controller: _rateController,
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            textInputAction: TextInputAction.next,
                            inputFormatters: [
                              FilteringTextInputFormatter.allow(RegExp(r'^\d{0,4}(\.\d{0,2})?')),
                            ],
                            validator: (v) {
                              final n = double.tryParse((v ?? '').trim());
                              if (n == null) return 'Required';
                              if (n < 1 || n > 1000) return '₹1 - ₹1000';
                              return null;
                            },
                            decoration: _decoration(hint: 'e.g. 21'),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 16),

                _label('Languages Spoken'),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: _languages.map((lang) {
                    final selected = _selectedLanguages.contains(lang);
                    return FilterChip(
                      label: Text(lang),
                      selected: selected,
                      selectedColor: const Color(0xFF1E1A38),
                      checkmarkColor: const Color(0xFFFFD700),
                      backgroundColor: Colors.white,
                      labelStyle: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: selected ? Colors.white : Colors.black87,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: BorderSide(color: selected ? const Color(0xFF1E1A38) : Colors.grey.shade300),
                      ),
                      onSelected: (val) {
                        setState(() {
                          if (val) {
                            _selectedLanguages.add(lang);
                          } else {
                            _selectedLanguages.remove(lang);
                          }
                          _languageError = _selectedLanguages.isEmpty;
                        });
                      },
                    );
                  }).toList(),
                ),
                if (_languageError)
                  const Padding(
                    padding: EdgeInsets.only(top: 6, left: 4),
                    child: Text('Select at least one language', style: TextStyle(color: Colors.red, fontSize: 12)),
                  ),

                const SizedBox(height: 16),

                _label('Astrological Bio & Background'),
                TextFormField(
                  controller: _bioController,
                  maxLines: 4,
                  maxLength: 500,
                  textCapitalization: TextCapitalization.sentences,
                  validator: (v) => (v ?? '').trim().length < 20 ? 'Please write at least 20 characters' : null,
                  decoration: _decoration(hint: 'Describe your experience, remedies, and Kundli expertise...'),
                ),

                const SizedBox(height: 20),

                SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: ElevatedButton(
                    onPressed: _isSubmitting ? null : _submitRegistration,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.black,
                      disabledBackgroundColor: Colors.black54,
                      elevation: 2,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                    ),
                    child: _isSubmitting
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                          )
                        : const Text(
                            'Complete Pandit Onboarding',
                            style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                          ),
                  ),
                ),
                const SizedBox(height: 8),
                Center(
                  child: TextButton(
                    onPressed: _isSubmitting
                        ? null
                        : () {
                            if (widget.returnResultToCaller) {
                              // Opened from the login screen – just go back to it.
                              Navigator.pop(context, false);
                            } else {
                              Navigator.pushReplacement(
                                context,
                                MaterialPageRoute(builder: (context) => const PanditLoginScreen()),
                              );
                            }
                          },
                    child: const Text(
                      'Already a Pandit partner? Login',
                      style: TextStyle(color: Color(0xFF9C27B0), fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
