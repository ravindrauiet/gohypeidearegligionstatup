import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

import 'backend_service.dart';

// ============================================================================
// Models (defensive parsing: the backend may send numbers as strings, nulls or
// missing keys; nothing here throws on odd JSON).
// ============================================================================

int? _int(dynamic v) {
  if (v == null) return null;
  if (v is int) return v;
  if (v is num) return v.round();
  return num.tryParse(v.toString().trim())?.round();
}

String _str(dynamic v, [String fallback = '']) {
  if (v == null) return fallback;
  final s = v.toString().trim();
  return s.isEmpty ? fallback : s;
}

String? _strOrNull(dynamic v) {
  final s = _str(v);
  return s.isEmpty ? null : s;
}

bool _bool(dynamic v, [bool fallback = false]) {
  if (v is bool) return v;
  if (v is num) return v != 0;
  if (v is String) {
    final s = v.toLowerCase().trim();
    if (s == 'true' || s == '1' || s == 'yes') return true;
    if (s == 'false' || s == '0' || s == 'no') return false;
  }
  return fallback;
}

List<String> _strList(dynamic v) {
  if (v is List) return v.map((e) => _str(e)).where((e) => e.isNotEmpty).toList();
  if (v is String && v.trim().isNotEmpty) {
    return v.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
  }
  return const [];
}

Map<String, dynamic>? _map(dynamic v) {
  if (v is Map<String, dynamic>) return v;
  if (v is Map) return v.map((k, val) => MapEntry(k.toString(), val));
  return null;
}

DateTime? _date(dynamic v) {
  if (v == null) return null;
  final d = DateTime.tryParse(v.toString());
  return d?.toLocal();
}

int _pct(dynamic v) => (_int(v) ?? 0).clamp(0, 100);

/// The five things people can look for. Keys match the backend.
class BuddyIntent {
  BuddyIntent._();
  static const lifePartner = 'life_partner';
  static const business = 'business';
  static const friend = 'friend';
  static const travel = 'travel';
  static const spiritual = 'spiritual';

  static const all = [lifePartner, business, friend, travel, spiritual];

  static String label(String key) => switch (key) {
        lifePartner => 'Life partner',
        business => 'Business partner',
        friend => 'Friend',
        travel => 'Travel buddy',
        spiritual => 'Satsang buddy',
        _ => 'Buddy',
      };

  static String description(String key) => switch (key) {
        lifePartner => 'Someone to build a life and family with',
        business => 'A co-founder or partner you can trust',
        friend => 'Good company, real conversations',
        travel => 'Trips, treks and yatras together',
        spiritual => 'Satsang, kirtan, seva and temple visits',
        _ => '',
      };
}

/// The signed-in user's own buddy profile.
class BuddyProfile {
  final String displayName;
  final String bio;
  final List<String> intents;
  final String? gender;
  final String interestedIn;
  final String? city;
  final List<String> languages;
  final String? photoUrl;
  final bool showNearby;
  final bool isActive;
  final bool hasLocation;

  const BuddyProfile({
    required this.displayName,
    this.bio = '',
    this.intents = const [],
    this.gender,
    this.interestedIn = 'any',
    this.city,
    this.languages = const [],
    this.photoUrl,
    this.showNearby = true,
    this.isActive = true,
    this.hasLocation = false,
  });

  static BuddyProfile tryParseOr(dynamic v, BuddyProfile fallback) {
    final m = _map(v);
    return m == null ? fallback : BuddyProfile.fromJson(m);
  }

  factory BuddyProfile.fromJson(Map<String, dynamic> j) => BuddyProfile(
        displayName: _str(j['displayName'] ?? j['display_name'], 'You'),
        bio: _str(j['bio']),
        intents: _strList(j['intents']).where(BuddyIntent.all.contains).toList(),
        gender: _strOrNull(j['gender']),
        interestedIn: _str(j['interestedIn'] ?? j['interested_in'], 'any'),
        city: _strOrNull(j['city']),
        languages: _strList(j['languages']),
        photoUrl: _strOrNull(j['photoUrl'] ?? j['photo_url']),
        showNearby: _bool(j['showNearby'] ?? j['show_nearby'], true),
        isActive: _bool(j['isActive'] ?? j['is_active'], true),
        hasLocation: _bool(j['hasLocation']) || (j['lat'] != null && j['lng'] != null),
      );

  Map<String, dynamic> toJson() => {
        'displayName': displayName,
        'bio': bio,
        'intents': intents,
        'gender': gender,
        'interestedIn': interestedIn,
        'city': city,
        'languages': languages,
        if (photoUrl != null) 'photoUrl': photoUrl,
        'showNearby': showNearby,
        'isActive': isActive,
      };

