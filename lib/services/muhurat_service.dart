import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'backend_service.dart';
import 'notification_service.dart';

// ============================================================================
// Muhurat finder: models, API client, saved place and reminders.
// Backend: GET /api/muhurat/events, GET /api/muhurat?event=&lat=&lng=&tz=&from=&days=
// ============================================================================

String _str(dynamic v) => v == null ? '' : v.toString();
String? _strOrNull(dynamic v) {
  final s = v?.toString().trim();
  return (s == null || s.isEmpty) ? null : s;
}

int _int(dynamic v, [int fallback = 0]) => v is num ? v.round() : int.tryParse(_str(v)) ?? fallback;

List<String> _strings(dynamic v) =>
    v is List ? v.map((e) => _str(e).trim()).where((s) => s.isNotEmpty).toList() : const [];

/// One supported event ("Griha Pravesh", "Vehicle purchase", ...).
class MuhuratEvent {
  final String id;
  final String label;
  final String labelHi;
  final String icon;
  final String? note;

  const MuhuratEvent({required this.id, required this.label, required this.labelHi, required this.icon, this.note});

  factory MuhuratEvent.fromJson(Map<String, dynamic> j) => MuhuratEvent(
        id: _str(j['id']),
        label: _str(j['label']),
        labelHi: _str(j['labelHi']),
        icon: _str(j['icon']),
        note: _strOrNull(j['note']),
      );

  /// Short label for chips: text before the first bracket.
  String get shortLabel {
    final i = label.indexOf('(');
    return (i > 0 ? label.substring(0, i) : label).trim();
  }

  /// Built-in list (same ids as the backend) so the grid renders instantly and offline.
  static const fallback = <MuhuratEvent>[
    MuhuratEvent(id: 'griha_pravesh', label: 'Griha Pravesh (moving into a new home)', labelHi: 'गृह प्रवेश', icon: 'home'),
    MuhuratEvent(id: 'vehicle_purchase', label: 'Vehicle purchase', labelHi: 'वाहन खरीद', icon: 'car'),
    MuhuratEvent(id: 'new_job_or_business', label: 'New job or business', labelHi: 'नई नौकरी / व्यापार आरंभ', icon: 'work'),
    MuhuratEvent(id: 'property_purchase', label: 'Property / land purchase', labelHi: 'संपत्ति / भूमि खरीद', icon: 'property'),
    MuhuratEvent(
        id: 'marriage',
        label: 'Marriage (Vivah)',
        labelHi: 'विवाह',
        icon: 'marriage',
        note: 'This finds generally auspicious days only. The final vivah muhurat must be confirmed by a pandit after '
            'matching both Kundlis.'),
    MuhuratEvent(id: 'engagement', label: 'Engagement (Sagai / Roka)', labelHi: 'सगाई', icon: 'ring'),
    MuhuratEvent(id: 'naming_ceremony', label: 'Naming ceremony (Namkaran)', labelHi: 'नामकरण', icon: 'baby'),
    MuhuratEvent(id: 'mundan', label: 'Mundan (first haircut)', labelHi: 'मुंडन', icon: 'child'),
    MuhuratEvent(id: 'travel_start', label: 'Start of a journey', labelHi: 'यात्रा आरंभ', icon: 'travel'),
    MuhuratEvent(id: 'gold_jewellery_purchase', label: 'Gold / jewellery purchase', labelHi: 'सोना / आभूषण खरीद', icon: 'gold'),
    MuhuratEvent(id: 'starting_education', label: 'Starting education (Vidyarambh)', labelHi: 'विद्यारंभ', icon: 'school'),
    MuhuratEvent(
        id: 'surgery_or_medical',
        label: 'Planned surgery / treatment',
        labelHi: 'शल्य चिकित्सा / उपचार',
        icon: 'medical',
        note: 'Always follow your doctor. Never delay urgent or recommended medical care for a muhurat - astrology is '
            'only for non-urgent planning.'),
  ];
}

