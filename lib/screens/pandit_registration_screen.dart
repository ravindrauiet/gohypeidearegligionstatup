import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/backend_service.dart';
import 'pandit_dashboard_screen.dart';
import 'pandit_login_screen.dart';

class PanditRegistrationScreen extends StatefulWidget {
  const PanditRegistrationScreen({super.key});

  @override
  State<PanditRegistrationScreen> createState() => _PanditRegistrationScreenState();
}

class _PanditRegistrationScreenState extends State<PanditRegistrationScreen> {
  final _formKey = GlobalKey<FormState>();

  final TextEditingController _emailController = TextEditingController(text: 'rishiraj@astroai.com');
  final TextEditingController _passwordController = TextEditingController(text: 'pandit123');
  final TextEditingController _nameController = TextEditingController(text: 'Pt. Rishiraj Sharma');
  final TextEditingController _expController = TextEditingController(text: '15');
  final TextEditingController _langController = TextEditingController(text: 'Hindi, English, Sanskrit');
  final TextEditingController _rateController = TextEditingController(text: '21');
  final TextEditingController _bioController = TextEditingController(
    text: 'Gold medalist Vedic astrologer with 15+ years of experience in Janam Kundli, Guna Milan, and planetary remedies.',
  );

  String _selectedSpecialty = 'Vedic Kundli & Guna Milan';
  String _selectedField = 'Vedic Kundli';
  bool _isSubmitting = false;

  final List<String> _specialties = [
    'Vedic Kundli & Guna Milan',
    'Love & Relationship Synastry',
    'Career, Business & Financial Wealth',
    'D9 Navamsha & Marriage Alignment',
    '24/7 Spiritual Guidance'
  ];

  final List<String> _fields = [
    'Vedic Kundli',
    'Love & Relationships',
    'Career & Wealth',
    '24/7 Guidance'
  ];

  Future<void> _submitRegistration() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSubmitting = true);
    final backendService = Provider.of<BackendService>(context, listen: false);

    final result = await backendService.registerPanditAccount(
      email: _emailController.text.trim(),
      password: _passwordController.text.trim(),
      fullName: _nameController.text.trim(),
      specialty: _selectedSpecialty,
      field: _selectedField,
      experienceYears: int.tryParse(_expController.text.trim()) ?? 15,
      languages: _langController.text.trim(),
      ratePerMin: double.tryParse(_rateController.text.trim()) ?? 21.0,
      bio: _bioController.text.trim(),
    );

    if (mounted) {
      setState(() => _isSubmitting = false);
      if (result != null && result['error'] == 'PANDIT_ALREADY_EXISTS') {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result['message'] ?? 'Account already registered as Pandit! Redirecting to Pandit Login...'),
            backgroundColor: const Color(0xFFD95D39),
          ),
        );
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => const PanditLoginScreen()),
        );
      } else if (result != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Registered as Pandit successfully! Opening Pandit Dashboard...')),
        );
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => const PanditDashboardScreen()),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Registration completed. Opening Pandit Dashboard...')),
        );
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => const PanditDashboardScreen()),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFCF7F1),
      appBar: AppBar(
        backgroundColor: const Color(0xFFFCF7F1),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.black),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Register as Pandit / Astrologer',
          style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 18),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header Card
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
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
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: const [
                          Text('Pandit Marketplace Partner', style: TextStyle(color: Color(0xFFFFD700), fontSize: 12, fontWeight: FontWeight.bold)),
                          SizedBox(height: 2),
                          Text('Join 5,000+ Expert Astrologers', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                          SizedBox(height: 2),
                          Text('Consult with seekers live & inspect authentic Kundli charts', style: TextStyle(color: Colors.white70, fontSize: 11)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              const Text('Pandit Account Email', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
              const SizedBox(height: 6),
              TextFormField(
                controller: _emailController,
                keyboardType: TextInputType.emailAddress,
                validator: (v) => v == null || v.isEmpty ? 'Please enter email' : null,
                decoration: InputDecoration(
                  hintText: 'e.g. rishiraj@astroai.com',
                  filled: true,
                  fillColor: Colors.white,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
                ),
              ),

              const SizedBox(height: 16),

              const Text('Create Pandit Password', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
              const SizedBox(height: 6),
              TextFormField(
                controller: _passwordController,
                obscureText: true,
                validator: (v) => v == null || v.length < 6 ? 'Password must be at least 6 characters' : null,
                decoration: InputDecoration(
                  hintText: 'Minimum 6 characters',
                  filled: true,
                  fillColor: Colors.white,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
                ),
              ),

              const SizedBox(height: 16),

              const Text('Full Name', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
              const SizedBox(height: 6),
              TextFormField(
                controller: _nameController,
                validator: (v) => v == null || v.isEmpty ? 'Please enter name' : null,
                decoration: InputDecoration(
                  hintText: 'e.g. Pt. Rishiraj Sharma',
                  filled: true,
                  fillColor: Colors.white,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
                ),
              ),

              const SizedBox(height: 16),

              const Text('Primary Specialty', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
              const SizedBox(height: 6),
              DropdownButtonFormField<String>(
                value: _selectedSpecialty,
                items: _specialties.map((s) => DropdownMenuItem(value: s, child: Text(s, style: const TextStyle(fontSize: 13)))).toList(),
                onChanged: (val) => setState(() => _selectedSpecialty = val!),
                decoration: InputDecoration(
                  filled: true,
                  fillColor: Colors.white,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
                ),
              ),

              const SizedBox(height: 16),

              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Experience (Years)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                        const SizedBox(height: 6),
                        TextFormField(
                          controller: _expController,
                          keyboardType: TextInputType.number,
                          decoration: InputDecoration(
                            hintText: '15',
                            filled: true,
                            fillColor: Colors.white,
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Rate (₹/Min)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                        const SizedBox(height: 6),
                        TextFormField(
                          controller: _rateController,
                          keyboardType: TextInputType.number,
                          decoration: InputDecoration(
                            hintText: '21',
                            filled: true,
                            fillColor: Colors.white,
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 16),

              const Text('Languages Spoken', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
              const SizedBox(height: 6),
              TextFormField(
                controller: _langController,
                decoration: InputDecoration(
                  hintText: 'Hindi, English, Sanskrit',
                  filled: true,
                  fillColor: Colors.white,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
                ),
              ),

              const SizedBox(height: 16),

              const Text('Astrological Bio & Background', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
              const SizedBox(height: 6),
              TextFormField(
                controller: _bioController,
                maxLines: 3,
                decoration: InputDecoration(
                  hintText: 'Describe your experience, remedies, and Kundli expertise...',
                  filled: true,
                  fillColor: Colors.white,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
                ),
              ),

              const SizedBox(height: 28),

              SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  onPressed: _isSubmitting ? null : _submitRegistration,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.black,
                    elevation: 2,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                  ),
                  child: _isSubmitting
                      ? const CircularProgressIndicator(color: Colors.white, strokeWidth: 2)
                      : const Text(
                          'Complete Pandit Onboarding',
                          style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
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
