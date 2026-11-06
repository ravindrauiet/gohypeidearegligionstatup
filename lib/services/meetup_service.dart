import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

import 'backend_service.dart';
import 'notification_service.dart';

// ============================================================================
// Satsang meetups (/api/meetups): small group events at temples and other
// public places. Models parse defensively (nothing throws on odd JSON).
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
  if (v is String) return v.toLowerCase() == 'true' || v == '1';
  return fallback;
}

Map<String, dynamic>? _map(dynamic v) {
  if (v is Map<String, dynamic>) return v;
  if (v is Map) return v.map((k, val) => MapEntry(k.toString(), val));
  return null;
}

DateTime? _date(dynamic v) => v == null ? null : DateTime.tryParse(v.toString())?.toLocal();

/// Event kinds. Keys match the backend.
class MeetupType {
  MeetupType._();
  static const aarti = 'aarti';
  static const bhajanSandhya = 'bhajan_sandhya';
  static const seva = 'seva';
  static const yoga = 'yoga';
  static const satsang = 'satsang';
  static const kirtan = 'kirtan';
  static const other = 'other';
  static const all = [aarti, bhajanSandhya, satsang, kirtan, seva, yoga, other];

  static String label(String key) => switch (key) {
        aarti => 'Aarti',
        bhajanSandhya => 'Bhajan sandhya',
        seva => 'Seva',
        yoga => 'Yoga',
        satsang => 'Satsang',
        kirtan => 'Kirtan',
        _ => 'Gathering',
      };
}

/// RSVP states (null = not going).
class MeetupRsvp {
  MeetupRsvp._();
  static const going = 'going';
  static const cancelled = 'cancelled';
  static const checkedIn = 'checked_in';
}

/// Another attendee as the server shows them: name, initials and verified
/// only. [userId] is present only in "People you met".
class MeetupPerson {
  final int? userId;
  final String displayName;
  final String initials;
  final bool verified;
  final bool canConnect;
  const MeetupPerson({this.userId, required this.displayName, required this.initials, this.verified = false, this.canConnect = false});

  static MeetupPerson? tryParse(dynamic v) {
    final m = _map(v);
    if (m == null) return null;
    final name = _str(m['displayName'], 'Member');
    return MeetupPerson(
      userId: _int(m['userId']),
      displayName: name,
      initials: _str(m['initials'], name.isEmpty ? '?' : name[0].toUpperCase()),
      verified: _bool(m['verified']),
      canConnect: _bool(m['canConnect']),
    );
  }
}

class MeetupHost {
  final String displayName;
  final bool verified;
  const MeetupHost({required this.displayName, this.verified = false});
}

class Meetup {
  final int id;
  final String title;
  final String type;
  final String status; // pending | approved | rejected | cancelled | completed
  final String phase; // upcoming | live | ended
  final String venueName;
  final String? city;
  final String address;
  final DateTime startsAt;
  final DateTime endsAt;
  final int? distanceKm;
  final int capacity;
  final int goingCount;
  final int spotsLeft;
  final bool womenOnly;
  final bool official;
  final MeetupHost? host;
  final bool isHost;
  final String? myStatus;
  final List<MeetupPerson>? attendees;
  // Detail only
  final String description;
  final String? mapsUrl;
  final DateTime? checkinOpensAt;
  final bool checkinOpen;
  final DateTime? checkedInAt;
  final int coinsForCheckin;
  final String? checkinCode;
  final int checkedInCount;
  final List<MeetupPerson>? peopleYouMet;

  const Meetup({
    required this.id,
    required this.title,
    this.type = MeetupType.satsang,
    this.status = 'approved',
    this.phase = 'upcoming',
    required this.venueName,
    this.city,
    this.address = '',
    required this.startsAt,
    required this.endsAt,
    this.distanceKm,
    this.capacity = 0,
    this.goingCount = 0,
    this.spotsLeft = 0,
    this.womenOnly = false,
    this.official = true,
    this.host,
    this.isHost = false,
    this.myStatus,
    this.attendees,
    this.description = '',
    this.mapsUrl,
    this.checkinOpensAt,
    this.checkinOpen = false,
    this.checkedInAt,
    this.coinsForCheckin = 100,
    this.checkinCode,
    this.checkedInCount = 0,
    this.peopleYouMet,
  });