class MuhuratWindow {
  final String start;
  final String end;
  final String label;
  const MuhuratWindow({required this.start, required this.end, required this.label});

  factory MuhuratWindow.fromJson(Map<String, dynamic> j) =>
      MuhuratWindow(start: _str(j['start']), end: _str(j['end']), label: _str(j['label']));

  String get text => '$start – $end';
}

/// One recommended day.
class MuhuratDay {
  final DateTime date;
  final String weekday;
  final int score;
  final String tithi;
  final String nakshatra;
  final String yoga;
  final String paksha;
  final MuhuratWindow? bestWindow;
  final List<String> reasons;
  final List<String> cautions;
  final String? rahuKaal;

  const MuhuratDay({
    required this.date,
    required this.weekday,
    required this.score,
    required this.tithi,
    required this.nakshatra,
    required this.yoga,
    required this.paksha,
    required this.bestWindow,
    required this.reasons,
    required this.cautions,
    this.rahuKaal,
  });

  static MuhuratDay? fromJson(dynamic raw) {
    if (raw is! Map) return null;
    final j = Map<String, dynamic>.from(raw);
    final parts = _str(j['date']).split('-').map(int.tryParse).toList();
    if (parts.length != 3 || parts.any((p) => p == null)) return null;
    final w = j['bestWindow'];
    return MuhuratDay(
      date: DateTime(parts[0]!, parts[1]!, parts[2]!),
      weekday: _str(j['weekday']),
      score: _int(j['score']).clamp(0, 100),
      tithi: _str(j['tithi']),
      nakshatra: _str(j['nakshatra']),
      yoga: _str(j['yoga']),
      paksha: _str(j['paksha']),
      bestWindow: w is Map ? MuhuratWindow.fromJson(Map<String, dynamic>.from(w)) : null,
      reasons: _strings(j['reasons']),
      cautions: _strings(j['cautions']),
      rahuKaal: _strOrNull(j['rahuKaal']),
    );
  }

  String get isoDate =>
      '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
}

class MuhuratAvoided {
  final String reason;
  final String text;
  final int count;
  const MuhuratAvoided({required this.reason, required this.text, required this.count});
}

class MuhuratResponse {
  final MuhuratEvent event;
  final List<MuhuratDay> results;
  final List<MuhuratAvoided> avoided;
  final String disclaimer;
  final String? message;
  final bool personal;
  final int days;

  const MuhuratResponse({
    required this.event,
    required this.results,
    required this.avoided,
    required this.disclaimer,
    this.message,
    this.personal = false,
    this.days = 30,
  });

  factory MuhuratResponse.fromJson(Map<String, dynamic> j, MuhuratEvent fallbackEvent) {
    final ev = j['event'];
    final avoided = <MuhuratAvoided>[];
    final rawAvoided = j['avoided'];
    if (rawAvoided is List) {
      for (final a in rawAvoided) {
        if (a is! Map) continue;
        avoided.add(MuhuratAvoided(reason: _str(a['reason']), text: _str(a['text']), count: _int(a['count'])));
      }
    }
    final rawResults = j['results'];
    return MuhuratResponse(
      event: ev is Map ? MuhuratEvent.fromJson(Map<String, dynamic>.from(ev)) : fallbackEvent,
      results: rawResults is List ? rawResults.map(MuhuratDay.fromJson).whereType<MuhuratDay>().toList() : const [],
      avoided: avoided,
      disclaimer: _strOrNull(j['disclaimer']) ?? MuhuratService.defaultDisclaimer,
      message: _strOrNull(j['message']),
      personal: j['personal'] == true,
      days: _int(j['days'], 30),
    );
  }
}

/// A place the search runs for. Only rounded coordinates are sent; nothing is shared with other users.
class MuhuratPlace {
  final String name;
  final double lat;
  final double lng;
  final String? tz;
  const MuhuratPlace(this.name, this.lat, this.lng, [this.tz]);

