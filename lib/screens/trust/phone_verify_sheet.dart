import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../services/notification_service.dart';
import '../../services/trust_service.dart';
import '../../widgets/ui/app_ui.dart';

/// Phone OTP behind an interface (Firebase in the app, a fake in tests).
abstract class PhoneVerifier {
  /// False when Firebase is not initialised: the phone option is hidden.
  bool get available;

  /// Sends an OTP. Completes with a verification id, or with an ID token
  /// directly when Android auto-verifies the SMS ([PhoneCodeResult.idToken]).
  Future<PhoneCodeResult> sendCode(String e164);

  /// Confirms the 6-digit code and returns a Firebase ID token.
  Future<String> confirm(String verificationId, String code);
}

class PhoneCodeResult {
  final String? verificationId;
  final String? idToken;
  const PhoneCodeResult({this.verificationId, this.idToken});
}

class PhoneVerifyException implements Exception {
  final String message;
  const PhoneVerifyException(this.message);
  @override
  String toString() => message;
}

/// Firebase phone auth. We only use the resulting ID token (the server checks
/// it and stores a hash of the number), then sign out of Firebase straight away.
class FirebasePhoneVerifier implements PhoneVerifier {
  @override
  bool get available => NotificationService.firebaseReady;

  FirebaseAuth get _auth => FirebaseAuth.instance;

  Future<String> _tokenFor(PhoneAuthCredential c) async {
    final uc = await _auth.signInWithCredential(c);
    final token = await uc.user?.getIdToken(true);
    unawaited(_auth.signOut().catchError((_) {}));
    if (token == null) throw const PhoneVerifyException('Could not confirm your number. Please try again.');
    return token;
  }

  static String _message(FirebaseAuthException e) => switch (e.code) {
        'invalid-phone-number' => 'That phone number does not look right.',
        'too-many-requests' => 'Too many attempts. Please try again later.',
        'invalid-verification-code' => 'That code is not correct.',
        'session-expired' => 'The code expired. Please send a new one.',
        'quota-exceeded' => 'SMS limit reached. Please try again later.',
        _ => 'Could not verify your number right now. Please try again.',
      };

  @override
  Future<PhoneCodeResult> sendCode(String e164) {
    final done = Completer<PhoneCodeResult>();
    _auth.verifyPhoneNumber(
      phoneNumber: e164,
      timeout: const Duration(seconds: 60),
      verificationCompleted: (cred) async {
        if (done.isCompleted) return;
        try {
          done.complete(PhoneCodeResult(idToken: await _tokenFor(cred)));
        } catch (e) {
          if (!done.isCompleted) done.completeError(e);
        }
      },
      verificationFailed: (e) {
        if (!done.isCompleted) done.completeError(PhoneVerifyException(_message(e)));
      },
      codeSent: (id, _) {
        if (!done.isCompleted) done.complete(PhoneCodeResult(verificationId: id));
      },
      codeAutoRetrievalTimeout: (_) {},
    ).catchError((Object e) {
      if (!done.isCompleted) {
        done.completeError(e is FirebaseAuthException ? PhoneVerifyException(_message(e)) : e);
      }
    });
    return done.future;
  }

  @override
  Future<String> confirm(String verificationId, String code) async {
    try {
      return await _tokenFor(PhoneAuthProvider.credential(verificationId: verificationId, smsCode: code));
    } on FirebaseAuthException catch (e) {
      throw PhoneVerifyException(_message(e));
    }
  }
}

/// Opens the phone OTP sheet. Returns true when the server confirmed the number.
Future<bool> showPhoneVerifySheet(BuildContext context,
    {required TrustService service, required PhoneVerifier verifier}) async {
  final ok = await showAppSheet<bool>(context, builder: (_) => PhoneVerifySheet(service: service, verifier: verifier));
  return ok == true;
}

class PhoneVerifySheet extends StatefulWidget {
  final TrustService service;
  final PhoneVerifier verifier;
  const PhoneVerifySheet({super.key, required this.service, required this.verifier});

