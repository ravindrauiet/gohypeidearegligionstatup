import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:google_sign_in/google_sign_in.dart';
import '../../services/backend_service.dart';
import '../../utils/app_routes.dart';
import '../../utils/validators.dart';
import '../../widgets/google_logo_widget.dart';
import '../../widgets/google_web_button.dart';
import '../../widgets/ui/app_ui.dart';

/// The Web OAuth client of the CosmicGuide Google Cloud project. Google issues
/// ID tokens for this client so the backend can verify them.
const String _kGoogleWebClientId = '744178907337-5vrb5sdqaua06vrkou013h3vqfalk94e.apps.googleusercontent.com';

/// Photo at the top of the sign-in screen.
const String _kHeroImage = 'assets/images/astrology-hero.jpg';

Future<void>? _googleInit;

/// Initializes Google Sign-In once. The web plugin takes the Web client as its
/// own `clientId` (and rejects `serverClientId`); Android/iOS request tokens
/// for it as the server client.
Future<void> _ensureGoogleInit() async {
  _googleInit ??= kIsWeb
      ? GoogleSignIn.instance.initialize(clientId: _kGoogleWebClientId)
      : GoogleSignIn.instance.initialize(serverClientId: _kGoogleWebClientId);
  try {
    await _googleInit;
  } catch (_) {
    _googleInit = null; // allow a retry
    rethrow;
  }
}