  BuddyProfile copyWith({bool? isActive, bool? showNearby, bool? hasLocation}) => BuddyProfile(
        displayName: displayName,
        bio: bio,
        intents: intents,
        gender: gender,
        interestedIn: interestedIn,
        city: city,
        languages: languages,
        photoUrl: photoUrl,
        showNearby: showNearby ?? this.showNearby,
        isActive: isActive ?? this.isActive,
        hasLocation: hasLocation ?? this.hasLocation,
      );
}

/// 403 BANNED: the user's buddy profile was suspended after review.
class BuddyBannedException extends BackendException {
  const BuddyBannedException(super.message, {super.statusCode});
}

/// 429 RATE_LIMITED: too many messages / requests in a short time.
class BuddyRateLimitedException extends BackendException {
  const BuddyRateLimitedException(super.message, {super.statusCode});
}

/// Why someone can't use buddies yet.
enum BuddyGate { none, loginRequired, noKundli, under18, banned }

/// Result of GET /buddy/profile.
class BuddyStatus {
  final BuddyProfile? profile;
  final bool eligible;
  final BuddyGate gate;
  final int? age;
  final int quizAnswered;
  final int quizTotal;

  const BuddyStatus({
    this.profile,
    required this.eligible,
    this.gate = BuddyGate.none,
    this.age,
    this.quizAnswered = 0,
    this.quizTotal = 50,
  });

  static const loggedOut = BuddyStatus(eligible: false, gate: BuddyGate.loginRequired);

  factory BuddyStatus.fromJson(Map<String, dynamic> j) {
    final reason = _str(j['reason']).toUpperCase();
    final p = _map(j['profile']);
    // Suspended after review: wins over everything else, whatever eligible says.
    final banned = reason == 'BANNED' || _bool(j['banned']) || _bool(p?['banned']);
    final eligible = _bool(j['eligible']) && !banned;
    final gate = switch (banned ? 'BANNED' : reason) {
      'BANNED' => BuddyGate.banned,
      'NO_KUNDLI' => BuddyGate.noKundli,
      'UNDER_18' => BuddyGate.under18,
      'LOGIN_REQUIRED' => BuddyGate.loginRequired,
      _ => eligible ? BuddyGate.none : BuddyGate.noKundli,
    };
    return BuddyStatus(
      profile: p == null ? null : BuddyProfile.fromJson(p),
      eligible: eligible && gate == BuddyGate.none,
      gate: eligible ? BuddyGate.none : gate,
      age: _int(j['age']),
      quizAnswered: _int(j['quizAnswered']) ?? 0,
      quizTotal: _int(j['quizTotal']) ?? 50,
    );
  }

  static const bannedStatus = BuddyStatus(eligible: false, gate: BuddyGate.banned);

  bool get hasProfile => profile != null;
  bool get isActive => profile?.isActive ?? false;
  bool get isBanned => gate == BuddyGate.banned;
  bool get quizComplete => quizAnswered >= quizTotal;

  BuddyStatus copyWith({BuddyProfile? profile, int? quizAnswered}) => BuddyStatus(
        profile: profile ?? this.profile,
        eligible: eligible,
        gate: gate,
        age: age,
        quizAnswered: quizAnswered ?? this.quizAnswered,
        quizTotal: quizTotal,
      );
}

/// My relationship with a candidate, if any.
class BuddyConnectionRef {
  final int id;
  final String status; // pending | accepted | declined | cancelled
  final String direction; // outgoing | incoming

  const BuddyConnectionRef({required this.id, required this.status, required this.direction});

  static BuddyConnectionRef? tryParse(dynamic v) {
    final j = _map(v);
    final id = _int(j?['id']);
    if (j == null || id == null) return null;
    return BuddyConnectionRef(
      id: id,
      status: _str(j['status'], 'pending'),
      direction: _str(j['direction'], 'outgoing'),
    );
  }

  bool get isPending => status == 'pending';
  bool get isAccepted => status == 'accepted';
  bool get isIncoming => direction == 'incoming';
}

/// Another person as shown in Discover / Nearby / Profile. Never contains their
/// birth details, chart or answers: only the score and short highlights.
class BuddyCandidate {
  final int userId;
  final String displayName;
  final int? age;
  final String? city;
  final int? distanceKm;
  final String? photoUrl;
  final List<String> intents;
  final String bio;
  final List<String> languages;
  final int score;
  final int kundliScore;
  final int mindsetScore;
  final int distanceScore;
  final List<String> highlights;
  final int sharedAnswers;
  final int agreeAnswers;
  final BuddyConnectionRef? connection;

  const BuddyCandidate({
    required this.userId,
    required this.displayName,
    this.age,
    this.city,
    this.distanceKm,
    this.photoUrl,
    this.intents = const [],
    this.bio = '',
    this.languages = const [],
    this.score = 0,
    this.kundliScore = 0,
    this.mindsetScore = 0,
    this.distanceScore = 0,
    this.highlights = const [],
    this.sharedAnswers = 0,
    this.agreeAnswers = 0,
    this.connection,
  });