  @override
  State<PhoneVerifySheet> createState() => _PhoneVerifySheetState();
}

class _PhoneVerifySheetState extends State<PhoneVerifySheet> {
  final _country = TextEditingController(text: '+91');
  final _number = TextEditingController();
  final _code = TextEditingController();
  String? _verificationId;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _country.dispose();
    _number.dispose();
    _code.dispose();
    super.dispose();
  }

  String? get _e164 {
    final cc = _country.text.replaceAll(RegExp(r'[^\d]'), '');
    final n = _number.text.replaceAll(RegExp(r'[^\d]'), '');
    if (cc.isEmpty || n.length < 6 || cc.length + n.length > 15) return null;
    return '+$cc$n';
  }

  Future<void> _finish(String idToken) async {
    await widget.service.verifyPhone(idToken);
    if (mounted) Navigator.pop(context, true);
  }

  Future<void> _run(Future<void> Function() fn) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await fn();
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e is PhoneVerifyException
          ? e.message
          : (e is TrustException && e.code == 'PHONE_IN_USE')
              ? 'This number has already verified another account.'
              : TrustService.errorText(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _send() {
    final phone = _e164;
    if (phone == null) {
      setState(() => _error = 'Enter your mobile number.');
      return;
    }
    _run(() async {
      final r = await widget.verifier.sendCode(phone);
      if (r.idToken != null) return _finish(r.idToken!);
      if (mounted) setState(() => _verificationId = r.verificationId);
    });
  }

  void _confirm() {
    final id = _verificationId;
    final code = _code.text.trim();
    if (id == null || code.length < 6) {
      setState(() => _error = 'Enter the 6-digit code.');
      return;
    }
    _run(() async => _finish(await widget.verifier.confirm(id, code)));
  }

  @override
  Widget build(BuildContext context) {
    final sent = _verificationId != null;
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
          AppSpacing.page, 0, AppSpacing.page, AppSpacing.lg + MediaQuery.viewInsetsOf(context).bottom),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
        const Text('Verify your phone', style: AppText.title),
        const SizedBox(height: 4),
        const Text(
          'We send a one-time code by SMS. Your number is never shown to anyone and we do not store it: '
          'only a scrambled fingerprint, so one number can verify one account.',
          style: AppText.body,
        ),
        const SizedBox(height: AppSpacing.md),
        if (!sent)
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SizedBox(
              width: 76,
              child: TextField(
                controller: _country,
                keyboardType: TextInputType.phone,
                inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[+\d]')), LengthLimitingTextInputFormatter(4)],
                decoration: const InputDecoration(labelText: 'Code'),
              ),
            ),
            const SizedBox(width: AppSpacing.xs),
            Expanded(
              child: TextField(
                key: const ValueKey('phone-number-field'),
                controller: _number,
                keyboardType: TextInputType.phone,
                autofillHints: const [AutofillHints.telephoneNumberNational],
                inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(12)],
                decoration: const InputDecoration(labelText: 'Mobile number'),
              ),
            ),
          ])
        else
          TextField(
            key: const ValueKey('otp-field'),
            controller: _code,
            keyboardType: TextInputType.number,
            autofillHints: const [AutofillHints.oneTimeCode],
            inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(6)],
            decoration: InputDecoration(labelText: '6-digit code', helperText: 'Sent to ${_e164 ?? 'your phone'}'),
          ),
        if (_error != null) ...[
          const SizedBox(height: AppSpacing.xs),
          Text(_error!, style: AppText.body.copyWith(color: AppColors.danger)),
        ],
        const SizedBox(height: AppSpacing.md),
        AppButton(
          label: sent ? 'Verify' : 'Send code',
          icon: sent ? Icons.check_rounded : Icons.sms_outlined,
          loading: _busy,
          onPressed: _busy ? null : (sent ? _confirm : _send),
        ),
        if (sent)
          TextButton(
            onPressed: _busy ? null : () => setState(() => _verificationId = null),
            child: const Text('Change number'),
          ),
      ]),
    );
  }
}