/// Shows the Google account picker and returns an ID token, or null when the
/// user cancels. Not available on the web, which uses Google's rendered button.
Future<String?> _googleSignInIdToken() async {
  final google = GoogleSignIn.instance;
  await _ensureGoogleInit();
  try {
    final account = await google.authenticate();
    final idToken = account.authentication.idToken;
    if (idToken == null) throw StateError('Google returned no ID token');
    return idToken;
  } on GoogleSignInException catch (e) {
    if (e.code == GoogleSignInExceptionCode.canceled || e.code == GoogleSignInExceptionCode.interrupted) {
      return null;
    }
    rethrow;
  }
}

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  /// Obtains a Google ID token; replaceable in tests (no platform plugin there).
  @visibleForTesting
  static Future<String?> Function() googleIdToken = _googleSignInIdToken;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  bool _sheetOpen = false;
  bool _googleBusy = false;
  StreamSubscription<GoogleSignInAuthenticationEvent>? _googleEvents;

  @override
  void initState() {
    super.initState();
    // On the web, signing in happens through Google's rendered button, which
    // reports the result as an authentication event.
    if (kIsWeb) {
      _googleEvents = GoogleSignIn.instance.authenticationEvents.listen(
        (event) {
          if (event is GoogleSignInAuthenticationEventSignIn) {
            final idToken = event.user.authentication.idToken;
            if (idToken != null) _completeGoogleLogin(idToken);
          }
        },
        onError: (Object e) {
          if (e is GoogleSignInException && e.code == GoogleSignInExceptionCode.canceled) return;
          debugPrint('Google sign-in error: $e');
          if (mounted) _showSnackBar('Google sign-in failed. Please try again or continue with email.');
        },
      );
      _ensureGoogleInit().catchError((Object e) {
        debugPrint('Google sign-in init error: $e');
        if (mounted) setState(() {}); // keep the button area from waiting forever
      });
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    precacheImage(const AssetImage(_kHeroImage), context, onError: (_, __) {});
  }

  @override
  void dispose() {
    _googleEvents?.cancel();
    super.dispose();
  }

  void _showSnackBar(String message) => showAppSnack(context, message, error: true);

  Future<void> _handleGoogleLogin() async {
    if (_googleBusy || _sheetOpen) return;
    try {
      final idToken = await LoginScreen.googleIdToken();
      if (idToken == null || !mounted) return; // cancelled
      await _completeGoogleLogin(idToken);
    } catch (e) {
      debugPrint('Google sign-in error: $e');
      if (mounted) {
        _showSnackBar('Google sign-in is unavailable right now. Please continue with email.');
      }
    }
  }

  /// Exchanges a Google ID token for an app session and leaves the login screen.
  Future<void> _completeGoogleLogin(String idToken) async {
    if (_googleBusy) return;
    setState(() => _googleBusy = true);
    final backendService = context.read<BackendService>();
    try {
      final ok = await backendService.loginWithGoogle(idToken);
      if (!mounted) return;
      if (!ok) {
        _showSnackBar(backendService.lastError ?? 'Google sign-in failed. Please try again.');
        return;
      }
      Fluttertoast.showToast(
        msg: 'Signed in successfully!',
        backgroundColor: AppColors.textPrimary,
        textColor: Colors.white,
      );
      Navigator.pushNamedAndRemoveUntil(
        context,
        AuthFlow.routeAfterLogin(backendService),
        (route) => false,
      );
    } finally {
      if (mounted) setState(() => _googleBusy = false);
    }
  }

  Future<void> _showEmailAuthModal({bool signUp = false}) async {
    if (_sheetOpen) return;
    _sheetOpen = true;
    final success = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
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
      backgroundColor: AppColors.textPrimary,
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
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 44),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Center(
            widthFactor: 1,
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: AppColors.textSecondary,
                decoration: TextDecoration.underline,
                decorationColor: AppColors.textTertiary,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _googleButton() {
    if (kIsWeb) {
      return SizedBox(
        height: 52,
        child: Center(
          child: _googleBusy
              ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2.5))
              : buildGoogleWebButton(),
        ),
      );
    }
    return _GoogleButton(onPressed: _googleBusy ? null : _handleGoogleLogin, loading: _googleBusy);
  }

  /// The white sheet holding every way to continue.
  Widget _sheet() {
    const legal = TextStyle(fontSize: 12.5, color: AppColors.textTertiary, height: 1.3);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text('Log in or sign up', style: AppText.headline),
        const SizedBox(height: 6),
        const Text(
          'Save your Kundli and pick up where you left off on any device.',
          style: AppText.body,
        ),
        const SizedBox(height: AppSpacing.xl),
        _googleButton(),
        const SizedBox(height: AppSpacing.md),
        const Row(
          children: [
            Expanded(child: Divider()),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: AppSpacing.sm),
              child: Text('or', style: AppText.caption),
            ),
            Expanded(child: Divider()),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        AppButton(
          label: 'Continue with Email',
          icon: Icons.mail_outline_rounded,
          onPressed: () => _showEmailAuthModal(),
        ),
        const SizedBox(height: AppSpacing.xs),
        Center(
          child: TextButton(
            onPressed: () => _showEmailAuthModal(signUp: true),
            style: TextButton.styleFrom(minimumSize: const Size(48, 44)),
            child: const Text.rich(
              TextSpan(
                text: 'New here? ',
                style: TextStyle(color: AppColors.textSecondary, fontWeight: FontWeight.w500),
                children: [
                  TextSpan(
                    text: 'Create an account',
                    style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.w700),
                  ),
                ],
              ),
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14.5),
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        Wrap(
          alignment: WrapAlignment.center,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            const Text('By continuing you agree to our ', style: legal),
            _legalLink('Terms', AppRoutes.terms),
            const Text('&', style: legal),
            _legalLink('Privacy Policy', AppRoutes.privacy),
          ],
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light.copyWith(
        statusBarColor: Colors.transparent,
        systemNavigationBarColor: AppColors.surface,
        systemNavigationBarIconBrightness: Brightness.dark,
      ),
      child: Scaffold(
        backgroundColor: AppColors.surface,
        body: LayoutBuilder(
          builder: (context, constraints) {
            final h = constraints.maxHeight;
            final top = MediaQuery.paddingOf(context).top;
            // The photo takes the top ~40% and steps aside on short screens.
            final heroH = (h * 0.42).clamp(170.0 + top, 380.0 + top);
            return SingleChildScrollView(
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: h),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(height: heroH + AppRadius.xl, child: _Hero(topInset: top)),
                    // The sheet overlaps the photo with rounded top corners.
                    Transform.translate(
                      offset: const Offset(0, -AppRadius.xl),
                      child: Container(
                        decoration: const BoxDecoration(color: AppColors.surface, borderRadius: AppRadius.sheet),
                        padding: EdgeInsets.fromLTRB(
                          AppSpacing.page + 4,
                          AppSpacing.xl,
                          AppSpacing.page + 4,
                          AppSpacing.md + MediaQuery.paddingOf(context).bottom,
                        ),
                        child: Center(
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 440),
                            child: _sheet(),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

/// Photo with the brand on top.
class _Hero extends StatelessWidget {
  final double topInset;
  const _Hero({required this.topInset});

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        Image.asset(
          _kHeroImage,
          fit: BoxFit.cover,
          alignment: const Alignment(0.35, 0),
          excludeFromSemantics: true,
          errorBuilder: (_, __, ___) =>
              const DecoratedBox(decoration: BoxDecoration(gradient: AppColors.cosmicGradient)),
        ),
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0x33000000), Color(0x00000000), Color(0xB31B1446)],
              stops: [0, 0.4, 1],
            ),
          ),
        ),
        Positioned(
          left: AppSpacing.page + 4,
          right: AppSpacing.page + 4,
          bottom: AppRadius.xl + AppSpacing.lg,
          child: MediaQuery.withClampedTextScaling(
            maxScaleFactor: 1.2,
            child: Semantics(
              header: true,
              label: 'CosmicGuide. Vedic astrology, made simple',
              child: ExcludeSemantics(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(AppRadius.md),
                      child: Image.asset(
                        'assets/icons/cosmicguide_icon.png',
                        width: 48,
                        height: 48,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => const SizedBox(width: 48, height: 48),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Text('CosmicGuide', style: AppText.display.copyWith(color: AppColors.textOnDark)),
                    const SizedBox(height: 2),
                    Text(
                      'Vedic astrology, made simple',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.body.copyWith(color: AppColors.textOnDarkMuted, fontSize: 15),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// White outlined "Continue with Google" button with the Google logo.
class _GoogleButton extends StatelessWidget {
  final VoidCallback? onPressed;
  final bool loading;
  const _GoogleButton({required this.onPressed, required this.loading});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      enabled: onPressed != null,
      label: 'Continue with Google',
      excludeSemantics: true,
      child: Material(
        color: AppColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: AppRadius.button,
          side: const BorderSide(color: AppColors.border, width: 1.2),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onPressed,
          child: SizedBox(
            height: 52,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (loading)
                    const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.2))
                  else
                    const GoogleLogoWidget(size: 20),
                  const SizedBox(width: AppSpacing.sm),
                  Flexible(
                    child: Text(
                      'Continue with Google',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.button.copyWith(color: AppColors.textPrimary),
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
      child: Padding(
        padding: EdgeInsets.only(bottom: bottomInset),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(AppSpacing.page + 4, 0, AppSpacing.page + 4, AppSpacing.md),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: AutofillGroup(
                child: Form(
                  key: _formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        _isSignUpMode ? 'Create New Account' : 'Welcome Back',
                        style: AppText.headline,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _isSignUpMode
                            ? 'Save your birth details & Kundli securely'
                            : 'Sign in to access your saved Kundli & history',
                        style: AppText.body,
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      if (_isSignUpMode) ...[
                        TextFormField(
                          key: const ValueKey('auth-name'),
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
                      ],
                      TextFormField(
                        key: const ValueKey('auth-email'),
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
                        key: const ValueKey('auth-password'),
                        controller: _passwordController,
                        enabled: !_isSubmitting,
                        obscureText: !_isPasswordVisible,
                        textInputAction: TextInputAction.done,
                        autocorrect: false,
                        enableSuggestions: false,
                        autofillHints: [
                          _isSignUpMode ? AutofillHints.newPassword : AutofillHints.password,
                        ],
                        onFieldSubmitted: (_) => _submit(),
                        decoration: InputDecoration(
                          labelText: 'Password',
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
                        validator: (val) => Validators.password(val, isNew: _isSignUpMode),
                      ),
                      if (_errorMessage != null) ...[
                        const SizedBox(height: AppSpacing.sm),
                        _ErrorBanner(_errorMessage!),
                      ],
                      const SizedBox(height: AppSpacing.lg),
                      AppButton(
                        label: _isSignUpMode ? 'Create Account' : 'Continue',
                        onPressed: _isSubmitting ? null : _submit,
                        loading: _isSubmitting,
                      ),
                      const SizedBox(height: 4),
                      Center(
                        child: TextButton(
                          onPressed: _isSubmitting
                              ? null
                              : () => setState(() {
                                    _isSignUpMode = !_isSignUpMode;
                                    _errorMessage = null;
                                  }),
                          style: TextButton.styleFrom(minimumSize: const Size(48, 44)),
                          child: Text.rich(
                            TextSpan(
                              style: const TextStyle(
                                fontSize: 14.5,
                                color: AppColors.textSecondary,
                                fontWeight: FontWeight.w500,
                              ),
                              children: [
                                TextSpan(
                                  text: _isSignUpMode ? 'Already have an account? ' : "Don't have an account? ",
                                ),
                                TextSpan(
                                  text: _isSignUpMode ? 'Sign In' : 'Sign Up',
                                  style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.primary),
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
    );
  }
}

/// Inline error shown above the submit button.
class _ErrorBanner extends StatelessWidget {
  final String message;
  const _ErrorBanner(this.message);

  @override
  Widget build(BuildContext context) {
    return Container(
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
              message,
              style:
                  const TextStyle(color: AppColors.danger, fontSize: 13.5, height: 1.35, fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }
}