  static BuddyCandidate? tryParse(dynamic v) {
    final j = _map(v);
    final id = _int(j?['userId'] ?? j?['user_id'] ?? j?['id']);
    if (j == null || id == null) return null;
    final b = _map(j['breakdown']) ?? const {};
    return BuddyCandidate(
      userId: id,
      displayName: _str(j['displayName'] ?? j['display_name'], 'Buddy'),
      age: _int(j['age']),
      city: _strOrNull(j['city']),
      distanceKm: _int(j['distanceKm']),
      photoUrl: _strOrNull(j['photoUrl'] ?? j['photo_url']),
      intents: _strList(j['intents']).where(BuddyIntent.all.contains).toList(),
      bio: _str(j['bio']),
      languages: _strList(j['languages']),
      score: _pct(j['score']),
      kundliScore: _pct(b['kundli']),
      mindsetScore: _pct(b['mindset']),
      distanceScore: _pct(b['distance']),
      highlights: _strList(j['highlights']).take(4).toList(),
      sharedAnswers: _int(j['sharedAnswers']) ?? 0,
      agreeAnswers: _int(j['agreeAnswers']) ?? 0,
      connection: BuddyConnectionRef.tryParse(j['connection']),
    );
  }

  /// "~4 km" (never exact coordinates).
  String? get distanceLabel {
    final d = distanceKm;
    if (d == null) return null;
    if (d <= 1) return '< 1 km';
    return '~$d km';
  }

  String get firstName {
    final p = displayName.trim().split(RegExp(r'\s+'));
    return p.isEmpty || p.first.isEmpty ? displayName : p.first;
  }

  String get subtitle => [
        if (age != null) '$age',
        if (city != null) city!,
      ].join(' · ');
}

/// Plain-English label for a 0-100 score.
String buddyScoreLabel(int score) {
  if (score >= 85) return 'Excellent match';
  if (score >= 70) return 'Great match';
  if (score >= 55) return 'Good match';
  if (score >= 40) return 'Fair match';
  return 'Low match';
}

class BuddyMessage {
  final int id;
  final String body;
  final DateTime createdAt;
  final bool mine;

  /// Local only: sent optimistically, waiting for the server.
  final bool pending;

  /// Local only: the send failed.
  final bool failed;

  const BuddyMessage({
    required this.id,
    required this.body,
    required this.createdAt,
    required this.mine,
    this.pending = false,
    this.failed = false,
  });

  static BuddyMessage? tryParse(dynamic v) {
    final j = _map(v);
    if (j == null) return null;
    final body = _str(j['body']);
    if (body.isEmpty) return null;
    return BuddyMessage(
      id: _int(j['id']) ?? 0,
      body: body,
      createdAt: _date(j['createdAt'] ?? j['created_at']) ?? DateTime.now(),
      mine: _bool(j['mine']),
    );
  }
}

class BuddyConnection {
  final int id;
  final String intent;
  final String status;
  final String? message;
  final DateTime? createdAt;
  final BuddyCandidate other;
  final BuddyMessage? lastMessage;
  final int unread;

  const BuddyConnection({
    required this.id,
    required this.intent,
    required this.status,
    this.message,
    this.createdAt,
    required this.other,
    this.lastMessage,
    this.unread = 0,
  });

  static BuddyConnection? tryParse(dynamic v) {
    final j = _map(v);
    final id = _int(j?['id']);
    final other = BuddyCandidate.tryParse(j?['other']);
    if (j == null || id == null || other == null) return null;
    return BuddyConnection(
      id: id,
      intent: _str(j['intent'], BuddyIntent.friend),
      status: _str(j['status'], 'pending'),
      message: _strOrNull(j['message']),
      createdAt: _date(j['createdAt'] ?? j['created_at']),
      other: other,
      lastMessage: BuddyMessage.tryParse(j['lastMessage']),
      unread: _int(j['unread']) ?? 0,
    );
  }

  bool get isAccepted => status == 'accepted';
}

class BuddyConnections {
  final List<BuddyConnection> incoming;
  final List<BuddyConnection> outgoing;
  final List<BuddyConnection> buddies;

  const BuddyConnections({this.incoming = const [], this.outgoing = const [], this.buddies = const []});

  static const empty = BuddyConnections();

  factory BuddyConnections.fromJson(Map<String, dynamic> j) {
    List<BuddyConnection> parse(dynamic v) =>
        v is List ? v.map(BuddyConnection.tryParse).whereType<BuddyConnection>().toList() : const [];
    return BuddyConnections(
      incoming: parse(j['incoming']),
      outgoing: parse(j['outgoing']),
      buddies: parse(j['buddies']),
    );
  }

  int get unread => buddies.fold(0, (s, c) => s + c.unread);

  BuddyConnections without(int userId) => BuddyConnections(
        incoming: incoming.where((c) => c.other.userId != userId).toList(),
        outgoing: outgoing.where((c) => c.other.userId != userId).toList(),
        buddies: buddies.where((c) => c.other.userId != userId).toList(),
      );
}