  bool get isGoing => myStatus == MeetupRsvp.going || myStatus == MeetupRsvp.checkedIn;
  bool get isCheckedIn => myStatus == MeetupRsvp.checkedIn;
  bool get isCancelled => status == 'cancelled';
  bool get isPending => status == 'pending';
  bool get isApproved => status == 'approved';
  bool get isEnded => phase == 'ended';
  bool get hasStarted => phase != 'upcoming';
  bool get isFull => spotsLeft <= 0;

  /// Check-in window (30 min before start until the end), from the local clock.
  bool checkinWindowOpen(DateTime now) =>
      isApproved && !now.isBefore(checkinOpensAt ?? startsAt.subtract(const Duration(minutes: 30))) && !now.isAfter(endsAt);

  static Meetup? tryParse(dynamic v) {
    final m = _map(v);
    if (m == null) return null;
    final id = _int(m['id']);
    final start = _date(m['startsAt']);
    final end = _date(m['endsAt']);
    if (id == null || start == null || end == null) return null;
    final h = _map(m['host']);
    List<MeetupPerson>? people(dynamic raw) =>
        raw is List ? raw.map(MeetupPerson.tryParse).whereType<MeetupPerson>().toList() : null;
    final capacity = _int(m['capacity']) ?? 0;
    final going = _int(m['goingCount']) ?? 0;
    return Meetup(
      id: id,
      title: _str(m['title'], 'Satsang'),
      type: _str(m['type'], MeetupType.satsang),
      status: _str(m['status'], 'approved'),
      phase: _str(m['phase'], 'upcoming'),
      venueName: _str(m['venueName'], 'Venue'),
      city: _strOrNull(m['city']),
      address: _str(m['address']),
      startsAt: start,
      endsAt: end,
      distanceKm: _int(m['distanceKm']),
      capacity: capacity,
      goingCount: going,
      spotsLeft: _int(m['spotsLeft']) ?? (capacity - going).clamp(0, capacity),
      womenOnly: _bool(m['womenOnly']),
      official: _bool(m['official'], h == null),
      host: h == null ? null : MeetupHost(displayName: _str(h['displayName'], 'Member'), verified: _bool(h['verified'])),
      isHost: _bool(m['isHost']),
      myStatus: _strOrNull(m['myStatus']),
      attendees: people(m['attendees']),
      description: _str(m['description']),
      mapsUrl: _strOrNull(m['mapsUrl']),
      checkinOpensAt: _date(m['checkinOpensAt']),
      checkinOpen: _bool(m['checkinOpen']),
      checkedInAt: _date(m['checkedInAt']),
      coinsForCheckin: _int(m['coinsForCheckin']) ?? 100,
      checkinCode: _strOrNull(m['checkinCode']),
      checkedInCount: _int(m['checkedInCount']) ?? 0,
      peopleYouMet: people(m['peopleYouMet']),
    );
  }

  static List<Meetup> listFrom(dynamic raw) =>
      raw is List ? raw.map(Meetup.tryParse).whereType<Meetup>().toList() : const [];
}

class MeetupList {
  /// 'location' (sorted by distance within [radiusKm]), 'city' or 'none'.
  final String origin;
  final int? radiusKm;
  final List<Meetup> meetups;
  const MeetupList({this.origin = 'none', this.radiusKm, this.meetups = const []});
  bool get byLocation => origin == 'location';
}

class MyMeetups {
  final List<Meetup> upcoming;
  final List<Meetup> past;
  final List<Meetup> hosting;
  const MyMeetups({this.upcoming = const [], this.past = const [], this.hosting = const []});
  bool get isEmpty => upcoming.isEmpty && past.isEmpty && hosting.isEmpty;
}

