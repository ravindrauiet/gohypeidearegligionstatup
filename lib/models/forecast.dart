// Typed models for the personal forecast API (`/api/forecast/*`).
//
// Parsing is deliberately forgiving: numbers may arrive as strings, any field
// may be null or missing, and lists may contain junk. Every `fromJson` returns
// a usable object with sensible defaults instead of throwing.

import 'dart:convert';

// ---------------------------------------------------------------------------
// Parsing helpers
// ---------------------------------------------------------------------------

Map<String, dynamic> fMap(dynamic v) {
  if (v is Map) return Map<String, dynamic>.from(v);
  if (v is String && v.trim().startsWith('{')) {
    try {
      final d = jsonDecode(v);
      if (d is Map) return Map<String, dynamic>.from(d);
    } catch (_) {}
  }
  return <String, dynamic>{};
}

List<dynamic> fList(dynamic v) {
  if (v is List) return v;
  if (v is String && v.trim().startsWith('[')) {
    try {
      final d = jsonDecode(v);
      if (d is List) return d;
    } catch (_) {}
  }
  return const [];
}

List<Map<String, dynamic>> fMapList(dynamic v) =>
    fList(v).whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();

String fStr(dynamic v, [String fallback = '']) {
  if (v == null) return fallback;
  final s = v.toString().trim();
  return (s.isEmpty || s == 'null') ? fallback : s;
}

String? fStrOrNull(dynamic v) {
  final s = fStr(v);
  return s.isEmpty ? null : s;
}

int? fIntOrNull(dynamic v) {
  if (v is int) return v;
  if (v is num) return v.isFinite ? v.round() : null;
  if (v is String) {
    final t = v.trim();
    return int.tryParse(t) ?? double.tryParse(t)?.round();
  }
  return null;
}

int fInt(dynamic v, [int fallback = 0]) => fIntOrNull(v) ?? fallback;

double fDouble(dynamic v, [double fallback = 0]) {
  if (v is num) return v.isFinite ? v.toDouble() : fallback;
  if (v is String) return double.tryParse(v.trim()) ?? fallback;
  return fallback;
}

bool fBool(dynamic v, [bool fallback = false]) {
  if (v is bool) return v;
  if (v is num) return v != 0;
  if (v is String) {
    final s = v.trim().toLowerCase();
    if (s == 'true' || s == 'yes' || s == '1') return true;
    if (s == 'false' || s == 'no' || s == '0') return false;
  }
  return fallback;
}

List<String> fStrList(dynamic v) =>
    fList(v).map((e) => fStr(e)).where((s) => s.isNotEmpty).toList();

/// Parses `YYYY-MM-DD` (or a full ISO timestamp) into a local, date-only value.
DateTime? fDate(dynamic v) {
  final s = fStr(v);
  if (s.isEmpty) return null;
  final m = RegExp(r'^(\d{4})-(\d{1,2})-(\d{1,2})').firstMatch(s);
  if (m != null) {
    final y = int.parse(m.group(1)!), mo = int.parse(m.group(2)!), d = int.parse(m.group(3)!);
    if (mo < 1 || mo > 12 || d < 1 || d > 31) return null;
    return DateTime(y, mo, d);
  }
  final p = DateTime.tryParse(s);
  return p == null ? null : DateTime(p.year, p.month, p.day);
}

List<DateTime> fDateList(dynamic v) => fList(v).map(fDate).whereType<DateTime>().toList();

int _score(dynamic v) => fInt(v, 50).clamp(0, 100);

