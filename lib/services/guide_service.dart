import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;
import 'package:shared_preferences/shared_preferences.dart';

import 'backend_service.dart';
import 'notification_service.dart';

// ============================================================================
// Puja & vrat guides. Content is bundled (assets/data/puja_guides.json) so it
// works offline; the backend (GET /api/guides, /api/guides/:id) adds next
// observance dates and newer content when online.
// ============================================================================

String _s(dynamic v) => v == null ? '' : v.toString().trim();
String? _sn(dynamic v) {
  final s = _s(v);
  return s.isEmpty ? null : s;
}

List<String> _list(dynamic v) => v is List ? v.map(_s).where((e) => e.isNotEmpty).toList() : const [];

DateTime? _date(dynamic v) {
  final p = _s(v).split('-').map(int.tryParse).toList();
  if (p.length != 3 || p.any((x) => x == null)) return null;
  return DateTime(p[0]!, p[1]!, p[2]!);
}

class GuideMantra {
  final String devanagari;
  final String transliteration;
  const GuideMantra(this.devanagari, this.transliteration);

  static GuideMantra? fromJson(dynamic j) {
    if (j is! Map) return null;
    final d = _s(j['devanagari']);
    final t = _s(j['transliteration']);
    if (d.isEmpty && t.isEmpty) return null;
    return GuideMantra(d, t);
  }
}

class GuideStep {
  final String text;
  final GuideMantra? mantra;
  const GuideStep(this.text, [this.mantra]);
}

class SamagriItem {
  final String item;
  final String? qty;
  const SamagriItem(this.item, [this.qty]);
  String get label => qty == null ? item : '$item ($qty)';
}

class VratRules {
  final List<String> doList;
  final List<String> dontList;
  final List<String> food;
  const VratRules(this.doList, this.dontList, this.food);
}

class PujaGuide {
  final String id;
  final String title;
  final String titleHi;
  final String deity;
  final String category; // vrat | puja | festival
  final String? image; // file name in assets/images
  final String whenText;
  final String? festivalKey;
  final Map<String, dynamic>? rule;
  final String duration;
  final String difficulty;
  final String overview;
  final List<SamagriItem> samagri;
  final List<GuideStep> steps;
  final VratRules? vratRules;
  final String katha;
  final String aartiTitle;
  final List<GuideMantra> aartiLines;
  final List<String> tips;
  final String regionalNote;
  final List<DateTime> nextDates;

  const PujaGuide({
    required this.id,
    required this.title,
    required this.titleHi,
    required this.deity,
    required this.category,
    this.image,
    required this.whenText,
    this.festivalKey,
    this.rule,
    required this.duration,
    required this.difficulty,
    required this.overview,
    this.samagri = const [],
    this.steps = const [],
    this.vratRules,
    this.katha = '',
    this.aartiTitle = '',
    this.aartiLines = const [],
    this.tips = const [],
    this.regionalNote = 'Customs vary by family and region; follow your family tradition.',
    this.nextDates = const [],
  });

  /// Whether this is the full guide (detail) rather than a list summary.
  bool get hasDetail => steps.isNotEmpty;

  DateTime? get nextDate => nextDates.isEmpty ? null : nextDates.first;

  String? get imageAsset => image == null || !GuideService.knownImages.contains(image) ? null : 'assets/images/$image';

