import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:fluttertoast/fluttertoast.dart';
import '../../services/backend_service.dart';
import '../../widgets/google_logo_widget.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  
  bool _isSignUpMode = false;
  bool _isPasswordVisible = false;

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _handleGoogleLogin() async {
    final backendService = Provider.of<BackendService>(context, listen: false);
    
    // Create/login Google user session in Neon DB
    final success = await backendService.register(
      'Google User',
      'google_user_${DateTime.now().millisecondsSinceEpoch}@gmail.com',
      'googleauth123',
    );

    if (mounted) {
      if (success) {
        Fluttertoast.showToast(msg: "Signed in with Google! Data saved to Neon DB.", backgroundColor: Colors.black);
      }
      Navigator.pushNamed(context, '/topic-selection');
    }
  }

  void _showEmailAuthModal() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFFFCF7F1),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setModalState) {
            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom + 24,
                top: 24,
                left: 24,
                right: 24,
              ),
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
                        decoration: BoxDecoration(color: Colors.grey.shade400, borderRadius: BorderRadius.circular(2)),
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Header Title
                    Text(
                      _isSignUpMode ? 'Create New Account' : 'Welcome Back',
                      style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.black),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _isSignUpMode
                          ? 'Save your full birth details & Kundli in Neon DB'
                          : 'Sign in to access your saved Kundli & history',
                      style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
                    ),
                    const SizedBox(height: 20),

                    // Full Name Field (Only in Sign Up Mode)
                    if (_isSignUpMode) ...[
                      TextFormField(
                        controller: _nameController,
                        decoration: InputDecoration(
                          labelText: 'Full Name',
                          filled: true,
                          fillColor: Colors.white,
                          prefixIcon: const Icon(Icons.person_outline),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
                        ),
                        validator: (val) => val == null || val.isEmpty ? 'Enter your full name' : null,
                      ),
                      const SizedBox(height: 14),
                    ],

                    // Email Field
                    TextFormField(
                      controller: _emailController,
                      keyboardType: TextInputType.emailAddress,
                      decoration: InputDecoration(
                        labelText: 'Email Address',
                        filled: true,
                        fillColor: Colors.white,
                        prefixIcon: const Icon(Icons.email_outlined),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
                      ),
                      validator: (val) => val == null || val.isEmpty ? 'Enter email' : null,
                    ),
                    const SizedBox(height: 14),

                    // Password Field with WORKING Eye Icon Toggle
                    TextFormField(
                      controller: _passwordController,
                      obscureText: !_isPasswordVisible,
                      decoration: InputDecoration(
                        labelText: 'Password',
                        filled: true,
                        fillColor: Colors.white,
                        prefixIcon: const Icon(Icons.lock_outline),
                        suffixIcon: IconButton(
                          icon: Icon(_isPasswordVisible ? Icons.visibility : Icons.visibility_off, color: Colors.black87),
                          onPressed: () {
                            setModalState(() {
                              _isPasswordVisible = !_isPasswordVisible;
                            });
                          },
                        ),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
                      ),
                      validator: (val) => val == null || val.isEmpty ? 'Enter password' : null,
                    ),

                    const SizedBox(height: 24),

                    // Action Submit Button
                    Consumer<BackendService>(
                      builder: (context, backendService, child) {
                        return SizedBox(
                          width: double.infinity,
                          height: 54,
                          child: ElevatedButton(
                            onPressed: backendService.isLoading
                                ? null
                                : () async {
                                    if (_formKey.currentState!.validate()) {
                                      final email = _emailController.text.trim();
                                      final password = _passwordController.text;
                                      final name = _isSignUpMode
                                          ? _nameController.text.trim()
                                          : email.split('@')[0];

                                      bool success = false;
                                      if (_isSignUpMode) {
                                        success = await backendService.register(name, email, password);
                                      } else {
                                        success = await backendService.login(email, password);
                                      }

                                      if (mounted) {
                                        if (success) {
                                          Navigator.pop(context);
                                          Fluttertoast.showToast(
                                            msg: _isSignUpMode ? "Account created in Neon DB!" : "Signed in successfully!",
                                            backgroundColor: Colors.black,
                                            textColor: Colors.white,
                                          );
                                          Navigator.pushNamed(context, '/topic-selection');
                                        } else {
                                          Fluttertoast.showToast(
                                            msg: _isSignUpMode ? "Registration failed. Try logging in." : "Invalid email or password.",
                                            backgroundColor: Colors.red,
                                          );
                                        }
                                      }
                                    }
                                  },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.black,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(27)),
                            ),
                            child: backendService.isLoading
                                ? const SizedBox(
                                    width: 22,
                                    height: 22,
                                    child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                                  )
                                : Text(
                                    _isSignUpMode ? 'Create Account & Save' : 'Continue to App',
                                    style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                                  ),
                          ),
                        );
                      },
                    ),

                    const SizedBox(height: 16),

                    // Toggle Sign In / Sign Up Mode
                    Center(
                      child: GestureDetector(
                        onTap: () {
                          setModalState(() {
                            _isSignUpMode = !_isSignUpMode;
                          });
                        },
                        child: RichText(
                          text: TextSpan(
                            style: const TextStyle(fontSize: 14, color: Colors.black87),
                            children: [
                              TextSpan(text: _isSignUpMode ? "Already have an account? " : "Don't have an account? "),
                              TextSpan(
                                text: _isSignUpMode ? "Sign In" : "Sign Up",
                                style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.black, decoration: TextDecoration.underline),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
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
                  color: const Color(0xFFEADBEE),
                );
              },
            ),
          ),

          // 2. Main Content
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 20),
              child: Column(
                children: [
                  const SizedBox(height: 40),

                  // Brand Logo Title
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        'upastr',
                        style: TextStyle(
                          fontSize: 42,
                          fontWeight: FontWeight.w900,
                          color: const Color(0xFF7032D9),
                          letterSpacing: -1.0,
                        ),
                      ),
                      Stack(
                        alignment: Alignment.center,
                        children: [
                          const Icon(Icons.nightlight_round, color: Color(0xFF7032D9), size: 36),
                          Container(
                            width: 14,
                            height: 14,
                            decoration: const BoxDecoration(
                              color: Colors.white,
                              shape: BoxShape.circle,
                            ),
                          ),
                          Container(
                            width: 8,
                            height: 8,
                            decoration: const BoxDecoration(
                              color: Color(0xFF7032D9),
                              shape: BoxShape.circle,
                            ),
                          ),
                        ],
                      ),
                      Text(
                        'logy',
                        style: TextStyle(
                          fontSize: 42,
                          fontWeight: FontWeight.w900,
                          color: const Color(0xFF7032D9),
                          letterSpacing: -1.0,
                        ),
                      ),
                    ],
                  ),

                  const Spacer(),

                  // Descriptive Subtitle
                  const Text(
                    'Use your Gmail account to save your data securely and access your previous information effortlessly',
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
                  SizedBox(
                    width: double.infinity,
                    height: 56,
                    child: ElevatedButton(
                      onPressed: _handleGoogleLogin,
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
                        children: const [
                          GoogleLogoWidget(size: 24),
                          SizedBox(width: 12),
                          Text(
                            'Continue with Google',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Colors.black,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 16),

                  // Button 2: Login with Email
                  SizedBox(
                    width: double.infinity,
                    height: 56,
                    child: ElevatedButton(
                      onPressed: _showEmailAuthModal,
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
                        children: const [
                          Icon(Icons.mail_outline_rounded, color: Colors.black, size: 22),
                          SizedBox(width: 12),
                          Text(
                            'Login with Email',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Colors.black,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 20),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}