  Map<String, dynamic> toJson() => {'name': name, 'lat': lat, 'lng': lng, if (tz != null) 'tz': tz};

  static MuhuratPlace? fromJson(dynamic j) {
    if (j is! Map) return null;
    final lat = j['lat'];
    final lng = j['lng'];
    if (lat is! num || lng is! num) return null;
    return MuhuratPlace(_str(j['name']), lat.toDouble(), lng.toDouble(), _strOrNull(j['tz']));
  }

  /// Same default as the Panchang screen (kDefaultPanchangLocation).
  static const delhi = MuhuratPlace('New Delhi', 28.6139, 77.2090, 'Asia/Kolkata');

  static const cities = <MuhuratPlace>[
    delhi,
    MuhuratPlace('Mumbai', 19.076, 72.8777, 'Asia/Kolkata'),
    MuhuratPlace('Bengaluru', 12.9716, 77.5946, 'Asia/Kolkata'),
    MuhuratPlace('Kolkata', 22.5726, 88.3639, 'Asia/Kolkata'),
    MuhuratPlace('Chennai', 13.0827, 80.2707, 'Asia/Kolkata'),
    MuhuratPlace('Hyderabad', 17.385, 78.4867, 'Asia/Kolkata'),
    MuhuratPlace('Pune', 18.5204, 73.8567, 'Asia/Kolkata'),
    MuhuratPlace('Ahmedabad', 23.0225, 72.5714, 'Asia/Kolkata'),
    MuhuratPlace('Jaipur', 26.9124, 75.7873, 'Asia/Kolkata'),
    MuhuratPlace('Lucknow', 26.8467, 80.9462, 'Asia/Kolkata'),
    MuhuratPlace('Patna', 25.5941, 85.1376, 'Asia/Kolkata'),
    MuhuratPlace('Varanasi', 25.3176, 82.9739, 'Asia/Kolkata'),
    MuhuratPlace('Bhopal', 23.2599, 77.4126, 'Asia/Kolkata'),
    MuhuratPlace('Chandigarh', 30.7333, 76.7794, 'Asia/Kolkata'),
    MuhuratPlace('Guwahati', 26.1445, 91.7362, 'Asia/Kolkata'),
    MuhuratPlace('Kathmandu', 27.7172, 85.324, 'Asia/Kathmandu'),
  ];
}

/// Thin client + local helpers. Stateless apart from the saved place.
class MuhuratService {
  final BackendService backend;

  /// Reminder hook for tests; defaults to [NotificationService.instance].
  final NotificationService? Function() notifications;

  MuhuratService(this.backend, {NotificationService? Function()? notifications})
      : notifications = notifications ?? (() => NotificationService.instance);

  static const defaultDisclaimer =
      'Muhurat suggestions follow widely published Vedic panchang rules. They are general guidance and do not replace '
      'your family tradition or a pandit. Customs vary by region.';

  /// Local reminder ids: [reminderIdBase] .. +19999 (meetups use 40000..139999).
  static const reminderIdBase = 150000;
  static const _kPlace = 'muhurat_place_v1';

  Future<List<MuhuratEvent>> events() async {
    try {
      final res = await backend.api('GET', '/muhurat/events');
      final raw = res['events'];
      if (raw is List) {
        final list = raw.whereType<Map>().map((e) => MuhuratEvent.fromJson(Map<String, dynamic>.from(e))).toList();
        if (list.isNotEmpty) return list;
      }
    } catch (_) {}
    return MuhuratEvent.fallback;
  }

  Future<MuhuratResponse> find(MuhuratEvent event, MuhuratPlace place, {DateTime? from, int days = 30}) async {
    final f = from ?? DateTime.now();
    final iso = '${f.year}-${f.month.toString().padLeft(2, '0')}-${f.day.toString().padLeft(2, '0')}';
    final q = <String, String>{
      'event': event.id,
      'lat': place.lat.toStringAsFixed(2),
      'lng': place.lng.toStringAsFixed(2),
      if (place.tz != null) 'tz': place.tz!,
      'from': iso,
      'days': '$days',
    };
    final res = await backend.api('GET', '/muhurat?${Uri(queryParameters: q).query}',
        timeout: const Duration(seconds: 25));
    return MuhuratResponse.fromJson(res, event);
  }