class ProposeStatus {
  final bool canPropose;

  /// LOGIN_REQUIRED, NOT_VERIFIED, RATE_LIMITED, UNDER_18, NO_BIRTH_DETAILS, BANNED.
  final String? reason;
  final int remainingThisWeek;
  final bool canHostWomenOnly;
  const ProposeStatus({required this.canPropose, this.reason, this.remainingThisWeek = 0, this.canHostWomenOnly = false});
}

/// What a host fills in to propose an event.
class MeetupDraft {
  final String title;
  final String type;
  final String description;
  final String? templeId;
  final String venueName;
  final String address;
  final String city;
  final double? lat;
  final double? lng;
  final DateTime startsAt;
  final DateTime endsAt;
  final int capacity;
  final bool womenOnly;

  const MeetupDraft({
    required this.title,
    required this.type,
    this.description = '',
    this.templeId,
    required this.venueName,
    required this.address,
    required this.city,
    this.lat,
    this.lng,
    required this.startsAt,
    required this.endsAt,
    required this.capacity,
    this.womenOnly = false,
  });

  Map<String, dynamic> toJson() => {
        'title': title.trim(),
        'type': type,
        'description': description.trim(),
        if (templeId != null) 'templeId': templeId,
        'venueName': venueName.trim(),
        'address': address.trim(),
        'city': city.trim(),
        if (lat != null && lng != null) 'lat': lat,
        if (lat != null && lng != null) 'lng': lng,
        'startsAt': startsAt.toUtc().toIso8601String(),
        'endsAt': endsAt.toUtc().toIso8601String(),
        'capacity': capacity,
        'womenOnly': womenOnly,
      };
}

/// A famous temple the host can pick as the venue (from /api/trips/temples).
class MeetupTemple {
  final String id;
  final String name;
  final String city;
  final String state;
  const MeetupTemple({required this.id, required this.name, required this.city, required this.state});
}

class MeetupCheckin {
  final int coinsAwarded;
  final int? balance;
  final Meetup? meetup;

  /// The raw response (for `showCoinsFromResponse`).
  final Map<String, dynamic> raw;
  const MeetupCheckin({required this.coinsAwarded, this.balance, this.meetup, this.raw = const {}});
}

/// Why the device location could not be used for check-in.
enum MeetupLocationIssue { serviceDisabled, denied, deniedForever, unavailable }

class MeetupLocationException implements Exception {
  final MeetupLocationIssue issue;
  const MeetupLocationException(this.issue);

  String get message => switch (issue) {
        MeetupLocationIssue.serviceDisabled => 'Turn on location services to check in at the venue.',
        MeetupLocationIssue.denied || MeetupLocationIssue.deniedForever =>
          'Location permission is needed to check in. You can enter the host code instead.',
        MeetupLocationIssue.unavailable => 'We could not find your location. You can enter the host code instead.',
      };

  @override
  String toString() => message;
}

typedef MeetupFix = ({double lat, double lng});

class MeetupService extends ChangeNotifier {
  final BackendService backend;
  MeetupService(this.backend);

  /// Local reminder ids: base + meetup id (outside the scheduler's ranges).
  static const reminderIdBase = 40000;

  /// Tests replace the device location lookup ([precise] for check-in).
  @visibleForTesting
  Future<MeetupFix?> Function({required bool precise})? debugLocator;

  /// Tests replace the permission check (true = granted). [ask] prompts the user.
  @visibleForTesting
  Future<MeetupLocationIssue?> Function({required bool ask})? debugPermission;

  /// Tests observe reminders instead of scheduling them.
  @visibleForTesting
  void Function(Meetup meetup, DateTime? when)? debugReminder;

  /// Clock for the check-in window and reminders (tests override it).
  DateTime Function() clock = DateTime.now;