class BuddyChatPage {
  final List<BuddyMessage> messages;
  final BuddyConnection? connection;
  const BuddyChatPage(this.messages, this.connection);
}

enum BuddyLocationResult { updated, denied, deniedForever, serviceDisabled, failed }

/// A rounded position. The server rounds again to 2 decimals (~1 km).
typedef BuddyLocationFix = ({double lat, double lng});

const buddyReportReasons = <String, String>{
  'fake': 'Fake profile',
  'harassment': 'Harassment or bullying',
  'inappropriate': 'Inappropriate messages or photos',
  'scam': 'Asking for money or a scam',
  'underage': 'Looks under 18',
  'other': 'Something else',
};

// ============================================================================
// Service
// ============================================================================

/// Buddy profile, discovery, nearby, connections and chat (/api/buddy).
/// Registered in main.dart; read it with `context.read<BuddyService>()`.
class BuddyService extends ChangeNotifier {
  final BackendService backend;
  BuddyService(this.backend) {
    backend.addListener(_onBackendChanged);
  }

  /// How often the nav badge refreshes while the app is in the foreground.
  static const badgeRefreshInterval = Duration(minutes: 3);

  /// Calls to [refreshBadge] closer together than this are ignored (unless forced).
  static const badgeMinGap = Duration(seconds: 30);

  /// Tests can move time forward for the badge throttle.
  @visibleForTesting
  DateTime Function() clock = DateTime.now;

  bool _disposed = false;
  Timer? _badgeTimer;
  DateTime? _lastBadgeRefresh;
  Future<void>? _badgeFuture;
  Future<BuddyConnections>? _connectionsFuture;

  /// Tests can replace the device location lookup.
  @visibleForTesting
  Future<BuddyLocationFix?> Function()? debugLocator;

  BuddyStatus? _status;
  bool _statusLoading = false;
  String? _statusError;
  Future<BuddyStatus>? _statusFuture;
  String? _statusUserKey;

  BuddyConnections _connections = BuddyConnections.empty;
  bool _connectionsLoaded = false;

  List<BuddyCandidate>? _topMatches;

  /// People blocked/reported this session; hidden everywhere immediately.
  final Set<int> _hidden = {};

  BuddyStatus? get status => _status;
  bool get statusLoading => _statusLoading;
  String? get statusError => _statusError;
  BuddyProfile? get profile => _status?.profile;
  bool get hasActiveProfile => _status?.profile?.isActive ?? false;

  BuddyConnections get connections => _connections;
  bool get connectionsLoaded => _connectionsLoaded;
  int get incomingCount => _connections.incoming.length;
  int get unreadCount => _connections.unread;

  /// For the bottom-nav / segmented badge: new requests + unread messages.
  int get badgeCount => incomingCount + unreadCount;

  List<BuddyCandidate>? get topMatches => _topMatches;

  bool isHidden(int userId) => _hidden.contains(userId);

  String get _userKey => backend.isAuthenticated ? '${backend.user?['id'] ?? backend.token}' : '';

  /// Returns true if cached data belonged to another account and was dropped.
  bool _resetIfUserChanged() {
    final key = _userKey;
    final changed = _statusUserKey != null && _statusUserKey != key;
    if (changed) {
      _status = null;
      _statusFuture = null;
      _statusError = null;
      _connections = BuddyConnections.empty;
      _connectionsLoaded = false;
      _connectionsFuture = null;
      _topMatches = null;
      _lastBadgeRefresh = null;
      _hidden.clear();
    }
    _statusUserKey = key;
    return changed;
  }

