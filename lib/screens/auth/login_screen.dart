import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:fluttertoast/fluttertoast.dart';
import '../../services/backend_service.dart';
import '../../utils/app_routes.dart';
import '../../utils/validators.dart';
import '../../widgets/cosmic_background.dart';
import '../../widgets/google_logo_widget.dart';

/// Warm accent of the sign-in sky (the same as the first onboarding slide).
const Color _accent = Color(0xFFFFA45C);

Color _white(double alpha) => Colors.white.withValues(alpha: alpha);

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
      backgroundColor: cosmicSheet,
      barrierColor: const Color(0xB3050314),
      shape: RoundedRectangleBorder(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        side: BorderSide(color: _white(0.16)),
      ),
      clipBehavior: Clip.antiAlias,
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

  Widget _legalLink(String label, String route) {
    return InkWell(
      onTap: () => Navigator.pushNamed(context, route),
      borderRadius: BorderRadius.circular(6),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
        child: Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: cosmicGoldLight,
            decoration: TextDecoration.underline,
            decorationColor: cosmicGoldLight,
          ),
        ),
      ),
    );
  }

  /// The frosted panel holding every way to continue.
  Widget _actions({required bool helper}) {
    final radius = BorderRadius.circular(30);
    final legal = TextStyle(fontSize: 12, color: _white(0.74), height: 1.3);
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: radius,
        boxShadow: const [BoxShadow(color: Color(0x80050314), blurRadius: 30, offset: Offset(0, 14))],
      ),
      child: ClipRRect(
        borderRadius: radius,
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 16, sigmaY: 16),
          child: Container(
            padding: const EdgeInsets.fromLTRB(18, 20, 18, 12),
            decoration: BoxDecoration(
              borderRadius: radius,
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [_white(0.14), _white(0.06)],
              ),
              border: Border.all(color: _white(0.20)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (helper) ...[
                  Text(
                    'Sign in to save your Kundli securely and pick up right where you left off on any device.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 13.5, color: _white(0.8), height: 1.45),
                  ),
                  const SizedBox(height: 16),
                ],
                CosmicPrimaryButton(
                  label: 'Continue with Email',
                  onPressed: () => _showEmailAuthModal(),
                  icon: null,
                  leading: const Icon(Icons.mail_rounded, color: Color(0xFF2B1403), size: 22),
                ),
                const SizedBox(height: 12),
                CosmicGlassButton(
                  label: 'Continue with Google',
                  onPressed: _handleGoogleLogin,
                  leading: Container(
                    width: 28,
                    height: 28,
                    alignment: Alignment.center,
                    decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                    child: const GoogleLogoWidget(size: 18),
                  ),
                ),
                const SizedBox(height: 4),
                TextButton(
                  onPressed: () => _showEmailAuthModal(signUp: true),
                  style: TextButton.styleFrom(foregroundColor: Colors.white, minimumSize: const Size(48, 44)),
                  child: Text.rich(
                    TextSpan(
                      text: 'New here? ',
                      style: TextStyle(color: _white(0.8)),
                      children: const [
                        TextSpan(
                          text: 'Create an account',
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
                    style: const TextStyle(fontSize: 14.5),
                  ),
                ),
                Wrap(
                  alignment: WrapAlignment.center,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text('By continuing you agree to our', style: legal),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const SizedBox(width: 2),
                        _legalLink('Terms', AppRoutes.terms),
                        Text('&', style: legal),
                        _legalLink('Privacy Policy', AppRoutes.privacy),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light.copyWith(
        statusBarColor: Colors.transparent,
        systemNavigationBarColor: cosmicNight,
        systemNavigationBarIconBrightness: Brightness.light,
      ),
      child: Scaffold(
        backgroundColor: cosmicNight,
        body: Stack(
          fit: StackFit.expand,
          children: [
            // 1. The same night sky as onboarding (drawn, no wallpaper image).
            const ExcludeSemantics(child: CosmicBackground(accent: _accent, epoch: 0)),

            // 2. Main content (scrollable so short screens, large text and
            //    landscape never overflow).
            SafeArea(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final h = constraints.maxHeight;
                  // What is left after the wordmark, promise and actions goes to
                  // the hero; on short screens the extras step aside first so the
                  // buttons stay in view.
                  final scale = MediaQuery.textScalerOf(context).scale(100) / 100;
                  final spare = h - 432 * (1 + (scale - 1) * 0.45);
                  final showChips = spare >= 250;
                  final showHelper = spare >= 190;
                  final left = spare - (showChips ? 50 : 0) - (showHelper ? 56 : 0);
                  final heroH = left < 110 ? 0.0 : left.clamp(110.0, 300.0);
                  return SingleChildScrollView(
                    child: ConstrainedBox(
                      constraints: BoxConstraints(minHeight: h),
                      child: Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 480),
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const _BrandTitle(),
                                if (heroH > 0) ...[
                                  const SizedBox(height: 6),
                                  SizedBox(height: heroH, width: double.infinity, child: const _LoginHero()),
                                ],
                                const SizedBox(height: 10),
                                const Padding(
                                  padding: EdgeInsets.symmetric(horizontal: 8),
                                  child: CosmicGoldText(
                                    before: 'Your true ',
                                    gold: 'Vedic Kundli',
                                    fontSize: 28,
                                    textAlign: TextAlign.center,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  'Your day, your planets, your people.',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(fontSize: 15.5, color: _white(0.82), height: 1.4),
                                ),
                                if (showChips) ...[
                                  const SizedBox(height: 14),
                                  // Decorative labels: always one row, scaled to fit.
                                  MediaQuery.withClampedTextScaling(
                                    maxScaleFactor: 1.1,
                                    child: const FittedBox(
                                      fit: BoxFit.scaleDown,
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          _FeatureChip(Icons.auto_awesome, 'Accurate Kundli'),
                                          SizedBox(width: 7),
                                          _FeatureChip(Icons.wb_sunny_rounded, 'Daily guidance'),
                                          SizedBox(width: 7),
                                          _FeatureChip(Icons.casino_rounded, 'Cosmic games'),
                                        ],
                                      ),
                                    ),
                                  ),
                                ],
                                const SizedBox(height: 18),
                                _actions(helper: showHelper),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Brand mark and wordmark.
class _BrandTitle extends StatelessWidget {
  const _BrandTitle();

  @override
  Widget build(BuildContext context) {
    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: 1.15,
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Semantics(
          header: true,
          label: 'CosmicGuide',
          child: ExcludeSemantics(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const CosmicMark(size: 30),
                const SizedBox(width: 10),
                const Text(
                  'Cosmic',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: Colors.white, letterSpacing: 0.2),
                ),
                ShaderMask(
                  blendMode: BlendMode.srcIn,
                  shaderCallback: (rect) => cosmicGoldGradient.createShader(rect),
                  child: const Text(
                    'Guide',
                    style:
                        TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: Colors.white, letterSpacing: 0.2),
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

class _FeatureChip extends StatelessWidget {
  final IconData icon;
  final String label;
  const _FeatureChip(this.icon, this.label);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: _white(0.10),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _white(0.22)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: cosmicGoldLight),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              label,
              style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }
}

// ----------------------------------------------------------------------------
// Hero
// ----------------------------------------------------------------------------

/// The brand moment: a softly glowing ringed planet inside a slowly turning
/// zodiac ring, with three small planets in orbit. It moves for a short while
/// and then comes to rest; with reduced motion it is shown at rest at once.
class _LoginHero extends StatefulWidget {
  const _LoginHero();

  @override
  State<_LoginHero> createState() => _LoginHeroState();
}

class _LoginHeroState extends State<_LoginHero> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: cosmicIdleDuration);
  bool? _reduce;

  static const double _w = 320;
  static const double _h = 250;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (reduce == _reduce) return;
    _reduce = reduce;
    if (reduce) {
      _c.stop();
      _c.value = 1;
    } else {
      _c.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  Widget _orb(Offset at, double size, Color color) {
    return Positioned(
      left: at.dx - size / 2,
      top: at.dy - size / 2,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            center: const Alignment(-0.4, -0.5),
            radius: 1.05,
            colors: [Color.lerp(color, Colors.white, 0.7)!, color, Color.lerp(color, const Color(0xFF140F35), 0.55)!],
            stops: const [0, 0.5, 1],
          ),
          boxShadow: [BoxShadow(color: color.withValues(alpha: 0.75), blurRadius: size * 0.7)],
        ),
      ),
    );
  }

  Widget _scene(double v) {
    const c = Offset(_w / 2, _h / 2);
    final seconds = v * cosmicIdleDuration.inMilliseconds / 1000;
    final appear = Curves.easeOutCubic.transform((seconds / 0.9).clamp(0.0, 1.0));
    // Eases in and out, so everything drifts to a stop.
    final drift = Curves.easeInOut.transform(v);
    final breathe = math.sin(v * math.pi * 6) * math.sin(v * math.pi);
    Offset orbit(double angle, double rx, double ry) =>
        c + Offset(math.cos(angle) * rx, math.sin(angle) * ry * 0.92 + math.cos(angle) * rx * -0.18);
    return Opacity(
      opacity: appear,
      child: Transform.scale(
        scale: 0.9 + 0.1 * appear,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned(
              left: c.dx - 122,
              top: c.dy - 122,
              width: 244,
              height: 244,
              child: Transform.rotate(
                angle: drift * 0.5,
                child: const RepaintBoundary(child: CustomPaint(painter: CosmicZodiacRingPainter())),
              ),
            ),
            // Orbit path.
            const Positioned.fill(child: CustomPaint(painter: _OrbitPathPainter())),
            _orb(orbit(2.5 + drift * 1.9, 96, 82), 11, const Color(0xFF7CC4FF)),
            Positioned(
              left: c.dx - 110,
              top: c.dy - 80 + breathe * 3,
              width: 220,
              height: 160,
              child: const RepaintBoundary(child: CustomPaint(painter: _BrandPlanetPainter())),
            ),
            _orb(orbit(0.5 + drift * 1.9, 96, 82), 17, const Color(0xFF5EEAD4)),
            _orb(orbit(4.3 + drift * 1.9, 96, 82), 13, const Color(0xFFF9A8D4)),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: FittedBox(
        fit: BoxFit.contain,
        child: SizedBox(
          width: _w,
          height: _h,
          child: AnimatedBuilder(animation: _c, builder: (context, _) => _scene(_c.value)),
        ),
      ),
    );
  }
}

class _OrbitPathPainter extends CustomPainter {
  const _OrbitPathPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final p = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.1
      ..color = Colors.white.withValues(alpha: 0.20);
    final path = Path();
    for (var i = 0; i <= 90; i++) {
      final a = i / 90 * math.pi * 2;
      final q = c + Offset(math.cos(a) * 96, math.sin(a) * 82 * 0.92 + math.cos(a) * 96 * -0.18);
      i == 0 ? path.moveTo(q.dx, q.dy) : path.lineTo(q.dx, q.dy);
    }
    canvas.drawPath(path, p);
  }

  @override
  bool shouldRepaint(_OrbitPathPainter old) => false;
}

/// A warm, softly lit planet with a tilted double ring.
class _BrandPlanetPainter extends CustomPainter {
  const _BrandPlanetPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    const r = 50.0;
    canvas.drawCircle(
      c,
      r + 22,
      Paint()
        ..color = cosmicGoldDeep.withValues(alpha: 0.50)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 30),
    );
    canvas.save();
    canvas.translate(c.dx, c.dy);
    canvas.rotate(-0.32);
    final outer = Rect.fromCenter(center: Offset.zero, width: 208, height: 56);
    final inner = Rect.fromCenter(center: Offset.zero, width: 168, height: 40);
    Paint ring(double w, double a) => Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = w
      ..shader = LinearGradient(
        colors: [
          cosmicGoldLight.withValues(alpha: a * 0.35),
          const Color(0xFFFFF1CC).withValues(alpha: a),
          cosmicGoldDeep.withValues(alpha: a * 0.5),
        ],
      ).createShader(outer);
    // Far half of the rings, behind the planet.
    canvas.drawArc(outer, math.pi, math.pi, false, ring(6, 0.75));
    canvas.drawArc(inner, math.pi, math.pi, false, ring(3, 0.55));
    canvas.rotate(0.32);

    // The planet.
    final sphere = Rect.fromCircle(center: Offset.zero, radius: r);
    canvas.drawCircle(
      Offset.zero,
      r,
      Paint()
        ..shader = const RadialGradient(
          center: Alignment(-0.45, -0.55),
          radius: 1.15,
          colors: [Color(0xFFFFF3D0), Color(0xFFFFC46B), Color(0xFFE2703A), Color(0xFF5B2A6E)],
          stops: [0, 0.38, 0.72, 1],
        ).createShader(sphere),
    );
    canvas.save();
    canvas.clipPath(Path()..addOval(sphere));
    canvas.rotate(-0.32);
    final band = Paint()..color = const Color(0xFF8A3B1E).withValues(alpha: 0.20);
    for (final y in const [-26.0, -6.0, 12.0, 30.0]) {
      canvas.drawRect(Rect.fromLTWH(-r - 10, y, r * 2 + 20, 7), band);
    }
    canvas.drawRect(
      const Rect.fromLTWH(-r - 10, 2, r * 2 + 20, 5),
      Paint()..color = const Color(0xFFFFF1CC).withValues(alpha: 0.22),
    );
    // Shadow the ring casts on the planet.
    canvas.drawOval(
      Rect.fromCenter(center: const Offset(0, 9), width: 150, height: 22),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 6
        ..color = const Color(0xFF3A1650).withValues(alpha: 0.30),
    );
    canvas.restore();

    // Near half of the rings, in front.
    canvas.rotate(-0.32);
    canvas.drawArc(
      outer,
      0,
      math.pi,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 9
        ..color = cosmicGoldDeep.withValues(alpha: 0.45)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5),
    );
    canvas.drawArc(outer, 0, math.pi, false, ring(6, 1));
    canvas.drawArc(inner, 0, math.pi, false, ring(3, 0.8));
    canvas.restore();
  }

  @override
  bool shouldRepaint(_BrandPlanetPainter old) => false;
}

// ----------------------------------------------------------------------------
// Email sheet
// ----------------------------------------------------------------------------

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

  static const _fieldText = TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w500);

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
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
      child: CosmicFormTheme(
        child: DecoratedBox(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFF241A55), cosmicSheet, Color(0xFF100C26)],
              stops: [0, 0.4, 1],
            ),
          ),
          child: Padding(
            padding: EdgeInsets.only(bottom: bottomInset),
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 12, 24, 16),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 480),
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
                                color: _white(0.34),
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                          ),
                          const SizedBox(height: 20),

                          // Header Title
                          Row(
                            children: [
                              const ExcludeSemantics(child: CosmicMark(size: 26)),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  _isSignUpMode ? 'Create New Account' : 'Welcome Back',
                                  style: const TextStyle(
                                    fontSize: 24,
                                    fontWeight: FontWeight.w800,
                                    color: Colors.white,
                                    letterSpacing: -0.2,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text(
                            _isSignUpMode
                                ? 'Save your birth details & Kundli securely'
                                : 'Sign in to access your saved Kundli & history',
                            style: TextStyle(fontSize: 14, color: _white(0.76), height: 1.4),
                          ),
                          const SizedBox(height: 20),

                          // Full Name Field (Only in Sign Up Mode)
                          if (_isSignUpMode) ...[
                            TextFormField(
                              key: const ValueKey('auth-name'),
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
                          ],

                          // Email Field
                          TextFormField(
                            key: const ValueKey('auth-email'),
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

                          // Password Field with visibility toggle
                          TextFormField(
                            key: const ValueKey('auth-password'),
                            controller: _passwordController,
                            enabled: !_isSubmitting,
                            style: _fieldText,
                            obscureText: !_isPasswordVisible,
                            textInputAction: TextInputAction.done,
                            autocorrect: false,
                            enableSuggestions: false,
                            autofillHints: [
                              _isSignUpMode ? AutofillHints.newPassword : AutofillHints.password,
                            ],
                            onFieldSubmitted: (_) => _submit(),
                            decoration: cosmicInputDecoration(
                              'Password',
                              Icons.lock_outline,
                              suffix: IconButton(
                                tooltip: _isPasswordVisible ? 'Hide password' : 'Show password',
                                icon: Icon(
                                  _isPasswordVisible ? Icons.visibility : Icons.visibility_off,
                                  color: _white(0.82),
                                ),
                                onPressed: () => setState(() => _isPasswordVisible = !_isPasswordVisible),
                              ),
                            ),
                            validator: (val) => Validators.password(val, isNew: _isSignUpMode),
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

                          // Action Submit Button
                          CosmicPrimaryButton(
                            label: _isSignUpMode ? 'Create Account' : 'Continue',
                            onPressed: _isSubmitting ? null : _submit,
                            loading: _isSubmitting,
                          ),

                          const SizedBox(height: 6),

                          // Toggle Sign In / Sign Up Mode
                          Center(
                            child: TextButton(
                              onPressed: _isSubmitting
                                  ? null
                                  : () => setState(() {
                                        _isSignUpMode = !_isSignUpMode;
                                        _errorMessage = null;
                                      }),
                              style: TextButton.styleFrom(
                                foregroundColor: Colors.white,
                                minimumSize: const Size(48, 44),
                              ),
                              child: Text.rich(
                                TextSpan(
                                  style: TextStyle(fontSize: 14.5, color: _white(0.8)),
                                  children: [
                                    TextSpan(
                                        text: _isSignUpMode ? 'Already have an account? ' : "Don't have an account? "),
                                    TextSpan(
                                      text: _isSignUpMode ? 'Sign In' : 'Sign Up',
                                      style: const TextStyle(
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
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
