import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';

import 'backend_service.dart';
import 'buddy_service.dart';

// ============================================================================
// Trust (v3): verified badge (selfie + gesture), phone check, biodata and
// family share links. Thin API wrapper over BackendService; screens create one
// with `TrustService(context.read<BackendService>())` (no provider needed).
// ============================================================================

/// The fixed gesture prompts. Same list as backend/services/trust_service.js.
class TrustGestures {
  TrustGestures._();

  static const all = [
    'Hold up two fingers',
    'Touch your ear',
    'Thumbs up',
    'Hand on your forehead',
    'Three fingers up',
    'Wave with an open palm',
    'Point at your nose',
    'Cover one eye with your hand',
  ];

  static String random([Random? rng]) => all[(rng ?? Random()).nextInt(all.length)];
}

/// Selfies above this (after compression on the device) are refused.
const maxSelfieBytes = 400 * 1024;

/// Push types added by the trust feature (wired by the notification router).
class TrustNotificationTypes {
  TrustNotificationTypes._();

  /// data: {status: approved|rejected, verificationId, reason?}
  static const verificationUpdate = 'verification_update';

  /// data: {noteId, linkId}
  static const familyNote = 'family_note';
}

/// A failed trust call with the server's machine-readable code (e.g. PENDING).
class TrustException extends BackendException {
  final String? code;
  const TrustException(super.message, {super.statusCode, this.code});
}

int? _int(dynamic v) => v is int ? v : (v is num ? v.round() : int.tryParse('${v ?? ''}'));
String? _str(dynamic v) {
  final s = v?.toString().trim() ?? '';
  return s.isEmpty ? null : s;
}

bool _bool(dynamic v) => v == true || v == 1 || v == 'true';
DateTime? _date(dynamic v) => v == null ? null : DateTime.tryParse(v.toString())?.toLocal();
Map<String, dynamic>? _map(dynamic v) =>
    v is Map<String, dynamic> ? v : (v is Map ? v.map((k, x) => MapEntry('$k', x)) : null);

enum VerificationStatus { none, pending, rejected, verified }

class VerificationRequest {
  final int id;
  final String gesture;
  final String status;
  final String? reason;
  final DateTime? createdAt;
  final DateTime? decidedAt;

  const VerificationRequest(
      {required this.id, required this.gesture, required this.status, this.reason, this.createdAt, this.decidedAt});

  static VerificationRequest? tryParse(dynamic v) {
    final j = _map(v);
    final id = _int(j?['id']);
    if (j == null || id == null) return null;
    return VerificationRequest(
      id: id,
      gesture: _str(j['gesture']) ?? '',
      status: _str(j['status']) ?? 'pending',
      reason: _str(j['reason']),
      createdAt: _date(j['createdAt']),
      decidedAt: _date(j['decidedAt']),
    );
  }
}

/// GET /buddy/verification.
class VerificationState {
  final VerificationStatus status;
  final bool phoneVerified;

  /// The server can check Firebase phone tokens.
  final bool phoneAvailable;
  final VerificationRequest? latest;
  final int submissionsToday;
  final int dailyLimit;
  final List<String> gestures;

  const VerificationState({
    this.status = VerificationStatus.none,
    this.phoneVerified = false,
    this.phoneAvailable = false,
    this.latest,
    this.submissionsToday = 0,
    this.dailyLimit = 3,
    this.gestures = TrustGestures.all,
  });

  factory VerificationState.fromJson(Map<String, dynamic> j) {
    final s = _str(j['status']);
    final verified = _bool(j['verified']) || s == 'verified';
    final g = j['gestures'];
    return VerificationState(
      status: verified
          ? VerificationStatus.verified
          : switch (s) {
              'pending' => VerificationStatus.pending,
              'rejected' => VerificationStatus.rejected,
              _ => VerificationStatus.none,
            },
      phoneVerified: _bool(j['phoneVerified']),
      phoneAvailable: _bool(j['phoneAvailable']),
      latest: VerificationRequest.tryParse(j['latest']),
      submissionsToday: _int(j['submissionsToday']) ?? 0,
      dailyLimit: _int(j['dailyLimit']) ?? 3,
      gestures: g is List && g.isNotEmpty ? g.map((e) => '$e').toList() : TrustGestures.all,
    );
  }

  bool get verified => status == VerificationStatus.verified;
  bool get canSubmit =>
      (status == VerificationStatus.none || status == VerificationStatus.rejected) && submissionsToday < dailyLimit;
  bool get limitReached => submissionsToday >= dailyLimit;
}

class FamilyLink {
  final int id;
  final String kind; // self | match
  final String token;
  final String url;
  final int? matchUserId;
  final String? matchName;
  final DateTime? createdAt;
  final DateTime? expiresAt;
  final DateTime? revokedAt;
  final bool active;
  final int notesCount;

  const FamilyLink({
    required this.id,
    required this.kind,
    required this.token,
    required this.url,
    this.matchUserId,
    this.matchName,
    this.createdAt,
    this.expiresAt,
    this.revokedAt,
    this.active = true,
    this.notesCount = 0,
  });