  static PujaGuide? fromJson(dynamic raw) {
    if (raw is! Map) return null;
    final j = Map<String, dynamic>.from(raw);
    final id = _s(j['id']);
    if (id.isEmpty) return null;
    final when = j['when'] is Map ? Map<String, dynamic>.from(j['when'] as Map) : const <String, dynamic>{};
    final vr = j['vratRules'];
    final aarti = j['aarti'] is Map ? Map<String, dynamic>.from(j['aarti'] as Map) : const <String, dynamic>{};
    final dates = (j['nextDates'] is List ? j['nextDates'] as List : [j['nextDate']])
        .map(_date)
        .whereType<DateTime>()
        .toList();
    return PujaGuide(
      id: id,
      title: _s(j['title']),
      titleHi: _s(j['titleHi']),
      deity: _s(j['deity']),
      category: _s(j['category']).isEmpty ? 'puja' : _s(j['category']),
      image: _sn(j['image']),
      whenText: _s(when['text']),
      festivalKey: _sn(when['festivalKey']),
      rule: when['rule'] is Map ? Map<String, dynamic>.from(when['rule'] as Map) : null,
      duration: _s(j['duration']),
      difficulty: _s(j['difficulty']),
      overview: _s(j['overview']),
      samagri: [
        if (j['samagri'] is List)
          for (final s in j['samagri'] as List)
            if (s is Map && _s(s['item']).isNotEmpty) SamagriItem(_s(s['item']), _sn(s['qty'])),
      ],
      steps: [
        if (j['steps'] is List)
          for (final s in j['steps'] as List)
            if (s is Map && _s(s['text']).isNotEmpty) GuideStep(_s(s['text']), GuideMantra.fromJson(s['mantra'])),
      ],
      vratRules: vr is Map ? VratRules(_list(vr['do']), _list(vr['dont']), _list(vr['food'])) : null,
      katha: _s(j['katha']),
      aartiTitle: _s(aarti['title']),
      aartiLines: aarti['lines'] is List
          ? (aarti['lines'] as List).map(GuideMantra.fromJson).whereType<GuideMantra>().toList()
          : const [],
      tips: _list(j['tips']),
      regionalNote: _sn(j['regionalNote']) ?? 'Customs vary by family and region; follow your family tradition.',
      nextDates: dates,
    );
  }

  /// Copy with server dates (and server content when it is a full guide).
  PujaGuide mergeServer(PujaGuide server) {
    final base = server.hasDetail ? server : this;
    return PujaGuide(
      id: base.id,
      title: base.title,
      titleHi: base.titleHi,
      deity: base.deity,
      category: base.category,
      image: base.image ?? image,
      whenText: base.whenText,
      festivalKey: base.festivalKey,
      rule: base.rule ?? rule,
      duration: base.duration,
      difficulty: base.difficulty,
      overview: base.overview,
      samagri: base.samagri,
      steps: base.steps,
      vratRules: base.vratRules,
      katha: base.katha,
      aartiTitle: base.aartiTitle,
      aartiLines: base.aartiLines,
      tips: base.tips,
      regionalNote: base.regionalNote,
      nextDates: server.nextDates.isNotEmpty ? server.nextDates : nextDates,
    );
  }

  /// Offline next date for weekday rules (Somvar, Hanuman). Lunar dates need the server.
  DateTime? localNextDate(DateTime today) {
    final r = rule;
    if (r == null || r['type'] != 'weekday' || r['weekdays'] is! List) return null;
    final days = (r['weekdays'] as List).whereType<num>().map((e) => e.toInt()).toSet();
    for (var i = 0; i < 8; i++) {
      final d = DateTime(today.year, today.month, today.day + i);
      if (days.contains(d.weekday % 7)) return d;
    }
    return null;
  }
}

/// Loads guides (bundle first, then server), persists samagri checklists and schedules reminders.
class GuideService {
  final BackendService? backend;
  final Future<String> Function() _loadAsset;
  final NotificationService? Function() notifications;

  GuideService(this.backend, {Future<String> Function()? loadAsset, NotificationService? Function()? notifications})
      : _loadAsset = loadAsset ?? (() => rootBundle.loadString(assetPath)),
        notifications = notifications ?? (() => NotificationService.instance);

  static const assetPath = 'assets/data/puja_guides.json';

  /// Deity images that ship in assets/images (others fall back to a gradient).
  static const knownImages = {
    'ganesh.jpg', 'durga-ma.jpg', 'hanuman_chalisa.jpg', 'hanumanji.jpg', 'diwali_lakshmi_puja.jpg', 'satyanarayan.jpg',
    'ganesh_sthapana.jpg', 'durga_abhishekam.jpg',
  };

  /// Local reminder ids: [reminderIdBase] .. +999 (2 per guide).
  static const reminderIdBase = 170000;

  static List<PujaGuide>? _bundled;

  static List<PujaGuide> parse(String raw) {
    final decoded = json.decode(raw);
    final list = decoded is Map ? decoded['guides'] : decoded;
    if (list is! List) return const [];
    return list.map(PujaGuide.fromJson).whereType<PujaGuide>().toList();
  }