  /// Log in / log out / account switch: drop the old user's data (and badge)
  /// straight away, then refresh for the new user.
  void _onBackendChanged() {
    if (_disposed || _statusUserKey == null || _statusUserKey == _userKey) return;
    // Defer: BackendService may notify while widgets are building.
    scheduleMicrotask(() {
      if (_disposed || !_resetIfUserChanged()) return;
      notifyListeners();
      if (backend.isAuthenticated && _badgeTimer != null) unawaited(refreshBadge(force: true));
    });
  }

  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _badgeTimer?.cancel();
    backend.removeListener(_onBackendChanged);
    super.dispose();
  }

  // ------------------------------------------------------------------ badge

  /// Refreshes [badgeCount] (incoming requests + unread messages). Cheap:
  /// skipped for guests / people without a buddy profile, de-duplicated while
  /// in flight and throttled to one call per [badgeMinGap] unless [force].
  /// Never throws.
  Future<void> refreshBadge({bool force = false}) {
    if (_disposed) return Future.value();
    _resetIfUserChanged();
    if (!backend.isAuthenticated) return Future.value();
    final inFlight = _badgeFuture;
    if (inFlight != null) return inFlight;
    final now = clock();
    final last = _lastBadgeRefresh;
    if (!force && last != null && now.difference(last) < badgeMinGap) return Future.value();
    _lastBadgeRefresh = now;
    return _badgeFuture = () async {
      try {
        final st = await loadStatus();
        if (!st.eligible || !st.hasProfile) return;
        await loadConnections();
      } catch (_) {
        // Badge is best-effort; keep the last known count.
      }
    }()
        .whenComplete(() => _badgeFuture = null);
  }

  /// Starts the foreground badge refresh (now + every [badgeRefreshInterval]).
  void startBadgeUpdates({Duration interval = badgeRefreshInterval}) {
    if (_disposed) return;
    _badgeTimer?.cancel();
    _badgeTimer = Timer.periodic(interval, (_) => refreshBadge());
    unawaited(refreshBadge());
  }

  /// Stops the periodic refresh (app in background / home screen gone).
  void stopBadgeUpdates() {
    _badgeTimer?.cancel();
    _badgeTimer = null;
  }

  @visibleForTesting
  bool get badgeUpdatesRunning => _badgeTimer?.isActive ?? false;

  static const bannedMessage =
      'Your buddy profile has been suspended after review. Contact support if you think this is a mistake.';
  static const slowDownMessage = 'Slow down a little. Please wait a moment and try again.';

  static String errorText(Object e) {
    if (e is BuddyBannedException) return bannedMessage;
    if (e is BuddyRateLimitedException) return slowDownMessage;
    if (e is BackendException) {
      if (e.statusCode == 401) return 'Please log in to use buddies.';
      if (e.statusCode == 429) return slowDownMessage;
      if (e.message.trim().isNotEmpty) return e.message;
    }
    return 'Could not reach the server. Please check your connection.';
  }

  /// All buddy calls go through here: turns 403 BANNED and 429 RATE_LIMITED
  /// into typed exceptions, and a ban flips the status so every screen (and
  /// the nearby watcher / badge) stops straight away.
  Future<Map<String, dynamic>> _api(String method, String path, {Map<String, dynamic>? body}) async {
    try {
      return await backend.api(method, path, body: body);
    } on BackendException catch (e) {
      final code = backend.lastErrorCode;
      if (e.statusCode == 403 && code == 'BANNED') {
        _markBanned();
        throw BuddyBannedException(e.message, statusCode: e.statusCode);
      }
      if (e.statusCode == 429) throw BuddyRateLimitedException(e.message, statusCode: e.statusCode);
      rethrow;
    }
  }

  void _markBanned() {
    if (_status?.isBanned ?? false) return;
    _status = BuddyStatus.bannedStatus;
    _topMatches = null;
    _connections = BuddyConnections.empty;
    _changedConnections();
  }

  // ---------------------------------------------------------------- profile

  /// GET /buddy/profile. Shares one in-flight request; cached unless [force].
  Future<BuddyStatus> loadStatus({bool force = false}) {
    _resetIfUserChanged();
    if (!backend.isAuthenticated) {
      _status = BuddyStatus.loggedOut;
      _statusError = null;
      return Future.value(_status);
    }
    if (!force && _status != null && _status!.gate != BuddyGate.loginRequired) return Future.value(_status);
    return _statusFuture ??= _fetchStatus().whenComplete(() => _statusFuture = null);
  }

  Future<BuddyStatus> _fetchStatus() async {
    _statusLoading = true;
    _statusError = null;
    notifyListeners();
    try {
      final res = await _api('GET', '/buddy/profile');
      _status = BuddyStatus.fromJson(res);
      return _status!;
    } on BackendException catch (e) {
      if (e.statusCode == 401) {
        _status = BuddyStatus.loggedOut;
        return _status!;
      }
      if (e is BuddyBannedException) return _status ?? BuddyStatus.bannedStatus;
      _statusError = errorText(e);
      rethrow;
    } catch (e) {
      _statusError = errorText(e);
      rethrow;
    } finally {
      _statusLoading = false;
      notifyListeners();
    }
  }

  /// PUT /buddy/profile.
  Future<BuddyProfile> saveProfile(BuddyProfile p) async {
    final res = await _api('PUT', '/buddy/profile', body: p.toJson());
    final saved = BuddyProfile.tryParseOr(res['profile'], p);
    _status = (_status ?? const BuddyStatus(eligible: true)).copyWith(profile: saved);
    _topMatches = null;
    notifyListeners();
    return saved;
  }

  /// Pause (DELETE /buddy/profile): hides me from everyone until resumed.
  Future<void> pauseProfile() async {
    await _api('DELETE', '/buddy/profile');
    final p = profile;
    if (p != null) _status = _status!.copyWith(profile: p.copyWith(isActive: false));
    notifyListeners();
  }

  Future<void> resumeProfile() async {
    final p = profile;
    if (p == null) return;
    await saveProfile(p.copyWith(isActive: true));
  }

  /// Keep the quiz count fresh after the user answers questions elsewhere.
  void setQuizAnswered(int count) {
    if (_status == null) return;
    _status = _status!.copyWith(quizAnswered: count);
    notifyListeners();
  }

  // --------------------------------------------------------------- location

  /// Asks for location permission (only call this when the user opts in).
  Future<BuddyLocationResult> ensureLocationPermission() async {
    if (debugLocator != null) return BuddyLocationResult.updated;
    try {
      if (!await Geolocator.isLocationServiceEnabled()) return BuddyLocationResult.serviceDisabled;
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) perm = await Geolocator.requestPermission();
      return switch (perm) {
        LocationPermission.always || LocationPermission.whileInUse => BuddyLocationResult.updated,
        LocationPermission.deniedForever => BuddyLocationResult.deniedForever,
        _ => BuddyLocationResult.denied,
      };
    } catch (_) {
      return BuddyLocationResult.failed;
    }
  }

  Future<BuddyLocationFix?> _locate() async {
    if (debugLocator != null) return debugLocator!();
    final pos = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.low, timeLimit: Duration(seconds: 15)),
    );
    return (lat: pos.latitude, lng: pos.longitude);
  }

  /// Gets an approximate position and sends it rounded (2 decimals, ~1 km).
  Future<BuddyLocationResult> updateLocation({String? city}) async {
    final perm = await ensureLocationPermission();
    if (perm != BuddyLocationResult.updated) return perm;
    BuddyLocationFix? fix;
    try {
      fix = await _locate().timeout(const Duration(seconds: 20));
    } catch (_) {
      fix = null;
    }
    if (fix == null) return BuddyLocationResult.failed;
    double r(double v) => (v * 100).roundToDouble() / 100;
    try {
      await _api('PUT', '/buddy/location', body: {
        'lat': r(fix.lat),
        'lng': r(fix.lng),
        if (city != null && city.trim().isNotEmpty) 'city': city.trim(),
      });
    } catch (_) {
      return BuddyLocationResult.failed;
    }
    final p = profile;
    if (p != null) _status = _status!.copyWith(profile: p.copyWith(hasLocation: true));
    _topMatches = null;
    notifyListeners();
    return BuddyLocationResult.updated;
  }

  // -------------------------------------------------------------- discovery

  List<BuddyCandidate> _candidates(Map<String, dynamic> res) {
    final raw = res['candidates'];
    if (raw is! List) return const [];
    return raw
        .map(BuddyCandidate.tryParse)
        .whereType<BuddyCandidate>()
        .where((c) => !_hidden.contains(c.userId))
        .toList();
  }

  Future<List<BuddyCandidate>> discover({String intent = 'all', int? maxKm, int limit = 20}) async {
    final q = <String>['intent=${Uri.encodeQueryComponent(intent)}', 'limit=$limit', if (maxKm != null) 'maxKm=$maxKm'];
    final res = await _api('GET', '/buddy/discover?${q.join('&')}');
    final list = _candidates(res);
    if (intent == 'all' && maxKm == null) {
      _topMatches = list.take(6).toList();
      notifyListeners();
    }
    return list;
  }

  /// Top matches for the Home rail (cached; [force] refetches).
  Future<List<BuddyCandidate>> loadTopMatches({bool force = false}) async {
    if (!force && _topMatches != null) return _topMatches!;
    final list = await discover();
    return list.take(6).toList();
  }

  Future<List<BuddyCandidate>> nearby() async => _candidates(await _api('GET', '/buddy/nearby'));

  Future<BuddyCandidate?> user(int userId) async {
    final res = await _api('GET', '/buddy/user/$userId');
    return BuddyCandidate.tryParse(res['candidate']);
  }

  // ------------------------------------------------------------ connections

  void _dropFromTop(int userId) {
    if (_topMatches == null) return;
    _topMatches = _topMatches!.where((c) => c.userId != userId).toList();
  }

  /// Sends a request (or accepts theirs if they already asked me).
  Future<BuddyConnectionRef?> connect(int userId, String intent, {String? message}) async {
    final res = await _api('POST', '/buddy/connect', body: {
      'userId': userId,
      'intent': intent,
      if (message != null && message.trim().isNotEmpty) 'message': message.trim(),
    });
    _dropFromTop(userId);
    unawaited(loadConnections(fresh: true).catchError((_) => _connections));
    return BuddyConnectionRef.tryParse(res['connection']);
  }

  Future<void> _connectionAction(int id, String action) async {
    try {
      await _api('POST', '/buddy/connections/$id/$action');
    } on BackendException catch (e) {
      // 404 / 409: the other person already cancelled, or it was answered on
      // another device. Refresh so the stale card disappears.
      if (e.statusCode == 404 || e.statusCode == 409) {
        unawaited(loadConnections(fresh: true).catchError((_) => _connections));
      }
      rethrow;
    }
    // Optimistic local update so the lists react instantly.
    final c = _connections;
    final moved = [...c.incoming, ...c.outgoing].where((x) => x.id == id).toList();
    _connections = BuddyConnections(
      incoming: c.incoming.where((x) => x.id != id).toList(),
      outgoing: c.outgoing.where((x) => x.id != id).toList(),
      buddies: [
        ...c.buddies,
        if (action == 'accept')
          for (final m in moved)
            BuddyConnection(id: m.id, intent: m.intent, status: 'accepted', other: m.other, createdAt: m.createdAt),
      ],
    );
    _changedConnections();
    unawaited(loadConnections(fresh: true).catchError((_) => _connections));
  }

  Future<void> accept(int connectionId) => _connectionAction(connectionId, 'accept');
  Future<void> decline(int connectionId) => _connectionAction(connectionId, 'decline');
  Future<void> cancel(int connectionId) => _connectionAction(connectionId, 'cancel');

  /// GET /buddy/connections. Concurrent calls share one request; [fresh]
  /// always starts a new one (used right after a local change).
  Future<BuddyConnections> loadConnections({bool fresh = false}) {
    _resetIfUserChanged();
    if (!backend.isAuthenticated) return Future.value(_connections);
    final inFlight = _connectionsFuture;
    if (inFlight != null && !fresh) return inFlight;
    late final Future<BuddyConnections> f;
    f = _fetchConnections().whenComplete(() {
      if (identical(_connectionsFuture, f)) _connectionsFuture = null;
    });
    return _connectionsFuture = f;
  }

  /// Bumped on every local change to the lists, so a response that was
  /// requested before the change can't undo it.
  int _connGen = 0;

  void _changedConnections() {
    _connGen++;
    notifyListeners();
  }

  Future<BuddyConnections> _fetchConnections() async {
    final key = _userKey;
    final gen = _connGen;
    final res = await _api('GET', '/buddy/connections');
    // The account changed (or the lists were edited locally) while this was
    // in flight: don't let stale data overwrite the current state.
    if (_disposed || key != _userKey || gen != _connGen) return _connections;
    var c = BuddyConnections.fromJson(res);
    for (final id in _hidden) {
      c = c.without(id);
    }
    _connections = c;
    _connectionsLoaded = true;
    _lastBadgeRefresh = clock();
    notifyListeners();
    return c;
  }

  /// Locally clears the unread badge for a chat once it's opened.
  void markRead(int connectionId) {
    final c = _connections;
    if (!c.buddies.any((b) => b.id == connectionId && b.unread > 0)) return;
    _connections = BuddyConnections(
      incoming: c.incoming,
      outgoing: c.outgoing,
      buddies: [
        for (final b in c.buddies)
          b.id == connectionId
              ? BuddyConnection(
                  id: b.id,
                  intent: b.intent,
                  status: b.status,
                  message: b.message,
                  createdAt: b.createdAt,
                  other: b.other,
                  lastMessage: b.lastMessage,
                )
              : b,
      ],
    );
    _changedConnections();
  }

  // ------------------------------------------------------------------- chat

  Future<BuddyChatPage> fetchChat(int connectionId, {int? after}) async {
    final res = await _api('GET', '/buddy/chat/$connectionId${after != null && after > 0 ? '?after=$after' : ''}');
    final raw = res['messages'];
    final msgs = raw is List ? raw.map(BuddyMessage.tryParse).whereType<BuddyMessage>().toList() : <BuddyMessage>[];
    return BuddyChatPage(msgs, BuddyConnection.tryParse(res['connection']));
  }

  Future<BuddyMessage> sendMessage(int connectionId, String body) async {
    final text = body.trim();
    final res = await _api('POST', '/buddy/chat/$connectionId', body: {'body': text});
    return BuddyMessage.tryParse(res['message']) ??
        BuddyMessage(id: 0, body: text, createdAt: DateTime.now(), mine: true);
  }

  /// Polls a chat every [interval] while it's open. Call [BuddyChatPoller.start]
  /// when the chat is visible and [BuddyChatPoller.dispose] when it closes.
  BuddyChatPoller chatPoller(int connectionId, {Duration interval = const Duration(seconds: 4)}) =>
      BuddyChatPoller(this, connectionId, interval: interval);

  // ----------------------------------------------------------------- safety

  void _hide(int userId) {
    _hidden.add(userId);
    _connections = _connections.without(userId);
    _dropFromTop(userId);
    _changedConnections();
  }

  Future<void> block(int userId) async {
    await _api('POST', '/buddy/block', body: {'userId': userId});
    _hide(userId);
  }

  /// Reporting also blocks.
  Future<void> report(int userId, String reason, {String? details}) async {
    await _api('POST', '/buddy/report', body: {
      'userId': userId,
      'reason': buddyReportReasons.containsKey(reason) ? reason : 'other',
      if (details != null && details.trim().isNotEmpty) 'details': details.trim(),
    });
    _hide(userId);
  }
}