  static FamilyLink? tryParse(dynamic v) {
    final j = _map(v);
    final id = _int(j?['id']);
    final url = _str(j?['url']);
    if (j == null || id == null || url == null) return null;
    final m = _map(j['match']);
    return FamilyLink(
      id: id,
      kind: j['kind'] == 'match' ? 'match' : 'self',
      token: _str(j['token']) ?? '',
      url: url,
      matchUserId: _int(m?['userId']),
      matchName: _str(m?['displayName']),
      createdAt: _date(j['createdAt']),
      expiresAt: _date(j['expiresAt']),
      revokedAt: _date(j['revokedAt']),
      active: _bool(j['active']),
      notesCount: _int(j['notesCount']) ?? 0,
    );
  }

  bool get isMatch => kind == 'match';
  String get title => isMatch ? 'Match: ${matchName ?? 'a buddy'}' : 'My profile';
}

class FamilyNote {
  final int id;
  final int linkId;
  final String name;
  final String relation;
  final String message;

  /// Name of the match the note is about (match links), else null.
  final String? about;
  final DateTime? createdAt;

  const FamilyNote({
    required this.id,
    required this.linkId,
    required this.name,
    required this.relation,
    required this.message,
    this.about,
    this.createdAt,
  });

  static FamilyNote? tryParse(dynamic v) {
    final j = _map(v);
    final id = _int(j?['id']);
    if (j == null || id == null) return null;
    return FamilyNote(
      id: id,
      linkId: _int(j['linkId']) ?? 0,
      name: _str(j['name']) ?? 'Family',
      relation: _str(j['relation']) ?? 'Other',
      message: _str(j['message']) ?? '',
      about: _str(j['about']),
      createdAt: _date(j['createdAt']),
    );
  }
}

class TrustService {
  final BackendService backend;
  TrustService(this.backend);

  /// Friendly text for any trust error.
  static String errorText(Object e) {
    if (e is TrustException) {
      switch (e.code) {
        case 'BANNED':
          return BuddyService.bannedMessage;
        case 'NO_PROFILE':
          return 'Create your buddy profile first.';
        case 'LOGIN_REQUIRED':
          return 'Please log in first.';
      }
    }
    return BuddyService.errorText(e);
  }

  Future<Map<String, dynamic>> _api(String method, String path, {Map<String, dynamic>? body}) async {
    try {
      return await backend.api(method, path, body: body, timeout: const Duration(seconds: 30));
    } on BackendException catch (e) {
      throw TrustException(e.message, statusCode: e.statusCode, code: backend.lastErrorCode);
    }
  }

  // ------------------------------------------------------------ verification

  Future<VerificationState> loadVerification() async =>
      VerificationState.fromJson(await _api('GET', '/buddy/verification'));

  /// Sends the selfie (JPEG bytes, already compressed) with the gesture shown.
  Future<VerificationState> submitSelfie(String gesture, Uint8List jpeg) async {
    if (jpeg.length > maxSelfieBytes) {
      throw const TrustException('This photo is too large. Please retake it.', code: 'BAD_IMAGE');
    }
    return VerificationState.fromJson(
        await _api('POST', '/buddy/verification', body: {'gesture': gesture, 'imageBase64': base64Encode(jpeg)}));
  }

  /// Sends the Firebase ID token proving the phone number (never the number).
  Future<VerificationState> verifyPhone(String idToken) async =>
      VerificationState.fromJson(await _api('POST', '/buddy/verification/phone', body: {'idToken': idToken}));

  // ----------------------------------------------------------------- biodata

  Future<Biodata> loadBiodata() async => Biodata.tryParse((await _api('GET', '/buddy/biodata'))['biodata']) ?? Biodata.empty;

  Future<Biodata> saveBiodata(Biodata b) async =>
      Biodata.tryParse((await _api('PUT', '/buddy/biodata', body: {'biodata': b.toJson()}))['biodata']) ?? b;

  // ------------------------------------------------------------------ family

  Future<({List<FamilyLink> links, int maxActive})> familyLinks() async {
    final res = await _api('GET', '/family/links');
    final raw = res['links'];
    return (
      links: raw is List ? raw.map(FamilyLink.tryParse).whereType<FamilyLink>().toList() : <FamilyLink>[],
      maxActive: _int(res['maxActive']) ?? 5,
    );
  }

  /// My own profile, or (with [matchUserId]) an accepted buddy as a match.
  Future<FamilyLink> createFamilyLink({int? matchUserId}) async {
    final res = await _api('POST', '/family/links',
        body: matchUserId == null ? {'kind': 'self'} : {'kind': 'match', 'matchUserId': matchUserId});
    final link = FamilyLink.tryParse(res['link']);
    if (link == null) throw const TrustException('Could not create the link. Please try again.');
    return link;
  }

  Future<void> revokeFamilyLink(int id) => _api('DELETE', '/family/links/$id');

  Future<List<FamilyNote>> familyNotes() async {
    final raw = (await _api('GET', '/family/notes'))['notes'];
    return raw is List ? raw.map(FamilyNote.tryParse).whereType<FamilyNote>().toList() : <FamilyNote>[];
  }

  Future<void> deleteFamilyNote(int id) => _api('DELETE', '/family/notes/$id');
}
