import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../services/backend_service.dart';
import '../../services/buddy_service.dart';
import '../../services/trust_service.dart';
import '../../widgets/buddy/buddy_ui.dart';
import '../../widgets/buddy/trust_badges.dart';
import '../../widgets/ui/app_ui.dart';
import 'phone_verify_sheet.dart';
import 'selfie_picker.dart';

/// Updates BuddyService's cached profile if it is provided (it is in the app).
void syncBuddyTrust(BuildContext context, {bool? verified, bool? phoneVerified, Biodata? biodata}) {
  try {
    context.read<BuddyService>().applyTrustUpdate(verified: verified, phoneVerified: phoneVerified, biodata: biodata);
  } catch (_) {
    // No BuddyService above this screen (tests): nothing to sync.
  }
}

/// "Get verified": a random gesture, a front-camera selfie, team review, then
/// the blue Verified badge (+50 coins). Also hosts the optional phone check.
class VerificationScreen extends StatefulWidget {
  /// Camera abstraction (tests pass a fake).
  final SelfiePicker? picker;

  /// Phone OTP abstraction; null uses Firebase (hidden when Firebase is off).
  final PhoneVerifier? phoneVerifier;

  /// Overrides the API wrapper (tests).
  final TrustService? service;

  /// Seeded randomness for the gesture prompt (tests).
  final Random? random;

  const VerificationScreen({super.key, this.picker, this.phoneVerifier, this.service, this.random});

  @override
  State<VerificationScreen> createState() => _VerificationScreenState();
}

class _VerificationScreenState extends State<VerificationScreen> {
  late final TrustService _service = widget.service ?? TrustService(context.read<BackendService>());
  late final SelfiePicker _picker = widget.picker ?? ImagePickerSelfiePicker();
  late final PhoneVerifier _phone = widget.phoneVerifier ?? FirebasePhoneVerifier();

  VerificationState? _state;
  bool _loading = true;
  String? _error;
  String? _errorCode;

  String? _gesture;
  Uint8List? _photo;
  String? _captureError;
  bool _capturing = false;
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  bool get _loggedIn => context.read<BackendService>().isAuthenticated;