/// `YYYY-MM-DD` for a date (local calendar fields).
String ymd(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// `YYYY-MM` for a month.
String ym(DateTime d) => '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}';

DateTime dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

/// Monday of the week containing [d].
DateTime mondayOf(DateTime d) => dateOnly(d).subtract(Duration(days: d.weekday - DateTime.monday));

bool sameDay(DateTime? a, DateTime? b) =>
    a != null && b != null && a.year == b.year && a.month == b.month && a.day == b.day;

// ---------------------------------------------------------------------------
// Enums (kept as normalised strings so unknown values never break parsing)
// ---------------------------------------------------------------------------

class Mood {
  Mood._();
  static const excellent = 'excellent';
  static const good = 'good';
  static const mixed = 'mixed';
  static const challenging = 'challenging';
  static const values = [excellent, good, mixed, challenging];

  static String parse(dynamic v, {int? score}) {
    final s = fStr(v).toLowerCase();
    if (values.contains(s)) return s;
    if (score != null) return fromScore(score);
    return mixed;
  }

  static String fromScore(int score) {
    if (score >= 75) return excellent;
    if (score >= 60) return good;
    if (score >= 42) return mixed;
    return challenging;
  }

  static String label(String mood) {
    switch (mood) {
      case excellent:
        return 'Excellent';
      case good:
        return 'Good';
      case challenging:
        return 'Challenging';
      default:
        return 'Mixed';
    }
  }
}

class Effect {
  Effect._();
  static const favorable = 'favorable';
  static const neutral = 'neutral';
  static const challenging = 'challenging';

  static String parse(dynamic v) {
    final s = fStr(v).toLowerCase();
    if (s == 'favorable' || s == 'favourable' || s == 'positive' || s == 'good') return favorable;
    if (s == 'challenging' || s == 'negative' || s == 'difficult' || s == 'bad') return challenging;
    return neutral;
  }

  static String label(String e) =>
      e == favorable ? 'Supportive' : (e == challenging ? 'Challenging' : 'Neutral');
}

// ---------------------------------------------------------------------------
// Shared objects
// ---------------------------------------------------------------------------

class ForecastProfile {
  final String name;
  final bool isFamily;
  final int? familyId;
  final String? relationship;

  const ForecastProfile({this.name = '', this.isFamily = false, this.familyId, this.relationship});

  factory ForecastProfile.fromJson(dynamic json) {
    final j = fMap(json);
    return ForecastProfile(
      name: fStr(j['name']),
      isFamily: fBool(j['isFamily']),
      familyId: fIntOrNull(j['familyId']),
      relationship: fStrOrNull(j['relationship']),
    );
  }

  String get firstName {
    final n = name.trim();
    if (n.isEmpty) return '';
    return n.split(RegExp(r'\s+')).first;
  }
}

/// Fields every forecast response carries.
class ForecastMeta {
  final ForecastProfile profile;
  final bool birthTimeKnown;
  final String? accuracyNote;
  final String generatedBy; // 'ai' | 'rules'

  const ForecastMeta({
    this.profile = const ForecastProfile(),
    this.birthTimeKnown = true,
    this.accuracyNote,
    this.generatedBy = 'rules',
  });

  factory ForecastMeta.fromJson(Map<String, dynamic> j) => ForecastMeta(
        profile: ForecastProfile.fromJson(j['profile']),
        birthTimeKnown: fBool(j['birthTimeKnown'], true),
        accuracyNote: fStrOrNull(j['accuracyNote']),
        generatedBy: fStr(j['generatedBy'], 'rules').toLowerCase() == 'ai' ? 'ai' : 'rules',
      );

  bool get isAi => generatedBy == 'ai';
}

class ForecastSummary {
  final String headline;
  final String narrative;
  final String mood;
  final int overallScore;

  const ForecastSummary({this.headline = '', this.narrative = '', this.mood = Mood.mixed, this.overallScore = 50});

  factory ForecastSummary.fromJson(dynamic json) {
    final j = fMap(json);
    final score = _score(j['overallScore'] ?? j['score']);
    return ForecastSummary(
      headline: fStr(j['headline']),
      narrative: fStr(j['narrative']),
      mood: Mood.parse(j['mood'], score: score),
      overallScore: score,
    );
  }
}

class AreaScore {
  final int score;
  final String label;
  final String reason;

  const AreaScore({this.score = 50, this.label = 'Steady', this.reason = ''});

  factory AreaScore.fromJson(dynamic json) {
    if (json is num || json is String) {
      final s = _score(json);
      return AreaScore(score: s, label: labelFor(s));
    }
    final j = fMap(json);
    final s = _score(j['score']);
    return AreaScore(score: s, label: fStr(j['label'], labelFor(s)), reason: fStr(j['reason']));
  }

  static String labelFor(int s) {
    if (s >= 80) return 'Strong';
    if (s >= 65) return 'Good';
    if (s >= 50) return 'Steady';
    if (s >= 35) return 'Careful';
    return 'Difficult';
  }
}

/// The five life areas, in display order.
class LifeArea {
  LifeArea._();
  static const career = 'career';
  static const love = 'love';
  static const money = 'money';
  static const health = 'health';
  static const mind = 'mind';
  static const all = [career, love, money, health, mind];

  static String label(String key) {
    switch (key) {
      case career:
        return 'Career';
      case love:
        return 'Love';
      case money:
        return 'Money';
      case health:
        return 'Health';
      case mind:
        return 'Mind';
      case 'travel':
        return 'Travel';
      case 'newBeginnings':
        return 'New beginnings';
      default:
        return key.isEmpty ? key : key[0].toUpperCase() + key.substring(1);
    }
  }
}

class ForecastScores {
  final Map<String, AreaScore> areas;

  const ForecastScores(this.areas);

  factory ForecastScores.fromJson(dynamic json) {
    final j = fMap(json);
    return ForecastScores({for (final k in LifeArea.all) k: AreaScore.fromJson(j[k])});
  }

  AreaScore operator [](String key) => areas[key] ?? const AreaScore();
  bool get isEmpty => areas.isEmpty;
}

class Transit {
  final String planet;
  final String sign;
  final double degree;
  final String nakshatra;
  final bool retrograde;
  final int houseFromMoon;
  final int houseFromLagna;
  final String effect;
  final String title;
  final String meaning;
  final List<String> realLife;
  final List<String> doList;
  final List<String> avoidList;
  final DateTime? since;
  final DateTime? until;

  const Transit({
    this.planet = '',
    this.sign = '',
    this.degree = 0,
    this.nakshatra = '',
    this.retrograde = false,
    this.houseFromMoon = 0,
    this.houseFromLagna = 0,
    this.effect = Effect.neutral,
    this.title = '',
    this.meaning = '',
    this.realLife = const [],
    this.doList = const [],
    this.avoidList = const [],
    this.since,
    this.until,
  });

  static int _house(dynamic v) {
    final h = fInt(v, 0);
    return (h >= 1 && h <= 12) ? h : 0;
  }

  factory Transit.fromJson(dynamic json) {
    final j = fMap(json);
    final planet = fStr(j['planet'], 'Planet');
    final sign = fStr(j['sign']);
    return Transit(
      planet: planet,
      sign: sign,
      degree: fDouble(j['degree']),
      nakshatra: fStr(j['nakshatra']),
      retrograde: fBool(j['retrograde']),
      houseFromMoon: _house(j['houseFromMoon']),
      houseFromLagna: _house(j['houseFromLagna']),
      effect: Effect.parse(j['effect']),
      title: fStr(j['title'], sign.isNotEmpty ? '$planet in $sign' : planet),
      meaning: fStr(j['meaning']),
      realLife: fStrList(j['realLife']),
      doList: fStrList(j['doList']),
      avoidList: fStrList(j['avoidList']),
      since: fDate(j['since']),
      until: fDate(j['until']),
    );
  }

  static const slowPlanets = ['Saturn', 'Jupiter', 'Rahu', 'Ketu'];
  bool get isSlow => slowPlanets.contains(planet);
}

class Aspect {
  final String transitPlanet;
  final String natalPlanet;
  final String aspect;
  final double orb;
  final String effect;
  final String meaning;

  const Aspect({
    this.transitPlanet = '',
    this.natalPlanet = '',
    this.aspect = '',
    this.orb = 0,
    this.effect = Effect.neutral,
    this.meaning = '',
  });

  factory Aspect.fromJson(dynamic json) {
    final j = fMap(json);
    return Aspect(
      transitPlanet: fStr(j['transitPlanet'], 'Planet'),
      natalPlanet: fStr(j['natalPlanet'], 'Planet'),
      aspect: fStr(j['aspect'], 'aspect').toLowerCase(),
      orb: fDouble(j['orb']),
      effect: Effect.parse(j['effect']),
      meaning: fStr(j['meaning']),
    );
  }

  String get title => 'Transit $transitPlanet ${aspect.isEmpty ? 'aspects' : aspect} your natal $natalPlanet';
}

class ForecastEvent {
  final DateTime? date;
  final String? time;
  final String type;
  final String title;
  final String description;
  final String personalImpact;
  final int importance;

  const ForecastEvent({
    this.date,
    this.time,
    this.type = 'festival',
    this.title = '',
    this.description = '',
    this.personalImpact = '',
    this.importance = 1,
  });

  factory ForecastEvent.fromJson(dynamic json) {
    final j = fMap(json);
    return ForecastEvent(
      date: fDate(j['date']),
      time: fStrOrNull(j['time']),
      type: fStr(j['type'], 'festival').toLowerCase(),
      title: fStr(j['title'], 'Event'),
      description: fStr(j['description']),
      personalImpact: fStr(j['personalImpact']),
      importance: fInt(j['importance'], 1).clamp(1, 3),
    );
  }

  bool get isFestival => type == 'festival' || type == 'ekadashi' || type == 'sankranti';
  bool get isEclipse => type == 'solar_eclipse' || type == 'lunar_eclipse';
}

class Remedy {
  final String title;
  final String mantra;
  final String action;
  final String color;
  final String? day;

  const Remedy({this.title = '', this.mantra = '', this.action = '', this.color = '', this.day});

  factory Remedy.fromJson(dynamic json) {
    final j = fMap(json);
    return Remedy(
      title: fStr(j['title']),
      mantra: fStr(j['mantra']),
      action: fStr(j['action']),
      color: fStr(j['color']),
      day: fStrOrNull(j['day']),
    );
  }

  bool get isEmpty => title.isEmpty && mantra.isEmpty && action.isEmpty;
}

class DashaNow {
  final String mahadasha;
  final String antardasha;
  final String pratyantardasha;
  final DateTime? mahadashaEnds;
  final DateTime? antardashaEnds;
  final DateTime? pratyantardashaEnds;
  final String theme;

  const DashaNow({
    this.mahadasha = '',
    this.antardasha = '',
    this.pratyantardasha = '',
    this.mahadashaEnds,
    this.antardashaEnds,
    this.pratyantardashaEnds,
    this.theme = '',
  });

  factory DashaNow.fromJson(dynamic json) {
    final j = fMap(json);
    return DashaNow(
      mahadasha: fStr(j['mahadasha']),
      antardasha: fStr(j['antardasha']),
      pratyantardasha: fStr(j['pratyantardasha']),
      mahadashaEnds: fDate(j['mahadashaEnds']),
      antardashaEnds: fDate(j['antardashaEnds']),
      pratyantardashaEnds: fDate(j['pratyantardashaEnds']),
      theme: fStr(j['theme']),
    );
  }

  bool get isEmpty => mahadasha.isEmpty;

  /// "Saturn – Mercury – Venus"
  String get chain => [mahadasha, antardasha, pratyantardasha].where((s) => s.isNotEmpty).join(' – ');

  List<String> get lords => [mahadasha, antardasha, pratyantardasha].where((s) => s.isNotEmpty).toList();
}

class CautionDay {
  final DateTime? date;
  final String reason;

  const CautionDay({this.date, this.reason = ''});

  factory CautionDay.fromJson(dynamic json) {
    final j = fMap(json);
    return CautionDay(date: fDate(j['date']), reason: fStr(j['reason']));
  }
}

class BestDays {
  final Map<String, List<DateTime>> byArea;

  const BestDays(this.byArea);

  static const keys = ['career', 'love', 'money', 'travel', 'newBeginnings'];

  factory BestDays.fromJson(dynamic json) {
    final j = fMap(json);
    return BestDays({for (final k in keys) k: fDateList(j[k])});
  }

  bool get isEmpty => byArea.values.every((l) => l.isEmpty);
}

// ---------------------------------------------------------------------------
// Day
// ---------------------------------------------------------------------------

class TaraBala {
  final String name;
  final int number;
  final bool favorable;
  final String meaning;

  const TaraBala({this.name = '', this.number = 0, this.favorable = true, this.meaning = ''});

  factory TaraBala.fromJson(dynamic json) {
    if (json is String) return TaraBala(name: json);
    final j = fMap(json);
    return TaraBala(
      name: fStr(j['name']),
      number: fInt(j['number'], 0).clamp(0, 9),
      favorable: fBool(j['favorable'], true),
      meaning: fStr(j['meaning']),
    );
  }
}

class MoonToday {
  final String sign;
  final String nakshatra;
  final int houseFromMoon;
  final int houseFromLagna;
  final TaraBala taraBala;
  final bool chandraBala;
  final bool chandrashtama;
  final String? changesSignAt;
  final String? nextSign;

  const MoonToday({
    this.sign = '',
    this.nakshatra = '',
    this.houseFromMoon = 0,
    this.houseFromLagna = 0,
    this.taraBala = const TaraBala(),
    this.chandraBala = true,
    this.chandrashtama = false,
    this.changesSignAt,
    this.nextSign,
  });

  factory MoonToday.fromJson(dynamic json) {
    final j = fMap(json);
    return MoonToday(
      sign: fStr(j['sign']),
      nakshatra: fStr(j['nakshatra']),
      houseFromMoon: fInt(j['houseFromMoon']),
      houseFromLagna: fInt(j['houseFromLagna']),
      taraBala: TaraBala.fromJson(j['taraBala']),
      chandraBala: fBool(j['chandraBala'], true),
      chandrashtama: fBool(j['chandrashtama']),
      changesSignAt: fStrOrNull(j['changesSignAt']),
      nextSign: fStrOrNull(j['nextSign']),
    );
  }
}

class BestTime {
  final String label;
  final String start;
  final String end;
  final String reason;

  const BestTime({this.label = '', this.start = '', this.end = '', this.reason = ''});

  factory BestTime.fromJson(dynamic json) {
    final j = fMap(json);
    return BestTime(
      label: fStr(j['label'], 'Good window'),
      start: fStr(j['start']),
      end: fStr(j['end']),
      reason: fStr(j['reason']),
    );
  }

  String get window => (start.isEmpty && end.isEmpty) ? '' : (end.isEmpty ? start : '$start – $end');
}

class ChoghadiyaSlot {
  final String name;
  final String time;
  final String status;

  const ChoghadiyaSlot({this.name = '', this.time = '', this.status = ''});

  factory ChoghadiyaSlot.fromJson(dynamic json) {
    final j = fMap(json);
    return ChoghadiyaSlot(name: fStr(j['name']), time: fStr(j['time']), status: fStr(j['status']));
  }
}

/// Compact view of the backend Panchang payload (all display strings).
class PanchangLite {
  final String vaar;
  final String tithi;
  final String paksha;
  final String nakshatra;
  final String yoga;
  final String karana;
  final String sunrise;
  final String sunset;
  final String moonrise;
  final String rahuKaal;
  final String abhijit;
  final String yamaganda;
  final String gulika;
  final List<ChoghadiyaSlot> choghadiya;

  const PanchangLite({
    this.vaar = '',
    this.tithi = '',
    this.paksha = '',
    this.nakshatra = '',
    this.yoga = '',
    this.karana = '',
    this.sunrise = '',
    this.sunset = '',
    this.moonrise = '',
    this.rahuKaal = '',
    this.abhijit = '',
    this.yamaganda = '',
    this.gulika = '',
    this.choghadiya = const [],
  });

  /// Panchang elements may be plain strings or `{name, ...}` objects.
  static String _el(dynamic v) {
    if (v is Map) return fStr(v['name'] ?? v['value']);
    return fStr(v);
  }

  factory PanchangLite.fromJson(dynamic json) {
    final j = fMap(json);
    return PanchangLite(
      vaar: _el(j['vaar'] ?? j['weekday']),
      tithi: _el(j['tithi']),
      paksha: _el(j['paksha']),
      nakshatra: _el(j['nakshatra']),
      yoga: _el(j['yoga']),
      karana: _el(j['karana']),
      sunrise: _el(j['sunrise']),
      sunset: _el(j['sunset']),
      moonrise: _el(j['moonrise']),
      rahuKaal: _el(j['rahuKaal']),
      abhijit: _el(j['abhijitMuhurat'] ?? j['abhijit']),
      yamaganda: _el(j['yamaganda']),
      gulika: _el(j['gulikaKaal'] ?? j['gulika']),
      choghadiya: fMapList(j['choghadiya']).map(ChoghadiyaSlot.fromJson).toList(),
    );
  }

  bool get isEmpty => tithi.isEmpty && nakshatra.isEmpty && sunrise.isEmpty;
}

class DayForecast {
  final DateTime date;
  final String weekday;
  final ForecastMeta meta;
  final ForecastSummary summary;
  final ForecastScores scores;
  final MoonToday moon;
  final DashaNow dasha;
  final List<Transit> transits;
  final List<Aspect> aspects;
  final List<ForecastEvent> events;
  final PanchangLite panchang;
  final List<String> goodFor;
  final List<String> avoid;
  final List<BestTime> bestTimes;
  final Remedy remedy;
  final String luckyColor;
  final int? luckyNumber;

  const DayForecast({
    required this.date,
    this.weekday = '',
    this.meta = const ForecastMeta(),
    this.summary = const ForecastSummary(),
    this.scores = const ForecastScores({}),
    this.moon = const MoonToday(),
    this.dasha = const DashaNow(),
    this.transits = const [],
    this.aspects = const [],
    this.events = const [],
    this.panchang = const PanchangLite(),
    this.goodFor = const [],
    this.avoid = const [],
    this.bestTimes = const [],
    this.remedy = const Remedy(),
    this.luckyColor = '',
    this.luckyNumber,
  });

  factory DayForecast.fromJson(dynamic json, {DateTime? fallbackDate}) {
    final j = fMap(json);
    final date = fDate(j['date']) ?? dateOnly(fallbackDate ?? DateTime.now());
    return DayForecast(
      date: date,
      weekday: fStr(j['weekday'], _weekdayName(date)),
      meta: ForecastMeta.fromJson(j),
      summary: ForecastSummary.fromJson(j['summary']),
      scores: ForecastScores.fromJson(j['scores']),
      moon: MoonToday.fromJson(j['moon']),
      dasha: DashaNow.fromJson(j['dasha']),
      transits: fMapList(j['transits']).map(Transit.fromJson).toList(),
      aspects: fMapList(j['aspects']).map(Aspect.fromJson).toList(),
      events: fMapList(j['events']).map(ForecastEvent.fromJson).toList(),
      panchang: PanchangLite.fromJson(j['panchang']),
      goodFor: fStrList(j['goodFor']),
      avoid: fStrList(j['avoid']),
      bestTimes: fMapList(j['bestTimes']).map(BestTime.fromJson).toList(),
      remedy: Remedy.fromJson(j['remedy']),
      luckyColor: fStr(j['luckyColor']),
      luckyNumber: fIntOrNull(j['luckyNumber']),
    );
  }
}

String _weekdayName(DateTime d) =>
    const ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'][d.weekday - 1];

// ---------------------------------------------------------------------------
// Week
// ---------------------------------------------------------------------------

class WeekDay {
  final DateTime date;
  final String weekday;
  final int score;
  final String mood;
  final String moonSign;
  final String taraBala;
  final bool taraFavorable;
  final bool chandrashtama;
  final String tithi;
  final String highlight;

  const WeekDay({
    required this.date,
    this.weekday = '',
    this.score = 50,
    this.mood = Mood.mixed,
    this.moonSign = '',
    this.taraBala = '',
    this.taraFavorable = true,
    this.chandrashtama = false,
    this.tithi = '',
    this.highlight = '',
  });

  static WeekDay? fromJson(dynamic json) {
    final j = fMap(json);
    final date = fDate(j['date']);
    if (date == null) return null;
    final score = _score(j['score']);
    return WeekDay(
      date: date,
      weekday: fStr(j['weekday'], _weekdayName(date)),
      score: score,
      mood: Mood.parse(j['mood'], score: score),
      moonSign: fStr(j['moonSign']),
      taraBala: fStr(j['taraBala'] is Map ? fMap(j['taraBala'])['name'] : j['taraBala']),
      taraFavorable: fBool(j['taraFavorable'], true),
      chandrashtama: fBool(j['chandrashtama']),
      tithi: fStr(j['tithi']),
      highlight: fStr(j['highlight']),
    );
  }
}

class WeekForecast {
  final DateTime weekStart;
  final DateTime weekEnd;
  final ForecastMeta meta;
  final ForecastSummary summary;
  final ForecastScores scores;
  final List<WeekDay> days;
  final BestDays bestDays;
  final List<CautionDay> cautionDays;
  final List<ForecastEvent> events;
  final DashaNow dasha;
  final String focus;
  final Remedy remedy;

  const WeekForecast({
    required this.weekStart,
    required this.weekEnd,
    this.meta = const ForecastMeta(),
    this.summary = const ForecastSummary(),
    this.scores = const ForecastScores({}),
    this.days = const [],
    this.bestDays = const BestDays({}),
    this.cautionDays = const [],
    this.events = const [],
    this.dasha = const DashaNow(),
    this.focus = '',
    this.remedy = const Remedy(),
  });

  factory WeekForecast.fromJson(dynamic json, {DateTime? fallbackStart}) {
    final j = fMap(json);
    final days = fList(j['days']).map(WeekDay.fromJson).whereType<WeekDay>().toList()
      ..sort((a, b) => a.date.compareTo(b.date));
    final start = fDate(j['weekStart']) ??
        (days.isNotEmpty ? days.first.date : mondayOf(fallbackStart ?? DateTime.now()));
    final end = fDate(j['weekEnd']) ?? start.add(const Duration(days: 6));
    return WeekForecast(
      weekStart: start,
      weekEnd: end,
      meta: ForecastMeta.fromJson(j),
      summary: ForecastSummary.fromJson(j['summary']),
      scores: ForecastScores.fromJson(j['scores']),
      days: days,
      bestDays: BestDays.fromJson(j['bestDays']),
      cautionDays: fMapList(j['cautionDays']).map(CautionDay.fromJson).toList(),
      events: fMapList(j['events']).map(ForecastEvent.fromJson).toList(),
      dasha: DashaNow.fromJson(j['dasha']),
      focus: fStr(j['focus']),
      remedy: Remedy.fromJson(j['remedy']),
    );
  }
}

// ---------------------------------------------------------------------------
// Month
// ---------------------------------------------------------------------------

class MonthDay {
  final DateTime date;
  final int score;
  final String mood;
  final String tithi;
  final String moonSign;
  final bool chandrashtama;
  final String? festival;
  final String highlight;

  const MonthDay({
    required this.date,
    this.score = 50,
    this.mood = Mood.mixed,
    this.tithi = '',
    this.moonSign = '',
    this.chandrashtama = false,
    this.festival,
    this.highlight = '',
  });

  static MonthDay? fromJson(dynamic json) {
    final j = fMap(json);
    final date = fDate(j['date']);
    if (date == null) return null;
    final score = _score(j['score']);
    return MonthDay(
      date: date,
      score: score,
      mood: Mood.parse(j['mood'], score: score),
      tithi: fStr(j['tithi']),
      moonSign: fStr(j['moonSign']),
      chandrashtama: fBool(j['chandrashtama']),
      festival: fStrOrNull(j['festival']),
      highlight: fStr(j['highlight']),
    );
  }
}

class MonthWeek {
  final DateTime? weekStart;
  final DateTime? weekEnd;
  final int score;
  final String headline;

  const MonthWeek({this.weekStart, this.weekEnd, this.score = 50, this.headline = ''});

  factory MonthWeek.fromJson(dynamic json) {
    final j = fMap(json);
    return MonthWeek(
      weekStart: fDate(j['weekStart']),
      weekEnd: fDate(j['weekEnd']),
      score: _score(j['score']),
      headline: fStr(j['headline']),
    );
  }
}

class MonthForecast {
  final DateTime month; // first day of month
  final String monthName;
  final ForecastMeta meta;
  final ForecastSummary summary;
  final ForecastScores scores;
  final List<MonthDay> days;
  final List<MonthWeek> weeks;
  final List<Transit> keyTransits;
  final List<ForecastEvent> events;
  final BestDays bestDays;
  final List<CautionDay> cautionDays;
  final DashaNow dasha;
  final Remedy remedy;

  const MonthForecast({
    required this.month,
    this.monthName = '',
    this.meta = const ForecastMeta(),
    this.summary = const ForecastSummary(),
    this.scores = const ForecastScores({}),
    this.days = const [],
    this.weeks = const [],
    this.keyTransits = const [],
    this.events = const [],
    this.bestDays = const BestDays({}),
    this.cautionDays = const [],
    this.dasha = const DashaNow(),
    this.remedy = const Remedy(),
  });

  static DateTime? _parseMonth(dynamic v) {
    final s = fStr(v);
    final m = RegExp(r'^(\d{4})-(\d{1,2})').firstMatch(s);
    if (m == null) return null;
    final mo = int.parse(m.group(2)!);
    if (mo < 1 || mo > 12) return null;
    return DateTime(int.parse(m.group(1)!), mo, 1);
  }

  factory MonthForecast.fromJson(dynamic json, {DateTime? fallbackMonth}) {
    final j = fMap(json);
    final days = fList(j['days']).map(MonthDay.fromJson).whereType<MonthDay>().toList()
      ..sort((a, b) => a.date.compareTo(b.date));
    final fb = fallbackMonth ?? DateTime.now();
    final month = _parseMonth(j['month']) ??
        (days.isNotEmpty ? DateTime(days.first.date.year, days.first.date.month, 1) : DateTime(fb.year, fb.month, 1));
    return MonthForecast(
      month: month,
      monthName: fStr(j['monthName']),
      meta: ForecastMeta.fromJson(j),
      summary: ForecastSummary.fromJson(j['summary']),
      scores: ForecastScores.fromJson(j['scores']),
      days: days,
      weeks: fMapList(j['weeks']).map(MonthWeek.fromJson).toList(),
      keyTransits: fMapList(j['keyTransits']).map(Transit.fromJson).toList(),
      events: fMapList(j['events']).map(ForecastEvent.fromJson).toList(),
      bestDays: BestDays.fromJson(j['bestDays']),
      cautionDays: fMapList(j['cautionDays']).map(CautionDay.fromJson).toList(),
      dasha: DashaNow.fromJson(j['dasha']),
      remedy: Remedy.fromJson(j['remedy']),
    );
  }

  MonthDay? dayFor(DateTime d) {
    for (final x in days) {
      if (sameDay(x.date, d)) return x;
    }
    return null;
  }
}

// ---------------------------------------------------------------------------
// Life timeline
// ---------------------------------------------------------------------------

class TimelineKind {
  TimelineKind._();
  static const sadeSati = 'sade_sati';
  static const ashtamaShani = 'ashtama_shani';
  static const kantakaShani = 'kantaka_shani';
  static const saturn = 'saturn_transit';
  static const jupiter = 'jupiter_transit';
  static const rahuKetu = 'rahu_ketu';
  static const mahadasha = 'mahadasha';
  static const antardasha = 'antardasha';

  static String label(String kind) {
    switch (kind) {
      case sadeSati:
        return 'Sade Sati';
      case ashtamaShani:
        return 'Ashtama Shani';
      case kantakaShani:
        return 'Kantaka Shani';
      case saturn:
        return 'Saturn transit';
      case jupiter:
        return 'Jupiter transit';
      case rahuKetu:
        return 'Rahu–Ketu axis';
      case mahadasha:
        return 'Mahadasha';
      case antardasha:
        return 'Antardasha';
      default:
        return kind.replaceAll('_', ' ');
    }
  }
}

class TimelinePeriod {
  final String id;
  final String kind;
  final String title;
  final DateTime? start;
  final DateTime? end;
  final String? phase;
  final String effect;
  final int intensity;
  final bool current;
  final String summary;
  final List<String> realLife;
  final List<String> advice;

  const TimelinePeriod({
    this.id = '',
    this.kind = '',
    this.title = '',
    this.start,
    this.end,
    this.phase,
    this.effect = Effect.neutral,
    this.intensity = 1,
    this.current = false,
    this.summary = '',
    this.realLife = const [],
    this.advice = const [],
  });

  factory TimelinePeriod.fromJson(dynamic json, {int index = 0}) {
    final j = fMap(json);
    final kind = fStr(j['kind']).toLowerCase();
    return TimelinePeriod(
      id: fStr(j['id'], '$kind-$index'),
      kind: kind,
      title: fStr(j['title'], TimelineKind.label(kind)),
      start: fDate(j['start']),
      end: fDate(j['end']),
      phase: fStrOrNull(j['phase']),
      effect: Effect.parse(j['effect']),
      intensity: fInt(j['intensity'], 1).clamp(1, 3),
      current: fBool(j['current']),
      summary: fStr(j['summary']),
      realLife: fStrList(j['realLife']),
      advice: fStrList(j['advice']),
    );
  }

  bool contains(DateTime d) {
    final s = start, e = end;
    if (s == null || e == null) return false;
    return !d.isBefore(s) && !d.isAfter(e);
  }
}

class LifeTimeline {
  final ForecastMeta meta;
  final DateTime now;
  final List<TimelinePeriod> periods;

  const LifeTimeline({required this.now, this.meta = const ForecastMeta(), this.periods = const []});

  factory LifeTimeline.fromJson(dynamic json) {
    final j = fMap(json);
    final list = fList(j['periods']);
    final periods = <TimelinePeriod>[
      for (var i = 0; i < list.length; i++)
        if (list[i] is Map) TimelinePeriod.fromJson(list[i], index: i),
    ];
    final far = DateTime(9999);
    periods.sort((a, b) => (a.start ?? far).compareTo(b.start ?? far));
    return LifeTimeline(
      now: fDate(j['now']) ?? dateOnly(DateTime.now()),
      meta: ForecastMeta.fromJson(j),
      periods: periods,
    );
  }
}