  bool _disposed = false;
  MeetupList? _nearby;
  Future<MeetupList>? _nearbyFuture;
  MeetupFix? _lastFix;

  /// The latest "near you" list (for the Home rail), or null until loaded.
  MeetupList? get nearby => _nearby;

  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  static String errorText(Object e) {
    if (e is MeetupLocationException) return e.message;
    if (e is BackendException) {
      if (e.statusCode == 401) return 'Please log in to join meetups.';
      if (e.statusCode == 429 && e.message.trim().isEmpty) return 'Slow down a little and try again.';
      if (e.message.trim().isNotEmpty) return e.message;
    }
    return 'Could not reach the server. Please check your connection.';
  }

  /// Error code of the last failed call (e.g. FULL, TOO_FAR, NOT_VERIFIED).
  String? get lastErrorCode => backend.lastErrorCode;

  // --------------------------------------------------------------- location

  Future<MeetupLocationIssue?> _permission({required bool ask}) async {
    final d = debugPermission;
    if (d != null) return d(ask: ask);
    try {
      if (!await Geolocator.isLocationServiceEnabled()) return MeetupLocationIssue.serviceDisabled;
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied && ask) perm = await Geolocator.requestPermission();
      return switch (perm) {
        LocationPermission.always || LocationPermission.whileInUse => null,
        LocationPermission.deniedForever => MeetupLocationIssue.deniedForever,
        _ => MeetupLocationIssue.denied,
      };
    } catch (_) {
      return MeetupLocationIssue.unavailable;
    }
  }

  Future<MeetupFix?> _locate({required bool precise}) async {
    final d = debugLocator;
    if (d != null) return d(precise: precise);
    final pos = await Geolocator.getCurrentPosition(
      locationSettings: LocationSettings(
        accuracy: precise ? LocationAccuracy.high : LocationAccuracy.low,
        timeLimit: const Duration(seconds: 15),
      ),
    );
    return (lat: pos.latitude, lng: pos.longitude);
  }

  /// Device location. Prompts for permission only when [ask]. Throws
  /// [MeetupLocationException] when it can't be had.
  Future<MeetupFix> locate({bool ask = false, bool precise = false}) async {
    final issue = await _permission(ask: ask);
    if (issue != null) throw MeetupLocationException(issue);
    MeetupFix? fix;
    try {
      fix = await _locate(precise: precise).timeout(const Duration(seconds: 20));
    } catch (_) {
      fix = null;
    }
    if (fix == null) throw const MeetupLocationException(MeetupLocationIssue.unavailable);
    if (!precise) _lastFix = fix;
    return fix;
  }

  // ------------------------------------------------------------------ list

  /// GET /meetups. Coordinates are rounded to ~1 km before they are sent.
  Future<MeetupList> list({String? type, MeetupFix? near, int? radiusKm, String? city}) async {
    double r(double v) => (v * 100).roundToDouble() / 100;
    final q = <String>[
      if (type != null && type != 'all') 'type=${Uri.encodeQueryComponent(type)}',
      if (near != null) 'lat=${r(near.lat)}',
      if (near != null) 'lng=${r(near.lng)}',
      if (radiusKm != null) 'radiusKm=$radiusKm',
      if (city != null && city.trim().isNotEmpty) 'city=${Uri.encodeQueryComponent(city.trim())}',
    ];
    final res = await backend.api('GET', q.isEmpty ? '/meetups' : '/meetups?${q.join('&')}');
    return MeetupList(
      origin: _str(res['origin'], 'none'),
      radiusKm: _int(res['radiusKm']),
      meetups: Meetup.listFrom(res['meetups']),
    );
  }

  /// "Near you": uses the location only if permission was already granted
  /// (or [askLocation]), otherwise lists every upcoming event.
  Future<MeetupList> loadNearby({String? type, bool askLocation = false, bool force = false}) {
    if (!force && type == null && !askLocation && _nearby != null) return Future.value(_nearby);
    if (type == null && !askLocation && _nearbyFuture != null) return _nearbyFuture!;
    final f = _loadNearby(type: type, askLocation: askLocation);
    if (type == null) {
      _nearbyFuture = f;
      f.whenComplete(() => _nearbyFuture = null).ignore();
    }
    return f;
  }

  Future<MeetupList> _loadNearby({String? type, required bool askLocation}) async {
    MeetupFix? fix = _lastFix;
    if (fix == null || askLocation) {
      try {
        fix = await locate(ask: askLocation);
      } on MeetupLocationException {
        if (askLocation) rethrow;
        fix = null;
      }
    }
    final out = await list(type: type, near: fix);
    if (type == null) {
      _nearby = out;
      notifyListeners();
    }
    return out;
  }

  // ---------------------------------------------------------------- detail

  Future<Meetup> detail(int id) async => _meetup(await backend.api('GET', '/meetups/$id'));

  Meetup _meetup(Map<String, dynamic> res) {
    final m = Meetup.tryParse(res['meetup']);
    if (m == null) throw const BackendException('This meetup is not available', statusCode: 404);
    return m;
  }

  void _replaceInNearby(Meetup m) {
    final n = _nearby;
    if (n == null) return;
    _nearby = MeetupList(
      origin: n.origin,
      radiusKm: n.radiusKm,
      meetups: [for (final x in n.meetups) x.id == m.id ? _keepDistance(m, x) : x],
    );
    notifyListeners();
  }

  static Meetup _keepDistance(Meetup fresh, Meetup old) => fresh.distanceKm != null || old.distanceKm == null
      ? fresh
      : Meetup.tryParse({..._toJson(fresh), 'distanceKm': old.distanceKm}) ?? fresh;

  static Map<String, dynamic> _toJson(Meetup m) => {
        'id': m.id, 'title': m.title, 'type': m.type, 'status': m.status, 'phase': m.phase, 'venueName': m.venueName,
        'city': m.city, 'address': m.address, 'startsAt': m.startsAt.toIso8601String(), 'endsAt': m.endsAt.toIso8601String(),
        'capacity': m.capacity, 'goingCount': m.goingCount, 'spotsLeft': m.spotsLeft, 'womenOnly': m.womenOnly,
        'official': m.official, 'isHost': m.isHost, 'myStatus': m.myStatus,
        if (m.host != null) 'host': {'displayName': m.host!.displayName, 'verified': m.host!.verified},
      };

  // ------------------------------------------------------------------ RSVP

  Future<Meetup> rsvp(int id) async {
    final m = _meetup(await backend.api('POST', '/meetups/$id/rsvp'));
    _replaceInNearby(m);
    unawaited(_scheduleReminder(m));
    return m;
  }

  Future<Meetup?> cancelRsvp(int id) async {
    final res = await backend.api('POST', '/meetups/$id/cancel');
    unawaited(_cancelReminder(id));
    final m = Meetup.tryParse(res['meetup']);
    if (m != null) _replaceInNearby(m);
    return m;
  }

  /// Reminder the evening before (6 pm the day before), or 2 hours before
  /// when that has already passed. Local only; never throws.
  static DateTime? reminderTime(Meetup m, DateTime now) {
    final s = m.startsAt;
    final dayBefore = DateTime(s.year, s.month, s.day - 1, 18);
    if (dayBefore.isAfter(now)) return dayBefore;
    final twoHours = s.subtract(const Duration(hours: 2));
    return twoHours.isAfter(now) ? twoHours : null;
  }

  Future<void> _scheduleReminder(Meetup m) async {
    final when = reminderTime(m, clock());
    final d = debugReminder;
    if (d != null) return d(m, when);
    if (when == null) return;
    final ns = NotificationService.instance;
    if (ns == null) return;
    final sameDay = when.day == m.startsAt.day;
    await ns.scheduleOneOff(
      id: reminderIdBase + m.id % 100000,
      title: sameDay ? 'Satsang soon: ${m.title}' : 'Tomorrow: ${m.title}',
      body: '${m.venueName}${m.city == null ? '' : ', ${m.city}'}. Check in at the venue for ${m.coinsForCheckin} coins.',
      when: when,
      channel: NotificationChannels.buddy,
      payload: {'type': 'meetup_update', 'meetupId': '${m.id}', 'kind': 'reminder'},
    );
  }

  Future<void> _cancelReminder(int id) async {
    final d = debugReminder;
    if (d != null) return;
    await NotificationService.instance?.cancelOneOff(reminderIdBase + id % 100000);
  }

  // -------------------------------------------------------------- check-in

  /// Checks in with the device's precise location (asks for permission).
  Future<MeetupCheckin> checkInHere(int id) async {
    final fix = await locate(ask: true, precise: true);
    return _checkin(id, {'lat': fix.lat, 'lng': fix.lng});
  }

  /// Checks in with the host's 6-digit code (indoor / GPS trouble).
  Future<MeetupCheckin> checkInWithCode(int id, String code) =>
      _checkin(id, {'code': code.replaceAll(RegExp(r'\s'), '')});

  Future<MeetupCheckin> _checkin(int id, Map<String, dynamic> body) async {
    final res = await backend.api('POST', '/meetups/$id/checkin', body: body);
    final m = Meetup.tryParse(res['meetup']);
    if (m != null) _replaceInNearby(m);
    return MeetupCheckin(
      coinsAwarded: _int(res['coinsAwarded']) ?? 0,
      balance: _int(res['balance']),
      meetup: m,
      raw: res,
    );
  }

  /// Sends a buddy request to someone met at a meetup (as a satsang buddy,
  /// falling back to friend when they are not looking for one).
  Future<void> connect(int userId) async {
    try {
      await backend.api('POST', '/buddy/connect', body: {'userId': userId, 'intent': 'spiritual'});
    } on BackendException {
      if (backend.lastErrorCode != 'INTENT_MISMATCH') rethrow;
      await backend.api('POST', '/buddy/connect', body: {'userId': userId, 'intent': 'friend'});
    }
  }

  // ----------------------------------------------------------- mine / host

  Future<MyMeetups> mine() async {
    final res = await backend.api('GET', '/meetups/mine');
    return MyMeetups(
      upcoming: Meetup.listFrom(res['upcoming']),
      past: Meetup.listFrom(res['past']),
      hosting: Meetup.listFrom(res['hosting']),
    );
  }

  Future<ProposeStatus> proposeStatus() async {
    if (!backend.isAuthenticated) return const ProposeStatus(canPropose: false, reason: 'LOGIN_REQUIRED');
    final res = await backend.api('GET', '/meetups/can-propose');
    return ProposeStatus(
      canPropose: _bool(res['canPropose']),
      reason: _strOrNull(res['reason']),
      remainingThisWeek: _int(res['remainingThisWeek']) ?? 0,
      canHostWomenOnly: _bool(res['canHostWomenOnly']),
    );
  }

  Future<List<MeetupTemple>> temples() async {
    final res = await backend.api('GET', '/trips/temples');
    final raw = res['temples'];
    if (raw is! List) return const [];
    return raw
        .map(_map)
        .whereType<Map<String, dynamic>>()
        .where((t) => _str(t['id']).isNotEmpty)
        .map((t) => MeetupTemple(id: _str(t['id']), name: _str(t['name']), city: _str(t['city']), state: _str(t['state'])))
        .toList()
      ..sort((a, b) => a.name.compareTo(b.name));
  }

  Future<Meetup> propose(MeetupDraft d) async => _meetup(await backend.api('POST', '/meetups', body: d.toJson()));

  /// Host withdraws their own event (attendees are notified).
  Future<Meetup> cancelEvent(int id) async {
    final m = _meetup(await backend.api('POST', '/meetups/$id/cancel-event'));
    _nearby = null;
    notifyListeners();
    return m;
  }
}