  Future<void> _load() async {
    if (!mounted) return;
    if (!_loggedIn) {
      setState(() => _loading = false);
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
      _errorCode = null;
    });
    try {
      final s = await _service.loadVerification();
      if (!mounted) return;
      setState(() {
        _state = s;
        _loading = false;
      });
      syncBuddyTrust(context, verified: s.verified, phoneVerified: s.phoneVerified);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = TrustService.errorText(e);
        _errorCode = e is TrustException ? e.code : null;
      });
    }
  }

  void _start() {
    final list = _state?.gestures ?? TrustGestures.all;
    setState(() {
      _gesture = list[(widget.random ?? Random()).nextInt(list.length)];
      _photo = null;
      _captureError = null;
    });
  }

  Future<void> _takeSelfie() async {
    setState(() {
      _capturing = true;
      _captureError = null;
    });
    try {
      final bytes = await _picker.takeSelfie();
      if (!mounted) return;
      if (bytes == null) {
        setState(() => _capturing = false);
        return;
      }
      setState(() {
        _capturing = false;
        if (bytes.length > maxSelfieBytes) {
          _photo = null;
          _captureError = 'That photo is too large (over 400 KB). Please retake it in good light.';
        } else {
          _photo = bytes;
        }
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _capturing = false;
        _captureError = 'Could not open the camera. Please allow camera access and try again.';
      });
    }
  }

  Future<void> _send() async {
    final g = _gesture;
    final p = _photo;
    if (g == null || p == null) return;
    setState(() {
      _sending = true;
      _captureError = null;
    });
    try {
      final s = await _service.submitSelfie(g, p);
      if (!mounted) return;
      setState(() {
        _state = s;
        _sending = false;
        _gesture = null;
        _photo = null;
      });
      showAppSnack(context, 'Selfie sent. We will let you know once it is reviewed.');
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _sending = false;
        _captureError = TrustService.errorText(e);
      });
      if (e is TrustException && (e.code == 'PENDING' || e.code == 'ALREADY_VERIFIED')) _load();
    }
  }

  Future<void> _verifyPhone() async {
    final ok = await showPhoneVerifySheet(context, service: _service, verifier: _phone);
    if (!mounted || !ok) return;
    showAppSnack(context, 'Phone verified');
    syncBuddyTrust(context, phoneVerified: true);
    _load();
  }

  // -------------------------------------------------------------------- UI

  Widget _hero() => AppCard(
        gradient: AppColors.cosmicGradient,
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Row(children: [
            VerifiedBadge(onDark: true),
            Spacer(),
            Icon(Icons.shield_moon_outlined, color: AppColors.gold, size: 28),
          ]),
          const SizedBox(height: AppSpacing.sm),
          const Text('Show people you are real',
              style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w800, height: 1.25)),
          const SizedBox(height: 6),
          const Text(
            'One quick selfie with a simple gesture. Our team checks it and you get the blue badge.',
            style: TextStyle(color: AppColors.textOnDarkMuted, fontSize: 14, height: 1.45),
          ),
          const SizedBox(height: AppSpacing.md),
          for (final (icon, text) in const [
            (Icons.trending_up_rounded, 'Shown a little higher in Discover'),
            (Icons.monetization_on_outlined, '+50 coins once approved'),
          ])
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Icon(icon, size: 18, color: AppColors.gold),
                const SizedBox(width: 8),
                Expanded(child: Text(text, style: const TextStyle(color: Colors.white, fontSize: 13.5, height: 1.35))),
              ]),
            ),
        ]),
      );

  Widget _statusCard(VerificationState s) {
    switch (s.status) {
      case VerificationStatus.verified:
        return AppCard(
          key: const ValueKey('verified-card'),
          child: Row(children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(color: verifiedBlue.withValues(alpha: 0.12), shape: BoxShape.circle),
              child: const Icon(Icons.verified_rounded, color: verifiedBlue, size: 30),
            ),
            const SizedBox(width: AppSpacing.sm),
            const Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('You are verified', style: AppText.title),
                SizedBox(height: 2),
                Text('Your blue badge shows on your buddy profile everywhere.', style: AppText.body),
              ]),
            ),
          ]),
        );
      case VerificationStatus.pending:
        final l = s.latest;
        return AppCard(
          key: const ValueKey('pending-card'),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Row(children: [
              Icon(Icons.hourglass_top_rounded, color: AppColors.warning),
              SizedBox(width: 8),
              Expanded(child: Text('Under review', style: AppText.title)),
            ]),
            const SizedBox(height: 6),
            Text(
              'Thanks! Our team is checking your selfie${l?.gesture.isNotEmpty == true ? ' (${l!.gesture.toLowerCase()})' : ''}. '
              'This usually takes less than a day. We will send you a notification.',
              style: AppText.body,
            ),
            if (l?.createdAt != null) ...[
              const SizedBox(height: 6),
              Text('Sent ${DateFormat('d MMM, h:mm a').format(l!.createdAt!)}', style: AppText.caption),
            ],
          ]),
        );
      case VerificationStatus.rejected:
        return AppCard(
          key: const ValueKey('rejected-card'),
          color: AppColors.dangerSoft,
          border: false,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Row(children: [
              Icon(Icons.error_outline_rounded, color: AppColors.danger),
              SizedBox(width: 8),
              Expanded(child: Text('Not approved this time', style: AppText.title)),
            ]),
            const SizedBox(height: 6),
            Text(s.latest?.reason ?? 'The selfie did not clearly show your face and the gesture.',
                style: AppText.bodyStrong),
            const SizedBox(height: 4),
            const Text('No problem: you can try again with a new gesture.', style: AppText.body),
          ]),
        );
      case VerificationStatus.none:
        return const SizedBox.shrink();
    }
  }

  Widget _captureFlow(VerificationState s) {
    if (s.limitReached && s.status != VerificationStatus.pending) {
      return BuddyNote(
        icon: Icons.schedule_rounded,
        color: AppColors.warning,
        text: 'You can send ${s.dailyLimit} selfies a day. Please try again tomorrow.',
      );
    }
    final g = _gesture;
    if (g == null) {
      return AppCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const Text('How it works', style: AppText.subtitle),
          const SizedBox(height: AppSpacing.xs),
          for (final (n, t) in const [
            ('1', 'We show you a simple gesture, like a thumbs up'),
            ('2', 'Take a selfie with the front camera doing it'),
            ('3', 'Our team compares it with your profile'),
          ])
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(children: [
                CircleAvatar(
                  radius: 13,
                  backgroundColor: AppColors.primarySoft,
                  child: Text(n, style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.w800, fontSize: 13)),
                ),
                const SizedBox(width: 10),
                Expanded(child: Text(t, style: AppText.bodyStrong)),
              ]),
            ),
          const SizedBox(height: AppSpacing.xs),
          AppButton(
            key: const ValueKey('start-verification'),
            label: s.status == VerificationStatus.rejected ? 'Try again' : 'Start verification',
            icon: Icons.camera_front_rounded,
            onPressed: _start,
          ),
        ]),
      );
    }
    final photo = _photo;
    return AppCard(
      key: const ValueKey('capture-card'),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const Text('Your gesture', style: AppText.caption),
        const SizedBox(height: 4),
        Container(
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(color: AppColors.primarySoft, borderRadius: BorderRadius.circular(AppRadius.md)),
          child: Row(children: [
            const Icon(Icons.back_hand_outlined, color: AppColors.primary, size: 28),
            const SizedBox(width: AppSpacing.sm),
            Expanded(child: Text(g, key: const ValueKey('gesture-text'), style: AppText.title)),
          ]),
        ),
        const SizedBox(height: AppSpacing.sm),
        if (photo != null) ...[
          ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.md),
            child: AspectRatio(
              aspectRatio: 3 / 4,
              child: Image.memory(photo, fit: BoxFit.cover, gaplessPlayback: true, errorBuilder: (_, __, ___) {
                return Container(
                  color: AppColors.surfaceMuted,
                  alignment: Alignment.center,
                  child: const Icon(Icons.image_outlined, size: 40, color: AppColors.textTertiary),
                );
              }),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
        ] else
          const Text('Face the camera in good light, keep your whole face visible and do the gesture above.',
              style: AppText.body),
        if (_captureError != null) ...[
          const SizedBox(height: AppSpacing.xs),
          Text(_captureError!, style: AppText.body.copyWith(color: AppColors.danger)),
        ],
        const SizedBox(height: AppSpacing.sm),
        if (photo == null)
          AppButton(
            key: const ValueKey('take-selfie'),
            label: 'Take selfie',
            icon: Icons.photo_camera_front_rounded,
            loading: _capturing,
            onPressed: _capturing ? null : _takeSelfie,
          )
        else
          Row(children: [
            Expanded(
              child: AppButton(
                label: 'Retake',
                variant: AppButtonVariant.outline,
                onPressed: _sending ? null : _takeSelfie,
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              flex: 2,
              child: AppButton(
                key: const ValueKey('send-selfie'),
                label: 'Send for review',
                icon: Icons.send_rounded,
                loading: _sending,
                onPressed: _sending ? null : _send,
              ),
            ),
          ]),
      ]),
    );
  }

  Widget _phoneCard(VerificationState s) => AppCard(
        key: const ValueKey('phone-card'),
        child: Row(children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(color: AppColors.successSoft, borderRadius: BorderRadius.circular(12)),
            child: const Icon(Icons.phone_iphone_rounded, color: AppColors.success),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Phone check', style: AppText.subtitle),
              const SizedBox(height: 2),
              Text(
                s.phoneVerified ? 'Your number is confirmed. It is never shown to anyone.' : 'Optional. Confirm your number with a one-time SMS code.',
                style: AppText.caption.copyWith(color: AppColors.textSecondary),
              ),
            ]),
          ),
          const SizedBox(width: AppSpacing.xs),
          if (s.phoneVerified)
            const Flexible(child: PhoneVerifiedChip())
          else
            AppButton(
              key: const ValueKey('verify-phone'),
              label: 'Verify',
              expand: false,
              height: 40,
              variant: AppButtonVariant.secondary,
              onPressed: _verifyPhone,
            ),
        ]),
      );

  Widget _body() {
    if (!_loggedIn) {
      return Center(
        child: AppStateView(
          icon: Icons.lock_person_rounded,
          title: 'Log in to get verified',
          message: 'Verification is for registered members with a buddy profile.',
          actionLabel: 'Log in',
          onAction: () => Navigator.pushNamed(context, '/login'),
        ),
      );
    }
    if (_loading && _state == null) return const Center(child: CircularProgressIndicator());
    final s = _state;
    if (s == null) {
      if (_errorCode == 'NO_PROFILE') {
        return const Center(
          child: AppStateView(
            icon: Icons.person_add_alt_1_rounded,
            title: 'Create your buddy profile first',
            message: 'Open Find your buddy, set up your profile, then come back to get verified.',
          ),
        );
      }
      if (_errorCode == 'BANNED') {
        return const Center(
          child: AppStateView(
              icon: Icons.gpp_maybe_outlined, title: 'Profile suspended', message: BuddyService.bannedMessage),
        );
      }
      return Center(child: AppStateView.error(message: _error, onAction: _load));
    }
    final showPhone = _phone.available && (s.phoneAvailable || s.phoneVerified);
    return RefreshIndicator(
      onRefresh: _load,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(AppSpacing.page, AppSpacing.md, AppSpacing.page, AppSpacing.xxl),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (s.status == VerificationStatus.none) ...[_hero(), const SizedBox(height: AppSpacing.md)],
          if (s.status != VerificationStatus.none) ...[_statusCard(s), const SizedBox(height: AppSpacing.md)],
          if (s.canSubmit || (s.limitReached && !s.verified && s.status != VerificationStatus.pending)) ...[
            _captureFlow(s),
            const SizedBox(height: AppSpacing.md),
          ],
          if (showPhone) ...[_phoneCard(s), const SizedBox(height: AppSpacing.md)],
          const BuddyNote(
            icon: Icons.lock_outline_rounded,
            color: AppColors.success,
            text: 'Your selfie is seen only by our review team and is deleted as soon as it is reviewed. '
                'It is never shown on your profile.',
          ),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Get verified')),
      body: _body(),
    );
  }
}