  Future<List<PujaGuide>> bundled() async {
    final cached = _bundled;
    if (cached != null) return cached;
    try {
      return _bundled = parse(await _loadAsset());
    } catch (_) {
      return const [];
    }
  }

  /// Bundled guides merged with server dates. Never throws; offline = bundle only.
  Future<List<PujaGuide>> all() async {
    final local = await bundled();
    final b = backend;
    if (b == null) return local;
    try {
      final res = await b.api('GET', '/guides', timeout: const Duration(seconds: 12));
      final raw = res['guides'];
      if (raw is! List) return local;
      final server = {for (final g in raw.map(PujaGuide.fromJson).whereType<PujaGuide>()) g.id: g};
      final merged = [for (final g in local) server[g.id] == null ? g : g.mergeServer(server[g.id]!)];
      // Guides only the server knows (newer content) are listed too; their detail comes from the server.
      for (final g in server.values) {
        if (!merged.any((m) => m.id == g.id)) merged.add(g);
      }
      return merged;
    } catch (_) {
      return local;
    }
  }

  /// Full guide: bundle (instant / offline) refreshed from the server when reachable.
  Future<PujaGuide?> detail(String id) async {
    final local = (await bundled()).where((g) => g.id == id).firstOrNull;
    final b = backend;
    if (b == null) return local;
    try {
      final res = await b.api('GET', '/guides/${Uri.encodeComponent(id)}', timeout: const Duration(seconds: 12));
      final server = PujaGuide.fromJson(res['guide']);
      if (server == null) return local;
      return local == null ? server : local.mergeServer(server);
    } catch (e) {
      if (local == null) rethrow;
      return local;
    }
  }

  // ---------------------------------------------------------------- checklist
  static String _checkKey(String id) => 'guide_samagri_$id';

  Future<Set<int>> checked(String guideId) async {
    try {
      final sp = await SharedPreferences.getInstance();
      return (sp.getStringList(_checkKey(guideId)) ?? const []).map(int.tryParse).whereType<int>().toSet();
    } catch (_) {
      return <int>{};
    }
  }

  Future<void> saveChecked(String guideId, Set<int> items) async {
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.setStringList(_checkKey(guideId), (items.toList()..sort()).map((e) => '$e').toList());
    } catch (_) {}
  }

  static String samagriShareText(PujaGuide g, Set<int> checked) {
    final b = StringBuffer('${g.title} (${g.titleHi}) - samagri list\n');
    for (var i = 0; i < g.samagri.length; i++) {
      b.writeln('${checked.contains(i) ? '☑' : '☐'} ${g.samagri[i].label}');
    }
    b.write('From CosmicGuide puja guides');
    return b.toString();
  }

  // ---------------------------------------------------------------- reminders
  /// Eve (18:00 the day before) and morning (06:30) of [day].
  static List<DateTime> reminderTimes(DateTime day) => [
        DateTime(day.year, day.month, day.day - 1, 18),
        DateTime(day.year, day.month, day.day, 6, 30),
      ];

  static int reminderId(String guideId, int slot) {
    var h = 0;
    for (final c in guideId.codeUnits) {
      h = (h * 31 + c) & 0x7fffffff;
    }
    return reminderIdBase + (h % 499) * 2 + slot;
  }

  /// Schedules the two reminders. Returns how many were scheduled.
  Future<int> remind(PujaGuide g, DateTime day) async {
    final ns = notifications();
    if (ns == null) return 0;
    final known = await ns.refreshPermission();
    if (known == false && !await ns.requestPermission()) return 0;
    final times = reminderTimes(day);
    var n = 0;
    for (var i = 0; i < times.length; i++) {
      final ok = await ns.scheduleOneOff(
        id: reminderId(g.id, i),
        title: i == 0 ? 'Tomorrow: ${g.title}' : 'Today: ${g.title}',
        body: i == 0
            ? 'Get your samagri ready tonight. Open the guide for the full steps.'
            : 'Your step-by-step ${g.category == 'vrat' ? 'vrat' : 'puja'} guide is ready. 🙏',
        when: times[i],
        channel: NotificationChannels.festivals,
        payload: {'type': 'guide', 'guideId': g.id},
      );
      if (ok) n++;
    }
    return n;
  }
}