enum BuddySendResult { sent, failed, rateLimited }

/// Keeps a chat's messages fresh by polling `after=<last id>`.
class BuddyChatPoller extends ChangeNotifier {
  final BuddyService service;
  final int connectionId;
  final Duration interval;

  BuddyChatPoller(this.service, this.connectionId, {this.interval = const Duration(seconds: 4)});

  final List<BuddyMessage> _messages = [];
  BuddyConnection? connection;
  bool loading = true;
  String? error;
  Timer? _timer;
  bool _fetching = false;
  bool _disposed = false;
  int _tempId = -1;

  /// True once the server says this chat is gone (request cancelled, blocked,
  /// logged out). Polling stops and sending is disabled.
  bool closed = false;

  /// Highest message id received from a *poll*. Ids from our own sends are not
  /// used, so a message the other person sent just before ours is not skipped.
  int _cursor = 0;

  List<BuddyMessage> get messages => List.unmodifiable(_messages);

  bool get isPolling => _timer?.isActive ?? false;

  void start() {
    if (_disposed || closed) return;
    _timer?.cancel();
    _timer = Timer.periodic(interval, (_) => refresh());
    if (loading) refresh();
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  static bool _isGone(Object e) =>
      e is BackendException && (e.statusCode == 401 || e.statusCode == 403 || e.statusCode == 404);

  void _close(Object e) {
    closed = true;
    stop();
    error =
        e is BackendException && e.statusCode == 401 ? BuddyService.errorText(e) : 'This chat is no longer available.';
  }

  Future<void> refresh() async {
    if (_fetching || _disposed || closed) return;
    _fetching = true;
    try {
      final page = await service.fetchChat(connectionId, after: _cursor);
      if (_disposed) return;
      for (final m in page.messages) {
        if (m.id > _cursor) _cursor = m.id;
      }
      _merge(page.messages);
      connection = page.connection ?? connection;
      error = null;
      service.markRead(connectionId);
    } catch (e) {
      if (_disposed) return;
      if (_isGone(e)) {
        _close(e);
      } else if (loading) {
        error = BuddyService.errorText(e);
      }
    } finally {
      _fetching = false;
      if (!_disposed) {
        loading = false;
        notifyListeners();
      }
    }
  }

  void _merge(List<BuddyMessage> incoming) {
    for (final m in incoming) {
      if (m.id > 0 && _messages.any((x) => x.id == m.id)) continue;
      _messages.add(m);
    }
    _messages.sort((a, b) {
      final c = a.createdAt.compareTo(b.createdAt);
      return c != 0 ? c : a.id.compareTo(b.id);
    });
  }

  /// Optimistic send. On a normal failure the bubble stays with "tap to
  /// retry"; when rate limited (429) the bubble is removed so the caller can
  /// put the text back in the input (or, for a [retry], it stays failed).
  Future<BuddySendResult> send(String text, {bool keepBubbleWhenRateLimited = false}) async {
    final body = text.trim();
    if (body.isEmpty || closed || _disposed) return BuddySendResult.failed;
    final temp = BuddyMessage(id: _tempId--, body: body, createdAt: DateTime.now(), mine: true, pending: true);
    _messages.add(temp);
    notifyListeners();
    try {
      final sent = await service.sendMessage(connectionId, body);
      if (_disposed) return BuddySendResult.sent;
      _messages.remove(temp);
      if (sent.id <= 0 || !_messages.any((m) => m.id == sent.id)) {
        _messages.add(BuddyMessage(
            id: sent.id > 0 ? sent.id : _tempId--, body: sent.body, createdAt: sent.createdAt, mine: true));
      }
      _merge(const []);
      notifyListeners();
      return BuddySendResult.sent;
    } catch (e) {
      if (_disposed) return BuddySendResult.failed;
      final limited = e is BuddyRateLimitedException || (e is BackendException && e.statusCode == 429);
      final i = _messages.indexOf(temp);
      if (i >= 0) {
        if (limited && !keepBubbleWhenRateLimited) {
          _messages.removeAt(i);
        } else {
          _messages[i] = BuddyMessage(id: temp.id, body: body, createdAt: temp.createdAt, mine: true, failed: true);
        }
      }
      if (_isGone(e)) _close(e);
      notifyListeners();
      return limited ? BuddySendResult.rateLimited : BuddySendResult.failed;
    }
  }

  /// Removes a failed bubble and sends it again. A second tap on the same
  /// bubble (before it rebuilds) is ignored, so it can't be sent twice.
  Future<BuddySendResult> retry(BuddyMessage failed) {
    final i = _messages.indexWhere((m) => m.id == failed.id && m.failed);
    if (i < 0 || closed) return Future.value(BuddySendResult.failed);
    _messages.removeAt(i);
    return send(failed.body, keepBubbleWhenRateLimited: true);
  }

  @override
  void dispose() {
    _disposed = true;
    stop();
    super.dispose();
  }
}