  Future<MuhuratPlace> savedPlace() async {
    try {
      final sp = await SharedPreferences.getInstance();
      final raw = sp.getString(_kPlace);
      if (raw != null) return MuhuratPlace.fromJson(json.decode(raw)) ?? MuhuratPlace.delhi;
    } catch (_) {}
    return MuhuratPlace.delhi;
  }

  Future<void> savePlace(MuhuratPlace p) async {
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.setString(_kPlace, json.encode(p.toJson()));
    } catch (_) {}
  }

  /// Birth place from the Kundli, offered as an "approximate" option (never shown to others).
  MuhuratPlace? birthPlace() {
    final bd = backend.kundliData?['birthDetails'];
    if (bd is! Map) return null;
    final lat = double.tryParse('${bd['latitude'] ?? ''}');
    final lng = double.tryParse('${bd['longitude'] ?? ''}');
    if (lat == null || lng == null || lat.abs() > 66) return null;
    final name = _strOrNull(bd['placeOfBirth'])?.split(',').first.trim();
    return MuhuratPlace(name == null ? 'Birth place' : '$name (birth place)', lat, lng, _strOrNull(bd['timezone']));
  }

  /// The two reminder instants for a muhurat day: 18:00 the day before and 10:00 on the day.
  static List<DateTime> reminderTimes(DateTime day) => [
        DateTime(day.year, day.month, day.day - 1, 18),
        DateTime(day.year, day.month, day.day, 10),
      ];

  static int reminderId(String eventId, DateTime day, int slot) {
    final key = '$eventId|${day.year}-${day.month}-${day.day}';
    var h = 0;
    for (final c in key.codeUnits) {
      h = (h * 31 + c) & 0x7fffffff;
    }
    return reminderIdBase + (h % 9999) * 2 + slot;
  }

  /// Schedules the reminders. Returns how many were scheduled (0 = permission off / all in the past).
  Future<int> addReminders(MuhuratEvent event, MuhuratDay day) async {
    final ns = notifications();
    if (ns == null) return 0;
    final known = await ns.refreshPermission();
    if (known == false && !await ns.requestPermission()) return 0;
    final times = reminderTimes(day.date);
    final window = day.bestWindow == null ? '' : ' Best time: ${day.bestWindow!.text}.';
    var n = 0;
    for (var i = 0; i < times.length; i++) {
      final ok = await ns.scheduleOneOff(
        id: reminderId(event.id, day.date, i),
        title: i == 0 ? 'Tomorrow: ${event.shortLabel} muhurat' : 'Today: ${event.shortLabel} muhurat',
        body: '${day.weekday}, ${day.nakshatra} nakshatra.$window',
        when: times[i],
        channel: NotificationChannels.reminders,
        payload: {'type': 'muhurat', 'event': event.id, 'date': day.isoDate},
      );
      if (ok) n++;
    }
    return n;
  }

  static String shareText(MuhuratEvent event, MuhuratDay d, String place) {
    final b = StringBuffer()
      ..writeln('${event.shortLabel} muhurat (${event.labelHi})')
      ..writeln('${d.weekday}, ${d.isoDate} · $place')
      ..writeln('${d.tithi} · ${d.nakshatra} nakshatra');
    if (d.bestWindow != null) b.writeln('Best time: ${d.bestWindow!.text} (${d.bestWindow!.label})');
    for (final r in d.reasons) {
      b.writeln('✓ $r');
    }
    b.write('Found with CosmicGuide. Please confirm with your family pandit.');
    return b.toString();
  }

  @visibleForTesting
  static String isoOf(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}
