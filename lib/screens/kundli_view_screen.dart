import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart' show DateFormat;
import 'package:provider/provider.dart';

import '../services/backend_service.dart';
import 'panchang_screen.dart';

// ============================================================================
// Shared Vedic helpers (used by KundliViewScreen, ChartTab and HomeTab)
// ============================================================================

const List<String> kZodiacSigns = kRashiNames;

const Map<int, String> kHouseMeanings = {
  1: 'Self, health & personality',
  2: 'Wealth, family & speech',
  3: 'Courage, siblings & skills',
  4: 'Home, mother & peace',
  5: 'Children, intellect & purva punya',
  6: 'Health, obstacles & service',
  7: 'Marriage, spouse & partners',
  8: 'Longevity, transformation & mystery',
  9: 'Fortune, dharma & father',
  10: 'Career, status & fame',
  11: 'Gains, income & friends',
  12: 'Losses, foreign lands & moksha',
};

class DivisionalChart {
  final String ascendant;
  final List<Map<String, dynamic>> planets;
  final bool lagnaApproximate;

  const DivisionalChart(this.ascendant, this.planets, this.lagnaApproximate);
}

class DashaPeriod {
  final String lord;
  final DateTime start;
  final DateTime end;

  const DashaPeriod(this.lord, this.start, this.end);

  bool contains(DateTime t) => !t.isBefore(start) && t.isBefore(end);
}

class VimshottariTimeline {
  final List<DashaPeriod> mahadashas;
  final DashaPeriod? currentMaha;
  final List<DashaPeriod> antardashas; // of the current mahadasha
  final DashaPeriod? currentAntar;

  const VimshottariTimeline(this.mahadashas, this.currentMaha, this.antardashas, this.currentAntar);
}

class Vedic {
  Vedic._();

  static const List<String> signShort = ['Ar', 'Ta', 'Ge', 'Cn', 'Le', 'Vi', 'Li', 'Sc', 'Sg', 'Cp', 'Aq', 'Pi'];
  static const List<String> signLords = [
    'Mars', 'Venus', 'Mercury', 'Moon', 'Sun', 'Mercury',
    'Venus', 'Mars', 'Jupiter', 'Saturn', 'Saturn', 'Jupiter',
  ];
  static const List<String> planetOrder = ['Sun', 'Moon', 'Mars', 'Mercury', 'Jupiter', 'Venus', 'Saturn', 'Rahu', 'Ketu'];
  static const Map<String, String> planetAbbr = {
    'Sun': 'Su', 'Moon': 'Mo', 'Mars': 'Ma', 'Mercury': 'Me', 'Jupiter': 'Ju',
    'Venus': 'Ve', 'Saturn': 'Sa', 'Rahu': 'Ra', 'Ketu': 'Ke',
  };
  static const List<String> dashaOrder = ['Ketu', 'Venus', 'Sun', 'Moon', 'Mars', 'Rahu', 'Jupiter', 'Saturn', 'Mercury'];
  static const Map<String, int> dashaYears = {
    'Ketu': 7, 'Venus': 20, 'Sun': 6, 'Moon': 10, 'Mars': 7, 'Rahu': 18, 'Jupiter': 16, 'Saturn': 19, 'Mercury': 17,
  };
  static const double _nakSpan = 360.0 / 27.0;
  static const Duration _istOffset = Duration(hours: 5, minutes: 30);

  // ---------------------------------------------------------------- parsing
  static double? toDouble(dynamic v) {
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v.trim());
    return null;
  }

  static int? toInt(dynamic v) {
    if (v is int) return v;
    if (v is num) return v.round();
    if (v is String) return int.tryParse(v.trim()) ?? double.tryParse(v.trim())?.round();
    return null;
  }

  static String text(dynamic v, [String fallback = '—']) {
    if (v == null) return fallback;
    final s = v.toString().trim();
    return (s.isEmpty || s == 'null') ? fallback : s;
  }

  static Map<String, dynamic> asMap(dynamic v) {
    if (v is Map) return Map<String, dynamic>.from(v);
    if (v is String && v.trim().startsWith('{')) {
      try {
        final d = jsonDecode(v);
        if (d is Map) return Map<String, dynamic>.from(d);
      } catch (_) {}
    }
    return <String, dynamic>{};
  }

  static List<Map<String, dynamic>> asMapList(dynamic v) {
    dynamic src = v;
    if (v is String && v.trim().startsWith('[')) {
      try {
        src = jsonDecode(v);
      } catch (_) {
        return [];
      }
    }
    if (src is! List) return [];
    return src.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
  }

  // ---------------------------------------------------------------- astrology
  static int signIndex(dynamic sign) {
    if (sign is num) {
      final i = sign.toInt();
      return (i >= 1 && i <= 12) ? i - 1 : -1;
    }
    final s = text(sign, '').toLowerCase();
    if (s.isEmpty) return -1;
    for (int i = 0; i < 12; i++) {
      if (s.startsWith(kZodiacSigns[i].toLowerCase())) return i;
    }
    return -1;
  }

  static String planetKey(dynamic name) {
    final s = text(name, '');
    for (final p in planetOrder) {
      if (s.toLowerCase().startsWith(p.toLowerCase())) return p;
    }
    return s.split(' ').first;
  }

  static String abbr(dynamic name) {
    final k = planetKey(name);
    return planetAbbr[k] ?? (k.length >= 2 ? k.substring(0, 2) : k);
  }

  static bool isNode(dynamic name) {
    final k = planetKey(name);
    return k == 'Rahu' || k == 'Ketu';
  }

  static bool isRetrograde(Map p) {
    final s = p['speed'];
    if (s is num) return s < 0;
    if (p['isRetrograde'] == true || p['retrograde'] == true) return true;
    return text(s, '').toLowerCase().contains('retro');
  }

  /// Chart label: "Sa(R)" for retrograde grahas (nodes are always retrograde, so not marked).
  static String chartLabel(Map p) {
    final a = abbr(p['name']);
    return (isRetrograde(p) && !isNode(p['name'])) ? '$a(R)' : a;
  }

  static double? degreeInSign(Map p) {
    final d = toDouble(p['degree']);
    if (d == null) return null;
    final r = d % 30;
    return r < 0 ? r + 30 : r;
  }

  static double? longitude(Map p) {
    final s = signIndex(p['sign']);
    final d = degreeInSign(p);
    if (s < 0 || d == null) return null;
    return s * 30.0 + d;
  }

  static String formatDegree(dynamic deg) {
    final d = toDouble(deg);
    if (d == null) return '—';
    var x = d % 30;
    if (x < 0) x += 30;
    final whole = x.floor();
    final min = ((x - whole) * 60).floor();
    return "$whole°${min.toString().padLeft(2, '0')}'";
  }

  /// D9 Navamsha: movable/fire signs start from Aries, earth from Capricorn,
  /// air from Libra, water from Cancer (equivalently: element-based start).
  static int navamshaSignIndex(double lon) {
    final l = ((lon % 360) + 360) % 360;
    final signIdx = (l / 30).floor() % 12;
    final navIdx = math.min(8, ((l % 30) / (30 / 9)).floor());
    const startByElement = [0, 9, 6, 3]; // fire, earth, air, water
    return (startByElement[signIdx % 4] + navIdx) % 12;
  }

  /// D10 Dasamsha: odd signs count from the sign itself, even signs from the 9th.
  static int dasamshaSignIndex(double lon) {
    final l = ((lon % 360) + 360) % 360;
    final signIdx = (l / 30).floor() % 12;
    final dasIdx = math.min(9, ((l % 30) / 3).floor());
    final start = signIdx.isEven ? signIdx : (signIdx + 8) % 12;
    return (start + dasIdx) % 12;
  }

  static int _orderIndex(Map p) {
    final i = planetOrder.indexOf(planetKey(p['name']));
    return i < 0 ? 99 : i;
  }

  /// Normalises planets and (re)computes whole-sign houses from the ascendant.
  static List<Map<String, dynamic>> placePlanets(List<Map<String, dynamic>> planets, int ascIdx) {
    final placed = planets.map((p) {
      final s = signIndex(p['sign']);
      int? house = toInt(p['house']);
      if (ascIdx >= 0 && s >= 0) house = ((s - ascIdx + 12) % 12) + 1;
      return <String, dynamic>{...p, 'house': house};
    }).toList();
    placed.sort((a, b) => _orderIndex(a).compareTo(_orderIndex(b)));
    return placed;
  }

  static List<Map<String, dynamic>> d1Planets(Map kundli) =>
      placePlanets(asMapList(kundli['planetaryPositions']), signIndex(kundli['ascendant']));

  static DivisionalChart divisional(Map kundli, int division) {
    final key = division == 9 ? 'd9Navamsha' : 'd10Dasamsha';
    final server = asMap(kundli[key]);
    final serverPlanets = asMapList(server['planetaryPositions']);
    final serverAsc = signIndex(server['ascendant']);
    if (serverAsc >= 0 && serverPlanets.isNotEmpty) {
      return DivisionalChart(kZodiacSigns[serverAsc], placePlanets(serverPlanets, serverAsc), false);
    }

    final fn = division == 9 ? navamshaSignIndex : dasamshaSignIndex;
    final ascIdx = signIndex(kundli['ascendant']);
    final ascDeg = toDouble(kundli['ascendantDegree']);
    int vAsc = 0;
    bool approx = true;
    if (ascIdx >= 0 && ascDeg != null) {
      vAsc = fn(ascIdx * 30.0 + (ascDeg % 30));
      approx = false;
    } else if (ascIdx >= 0) {
      vAsc = fn(ascIdx * 30.0 + 15.0);
    }

    final planets = <Map<String, dynamic>>[];
    for (final p in asMapList(kundli['planetaryPositions'])) {
      final lon = longitude(p);
      if (lon == null) continue;
      planets.add({...p, 'sign': kZodiacSigns[fn(lon)]});
    }
    return DivisionalChart(kZodiacSigns[vAsc], placePlanets(planets, vAsc), approx);
  }

  // ---------------------------------------------------------------- profile
  /// The kundli currently in focus (selected family member or self), or null if none exists.
  static Map<String, dynamic>? activeKundli(BackendService s) {
    final fam = s.selectedFamilyMember;
    if (fam != null && fam['kundli'] != null) {
      final k = asMap(fam['kundli']);
      return {
        ...k,
        'nakshatraPada': k['nakshatraPada'] ?? k['nakshatra_pada'],
        'birthDetails': {
          ...asMap(k['birthDetails']),
          'fullName': fam['fullName'],
          'relationship': fam['relationship'],
          'gender': fam['gender'],
          'dateOfBirth': fam['dateOfBirth'],
          'timeOfBirth': fam['timeOfBirth'],
          'placeOfBirth': fam['placeOfBirth'],
        },
      };
    }
    final k = s.kundliData;
    if (k == null || signIndex(k['ascendant']) < 0) return null;
    return {...k, 'nakshatraPada': k['nakshatraPada'] ?? k['nakshatra_pada']};
  }

  static String displayName(Map? kundli, {BackendService? service}) {
    final b = asMap(kundli?['birthDetails']);
    final n = text(b['fullName'], '');
    if (n.isNotEmpty) return n;
    final u = text(service?.user?['fullName'], '');
    return u.isNotEmpty ? u : 'Seeker';
  }

  static String identity(Map kundli) {
    final b = asMap(kundli['birthDetails']);
    return '${b['fullName']}|${b['dateOfBirth']}|${b['timeOfBirth']}|${kundli['ascendant']}|${b['relationship']}';
  }

  /// Parses the birth date + time (entered in IST) into a UTC instant.
  static DateTime? birthUtc(Map kundli) {
    final b = asMap(kundli['birthDetails']);
    final dobRaw = text(b['dateOfBirth'] ?? kundli['dateOfBirth'], '');
    if (dobRaw.isEmpty) return null;

    int? y, mo, d;
    if (dobRaw.contains('T')) {
      final parsed = DateTime.tryParse(dobRaw);
      if (parsed == null) return null;
      // Postgres DATE columns are serialised as UTC midnight of the IST date.
      final local = parsed.isUtc ? parsed.add(_istOffset) : parsed;
      y = local.year;
      mo = local.month;
      d = local.day;
    } else {
      final parts = dobRaw.split(RegExp(r'[-/ .]+')).where((e) => e.isNotEmpty).toList();
      if (parts.length < 3) return null;
      if (parts[0].length == 4) {
        y = int.tryParse(parts[0]);
        mo = int.tryParse(parts[1]);
        d = int.tryParse(parts[2]);
      } else {
        d = int.tryParse(parts[0]);
        mo = int.tryParse(parts[1]);
        y = int.tryParse(parts[2]);
      }
    }
    if (y == null || mo == null || d == null || mo < 1 || mo > 12 || d < 1 || d > 31) return null;

    int h = 12, m = 0;
    final tobRaw = text(b['timeOfBirth'] ?? kundli['timeOfBirth'], '');
    final tm = RegExp(r'(\d{1,2})\s*:\s*(\d{2})').firstMatch(tobRaw);
    if (tm != null) {
      h = int.parse(tm.group(1)!);
      m = int.parse(tm.group(2)!);
      final lower = tobRaw.toLowerCase();
      if (lower.contains('pm') && h < 12) h += 12;
      if (lower.contains('am') && h == 12) h = 0;
    }
    if (h > 23 || m > 59) return null;
    return DateTime.utc(y, mo, d, h, m).subtract(_istOffset);
  }

  /// Vimshottari Mahadasha / Antardasha timeline from the Moon's exact longitude.
  static VimshottariTimeline? vimshottari(Map kundli, {DateTime? now}) {
    final birth = birthUtc(kundli);
    if (birth == null) return null;
    Map<String, dynamic>? moon;
    for (final p in asMapList(kundli['planetaryPositions'])) {
      if (planetKey(p['name']) == 'Moon') moon = p;
    }
    if (moon == null) return null;
    final lon = longitude(moon);
    if (lon == null) return null;

    const yearMs = 365.25 * 86400000;
    Duration years(double y) => Duration(milliseconds: (y * yearMs).round());

    final nakIdx = (lon / _nakSpan).floor() % 27;
    final elapsed = (lon % _nakSpan) / _nakSpan;
    final firstIdx = nakIdx % 9;
    final firstLord = dashaOrder[firstIdx];
    var cursor = birth.subtract(years(dashaYears[firstLord]! * elapsed));

    final mahas = <DashaPeriod>[];
    for (int i = 0; i < 9; i++) {
      final lord = dashaOrder[(firstIdx + i) % 9];
      final end = cursor.add(years(dashaYears[lord]!.toDouble()));
      mahas.add(DashaPeriod(lord, cursor, end));
      cursor = end;
    }

    final t = (now ?? DateTime.now()).toUtc();
    DashaPeriod? cur;
    for (final md in mahas) {
      if (md.contains(t)) cur = md;
    }

    final antars = <DashaPeriod>[];
    DashaPeriod? curAntar;
    if (cur != null) {
      final mdIdx = dashaOrder.indexOf(cur.lord);
      var c = cur.start;
      for (int j = 0; j < 9; j++) {
        final lord = dashaOrder[(mdIdx + j) % 9];
        final len = dashaYears[cur.lord]! * dashaYears[lord]! / 120.0;
        final end = j == 8 ? cur.end : c.add(years(len));
        final ad = DashaPeriod(lord, c, end);
        antars.add(ad);
        if (ad.contains(t)) curAntar = ad;
        c = end;
      }
    }
    return VimshottariTimeline(mahas, cur, antars, curAntar);
  }

  // ---------------------------------------------------------------- avakhada
  static const List<String> _gana = [
    'Deva', 'Manushya', 'Rakshasa', 'Manushya', 'Deva', 'Manushya', 'Deva', 'Deva', 'Rakshasa',
    'Rakshasa', 'Manushya', 'Manushya', 'Deva', 'Rakshasa', 'Deva', 'Rakshasa', 'Deva', 'Rakshasa',
    'Rakshasa', 'Manushya', 'Manushya', 'Deva', 'Rakshasa', 'Rakshasa', 'Manushya', 'Manushya', 'Deva',
  ];
  static const List<String> _nadi = [
    'Adi', 'Madhya', 'Antya', 'Antya', 'Madhya', 'Adi', 'Adi', 'Madhya', 'Antya',
    'Antya', 'Madhya', 'Adi', 'Adi', 'Madhya', 'Antya', 'Antya', 'Madhya', 'Adi',
    'Adi', 'Madhya', 'Antya', 'Antya', 'Madhya', 'Adi', 'Adi', 'Madhya', 'Antya',
  ];
  static const List<String> _yoni = [
    'Horse', 'Elephant', 'Sheep', 'Serpent', 'Serpent', 'Dog', 'Cat', 'Sheep', 'Cat',
    'Rat', 'Rat', 'Cow', 'Buffalo', 'Tiger', 'Buffalo', 'Tiger', 'Deer', 'Deer',
    'Dog', 'Monkey', 'Mongoose', 'Monkey', 'Lion', 'Horse', 'Lion', 'Cow', 'Elephant',
  ];
  static const List<String> _varna = [
    'Kshatriya', 'Vaishya', 'Shudra', 'Brahmin', 'Kshatriya', 'Vaishya',
    'Shudra', 'Brahmin', 'Kshatriya', 'Vaishya', 'Shudra', 'Brahmin',
  ];
  static const List<String> _tatwa = ['Fire', 'Earth', 'Air', 'Water'];

  static String _vashya(int signIdx, double? degInSign) {
    final firstHalf = (degInSign ?? 0) < 15;
    switch (signIdx) {
      case 0:
      case 1:
        return 'Chatushpada';
      case 3:
      case 11:
        return 'Jalachara';
      case 4:
        return 'Vanachara';
      case 7:
        return 'Keeta';
      case 8:
        return firstHalf ? 'Manava' : 'Chatushpada';
      case 9:
        return firstHalf ? 'Chatushpada' : 'Jalachara';
      default:
        return 'Manava';
    }
  }

  static String _paya(int moonHouse) {
    if ([1, 6, 11].contains(moonHouse)) return 'Gold (Swarna)';
    if ([2, 5, 9].contains(moonHouse)) return 'Silver (Rajat)';
    if ([3, 7, 10].contains(moonHouse)) return 'Copper (Tamra)';
    return 'Iron (Loha)';
  }

  /// Avakhada Chakra derived from the Moon (falls back to the server payload).
  static Map<String, String> avakhada(Map kundli) {
    final server = asMap(kundli['avakhada']);
    Map<String, dynamic>? moon;
    for (final p in asMapList(kundli['planetaryPositions'])) {
      if (planetKey(p['name']) == 'Moon') moon = p;
    }
    final lon = moon != null ? longitude(moon) : null;
    final moonSignIdx = lon != null ? (lon / 30).floor() % 12 : signIndex(kundli['moonSign']);
    int nakIdx = lon != null ? (lon / _nakSpan).floor() % 27 : kNakshatraNames.indexOf(text(kundli['nakshatra'], ''));
    final ascIdx = signIndex(kundli['ascendant']);

    if (moonSignIdx < 0 || nakIdx < 0) {
      return server.map((k, v) => MapEntry(k, text(v)));
    }
    final moonHouse = ascIdx >= 0 ? ((moonSignIdx - ascIdx + 12) % 12) + 1 : 0;

    return {
      'Varna': _varna[moonSignIdx],
      'Vashya': _vashya(moonSignIdx, moon != null ? degreeInSign(moon) : null),
      'Yoni': _yoni[nakIdx],
      'Gana': _gana[nakIdx],
      'Nadi': _nadi[nakIdx],
      'Tatwa': _tatwa[moonSignIdx % 4],
      if (moonHouse > 0) 'Paya': _paya(moonHouse),
      'Rasi Lord': signLords[moonSignIdx],
      'Nakshatra Lord': dashaOrder[nakIdx % 9],
      if (ascIdx >= 0) 'Lagna Lord': signLords[ascIdx],
    };
  }

  /// Panchang at birth (computed from the birth instant, else server payload).
  static Map<String, String> birthPanchang(Map kundli) {
    final birth = birthUtc(kundli);
    final server = asMap(kundli['panchang']);
    if (birth == null) {
      return {
        if (server['tithi'] != null) 'Tithi': text(server['tithi']),
        if (server['vaar'] != null) 'Vaar': text(server['vaar']),
        'Nakshatra': text(kundli['nakshatra'] ?? server['nakshatra']),
        if (server['yoga'] != null) 'Yoga': text(server['yoga']),
        if (server['karana'] != null) 'Karana': text(server['karana']),
      };
    }
    final lat = toDouble(kundli['latitude']) ?? 28.6139;
    final lon = toDouble(kundli['longitude']) ?? 77.2090;
    final s = PanchangCalculator.snapshotAt(birth, lat: lat, lon: lon);
    final pada = toInt(kundli['nakshatraPada']);
    final nak = text(kundli['nakshatra'], s.nakshatra);
    return {
      'Tithi': '${s.tithi} (${s.paksha})',
      'Vaar': s.vaar,
      'Nakshatra': pada != null ? '$nak (Pada $pada)' : nak,
      'Yoga': s.yoga,
      'Karana': s.karana,
    };
  }
}

// ============================================================================
// Chart rendering (North & South Indian styles)
// ============================================================================

enum ChartStyle { north, south }

class KundliChart extends StatelessWidget {
  final String ascendant;
  final List<Map<String, dynamic>> planets;
  final ChartStyle style;
  final String centerLabel;
  final double maxSize;

  const KundliChart({
    super.key,
    required this.ascendant,
    required this.planets,
    required this.style,
    required this.centerLabel,
    this.maxSize = 360,
  });

  @override
  Widget build(BuildContext context) {
    final ascIdx = Vedic.signIndex(ascendant);
    final summary = planets.map((p) => '${Vedic.planetKey(p['name'])} in house ${p['house']}').join(', ');
    return LayoutBuilder(builder: (context, constraints) {
      final size = math.min(constraints.maxWidth, maxSize);
      return Center(
        child: Semantics(
          label: '$centerLabel chart, ascendant $ascendant. $summary',
          child: SizedBox.square(
            dimension: size,
            child: CustomPaint(
              painter: style == ChartStyle.north
                  ? NorthIndianChartPainter(ascIdx: ascIdx, planets: planets, centerLabel: centerLabel)
                  : SouthIndianChartPainter(ascIdx: ascIdx, planets: planets, centerLabel: centerLabel),
            ),
          ),
        ),
      );
    });
  }
}

const Color _chartLine = Color(0xFF7C77E6);
const Color _chartBg = Color(0xFFFCF7F1);
const Color _chartAccent = Color(0xFFD95D39);

void _drawLabelBlock(
  Canvas canvas,
  List<String> items,
  Offset center,
  int perLine,
  double fontSize, {
  Color color = Colors.black,
  List<bool>? highlight,
}) {
  if (items.isEmpty) return;
  final spans = <TextSpan>[];
  for (int i = 0; i < items.length; i++) {
    if (i > 0) spans.add(TextSpan(text: i % perLine == 0 ? '\n' : ' '));
    final hl = highlight != null && i < highlight.length && highlight[i];
    spans.add(TextSpan(text: items[i], style: TextStyle(color: hl ? _chartAccent : color)));
  }
  final tp = TextPainter(
    text: TextSpan(
      style: TextStyle(fontSize: fontSize, fontWeight: FontWeight.w800, height: 1.15, color: color),
      children: spans,
    ),
    textAlign: TextAlign.center,
    textDirection: TextDirection.ltr,
  )..layout();
  tp.paint(canvas, Offset(center.dx - tp.width / 2, center.dy - tp.height / 2));
}

class NorthIndianChartPainter extends CustomPainter {
  final int ascIdx;
  final List<Map<String, dynamic>> planets;
  final String centerLabel;

  NorthIndianChartPainter({required this.ascIdx, required this.planets, required this.centerLabel});

  // (planet label centre, sign number centre, labels per line) for houses 1..12
  static const List<List<double>> _layout = [
    [0.50, 0.20, 0.50, 0.42, 2],
    [0.25, 0.085, 0.25, 0.20, 3],
    [0.085, 0.25, 0.20, 0.25, 1],
    [0.22, 0.50, 0.42, 0.50, 2],
    [0.085, 0.75, 0.20, 0.75, 1],
    [0.25, 0.915, 0.25, 0.80, 3],
    [0.50, 0.80, 0.50, 0.58, 2],
    [0.75, 0.915, 0.75, 0.80, 3],
    [0.915, 0.75, 0.80, 0.75, 1],
    [0.78, 0.50, 0.58, 0.50, 2],
    [0.915, 0.25, 0.80, 0.25, 1],
    [0.75, 0.085, 0.75, 0.20, 3],
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final line = Paint()
      ..color = _chartLine
      ..strokeWidth = 1.6
      ..style = PaintingStyle.stroke;
    final rect = Rect.fromLTWH(0, 0, w, h);
    canvas.drawRect(rect, Paint()..color = _chartBg);
    canvas.drawRect(rect.deflate(0.8), line);
    canvas.drawLine(Offset.zero, Offset(w, h), line);
    canvas.drawLine(Offset(w, 0), Offset(0, h), line);
    canvas.drawPath(
      Path()
        ..moveTo(w / 2, 0)
        ..lineTo(w, h / 2)
        ..lineTo(w / 2, h)
        ..lineTo(0, h / 2)
        ..close(),
      line,
    );

    final base = (w * 0.036).clamp(8.0, 13.0);
    final start = ascIdx >= 0 ? ascIdx : 0;

    final byHouse = List.generate(12, (_) => <String>[]);
    for (final p in planets) {
      final house = Vedic.toInt(p['house']);
      if (house != null && house >= 1 && house <= 12) byHouse[house - 1].add(Vedic.chartLabel(p));
    }

    for (int i = 0; i < 12; i++) {
      final cfg = _layout[i];
      // Sign number (1 = Aries ... 12 = Pisces)
      _drawLabelBlock(canvas, ['${(start + i) % 12 + 1}'], Offset(w * cfg[2], h * cfg[3]), 1, base * 0.95,
          color: _chartAccent);
      final items = <String>[if (i == 0) 'Asc', ...byHouse[i]];
      _drawLabelBlock(
        canvas,
        items,
        Offset(w * cfg[0], h * cfg[1]),
        cfg[4].toInt(),
        items.length > 4 ? base * 0.85 : base,
        highlight: [if (i == 0) true],
      );
    }
  }

  @override
  bool shouldRepaint(covariant NorthIndianChartPainter old) =>
      old.ascIdx != ascIdx || old.centerLabel != centerLabel || !identical(old.planets, planets);
}

class SouthIndianChartPainter extends CustomPainter {
  final int ascIdx;
  final List<Map<String, dynamic>> planets;
  final String centerLabel;

  SouthIndianChartPainter({required this.ascIdx, required this.planets, required this.centerLabel});

  // Fixed sign cells (row, col): Pisces top-left, clockwise.
  static const List<List<int>> _cells = [
    [0, 1], [0, 2], [0, 3], [1, 3], [2, 3], [3, 3], [3, 2], [3, 1], [3, 0], [2, 0], [1, 0], [0, 0],
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final cw = w / 4, ch = h / 4;
    final line = Paint()
      ..color = _chartLine
      ..strokeWidth = 1.6
      ..style = PaintingStyle.stroke;
    canvas.drawRect(Rect.fromLTWH(0, 0, w, h), Paint()..color = _chartBg);
    canvas.drawRect(Rect.fromLTWH(0, 0, w, h).deflate(0.8), line);
    // Full-length lines
    canvas.drawLine(Offset(0, ch), Offset(w, ch), line);
    canvas.drawLine(Offset(0, 3 * ch), Offset(w, 3 * ch), line);
    canvas.drawLine(Offset(cw, 0), Offset(cw, h), line);
    canvas.drawLine(Offset(3 * cw, 0), Offset(3 * cw, h), line);
    // Partial lines (skip the merged centre)
    canvas.drawLine(Offset(0, 2 * ch), Offset(cw, 2 * ch), line);
    canvas.drawLine(Offset(3 * cw, 2 * ch), Offset(w, 2 * ch), line);
    canvas.drawLine(Offset(2 * cw, 0), Offset(2 * cw, ch), line);
    canvas.drawLine(Offset(2 * cw, 3 * ch), Offset(2 * cw, h), line);

    final base = (w * 0.036).clamp(8.0, 13.0);

    final bySign = List.generate(12, (_) => <String>[]);
    for (final p in planets) {
      final s = Vedic.signIndex(p['sign']);
      if (s >= 0) bySign[s].add(Vedic.chartLabel(p));
    }

    for (int s = 0; s < 12; s++) {
      final r = _cells[s][0], c = _cells[s][1];
      final x0 = c * cw, y0 = r * ch;
      final signTp = TextPainter(
        text: TextSpan(
          text: Vedic.signShort[s],
          style: TextStyle(fontSize: base * 0.8, color: Colors.grey.shade600, fontWeight: FontWeight.w600),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      signTp.paint(canvas, Offset(x0 + cw - signTp.width - 4, y0 + 3));

      final isAsc = s == ascIdx;
      if (isAsc) {
        final accent = Paint()
          ..color = _chartAccent
          ..strokeWidth = 1.6;
        canvas.drawLine(Offset(x0, y0 + ch * 0.32), Offset(x0 + cw * 0.32, y0), accent);
      }
      final items = <String>[if (isAsc) 'Asc', ...bySign[s]];
      _drawLabelBlock(
        canvas,
        items,
        Offset(x0 + cw / 2, y0 + ch * 0.58),
        2,
        items.length > 4 ? base * 0.85 : base,
        highlight: [if (isAsc) true],
      );
    }

    _drawLabelBlock(
      canvas,
      [centerLabel, if (ascIdx >= 0) 'Lagna: ${kZodiacSigns[ascIdx]}'],
      Offset(w / 2, h / 2),
      1,
      base,
      color: _chartLine,
    );
  }

  @override
  bool shouldRepaint(covariant SouthIndianChartPainter old) =>
      old.ascIdx != ascIdx || old.centerLabel != centerLabel || !identical(old.planets, planets);
}

class ChartStyleToggle extends StatelessWidget {
  final ChartStyle value;
  final ValueChanged<ChartStyle> onChanged;

  const ChartStyleToggle({super.key, required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    Widget seg(ChartStyle s, String label) {
      final selected = value == s;
      return Expanded(
        child: Material(
          color: selected ? const Color(0xFF1E1A17) : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          child: InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: () => onChanged(s),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                label,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: selected ? Colors.white : Colors.black87,
                ),
              ),
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: const Color(0xFFFCF7F1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Row(children: [seg(ChartStyle.north, 'North Indian'), seg(ChartStyle.south, 'South Indian')]),
    );
  }
}

// ============================================================================
// AI report (markdown-ish) renderer
// ============================================================================

class KundliReportView extends StatelessWidget {
  final String report;
  const KundliReportView({super.key, required this.report});

  static final RegExp _heading = RegExp(r'^\s*#{1,6}\s*(.+)$');

  @override
  Widget build(BuildContext context) {
    final sections = <List<String>>[]; // [title, body]
    String? title;
    final body = StringBuffer();
    void flush() {
      final b = body.toString().trim();
      if ((title ?? '').isNotEmpty || b.isNotEmpty) sections.add([title ?? '', b]);
      body.clear();
    }

    for (final raw in report.split('\n')) {
      final m = _heading.firstMatch(raw);
      if (m != null) {
        flush();
        title = m.group(1)!.replaceAll('**', '').trim();
      } else {
        final trimmed = raw.trimRight();
        body.writeln(trimmed.startsWith(RegExp(r'\s*[-*]\s+')) ? trimmed.replaceFirst(RegExp(r'^\s*[-*]\s+'), '• ') : trimmed);
      }
    }
    flush();

    if (sections.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(child: Text('The report is empty. Please try again.')),
      );
    }

    return Column(children: sections.map((s) => _section(s[0], s[1])).toList());
  }

  Widget _section(String title, String body) {
    Color c = const Color(0xFF6C63FF);
    IconData icon = Icons.stars_rounded;
    final t = title.toLowerCase();
    if (t.contains('personality')) {
      c = const Color(0xFF317BEA);
      icon = Icons.person_rounded;
    } else if (t.contains('physical')) {
      c = const Color(0xFF00B894);
      icon = Icons.fitness_center_rounded;
    } else if (t.contains('health')) {
      c = const Color(0xFFE17055);
      icon = Icons.health_and_safety_rounded;
    } else if (t.contains('career') || t.contains('wealth')) {
      c = const Color(0xFFFF9800);
      icon = Icons.work_rounded;
    } else if (t.contains('marriage') || t.contains('relationship')) {
      c = const Color(0xFFE84393);
      icon = Icons.favorite_rounded;
    } else if (t.contains('dasha')) {
      c = const Color(0xFF9C27B0);
      icon = Icons.hourglass_bottom_rounded;
    } else if (t.contains('summary') || t.contains('final') || t.contains('guidance')) {
      c = const Color(0xFFD95D39);
      icon = Icons.workspace_premium_rounded;
    }

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: c.withValues(alpha: 0.25)),
        boxShadow: [BoxShadow(color: c.withValues(alpha: 0.05), blurRadius: 10, offset: const Offset(0, 4))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (title.isNotEmpty) ...[
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(color: c.withValues(alpha: 0.12), shape: BoxShape.circle),
                  child: Icon(icon, color: c, size: 18),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.black.withValues(alpha: 0.85)),
                  ),
                ),
              ],
            ),
            if (body.isNotEmpty) ...[
              const SizedBox(height: 10),
              const Divider(height: 1),
              const SizedBox(height: 10),
            ],
          ],
          if (body.isNotEmpty) SelectableText.rich(TextSpan(children: _spans(body))),
        ],
      ),
    );
  }

  static List<TextSpan> _spans(String text) {
    const normal = TextStyle(color: Color(0xFF2D3748), fontSize: 14, height: 1.55);
    const bold = TextStyle(color: Colors.black, fontWeight: FontWeight.w800, fontSize: 14, height: 1.55);
    final spans = <TextSpan>[];
    final exp = RegExp(r'\*\*(.+?)\*\*');
    int start = 0;
    for (final m in exp.allMatches(text)) {
      if (m.start > start) spans.add(TextSpan(text: text.substring(start, m.start), style: normal));
      spans.add(TextSpan(text: m.group(1), style: bold));
      start = m.end;
    }
    if (start < text.length) spans.add(TextSpan(text: text.substring(start), style: normal));
    return spans;
  }
}

// ============================================================================
// Shared small widgets
// ============================================================================

/// Shown when the user has not generated a Kundli yet.
class KundliEmptyState extends StatelessWidget {
  const KundliEmptyState({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(color: const Color(0xFF6C63FF).withValues(alpha: 0.1), shape: BoxShape.circle),
              child: const Icon(Icons.auto_awesome, color: Color(0xFF6C63FF), size: 40),
            ),
            const SizedBox(height: 18),
            const Text(
              'Create your Vedic Kundli',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: Colors.black),
            ),
            const SizedBox(height: 8),
            Text(
              'Add your date, time and place of birth to see your birth chart, divisional charts, dashas and a full life report.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: Colors.grey.shade700, height: 1.4),
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: () => Navigator.pushNamed(context, '/birth-details'),
              icon: const Icon(Icons.edit_calendar_rounded),
              label: const Text('Add birth details'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF6C63FF),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Bottom sheet that switches the active Kundli profile (self / family members).
Future<void> showKundliProfilePicker(BuildContext context) {
  final service = Provider.of<BackendService>(context, listen: false);
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.white,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    builder: (ctx) => _ProfilePickerSheet(service: service),
  );
}

class _ProfilePickerSheet extends StatefulWidget {
  final BackendService service;
  const _ProfilePickerSheet({required this.service});

  @override
  State<_ProfilePickerSheet> createState() => _ProfilePickerSheetState();
}

class _ProfilePickerSheetState extends State<_ProfilePickerSheet> {
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    if (widget.service.isAuthenticated) _refresh();
  }

  Future<void> _refresh() async {
    setState(() => _loading = true);
    try {
      await widget.service.fetchFamilyKundlis();
    } catch (_) {}
    if (!mounted) return;
    setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.service;
    final members = s.familyMembers;
    final selected = s.selectedFamilyMember;
    final selfName = Vedic.displayName(s.kundliData, service: s);

    Widget tile({required String title, required String subtitle, required bool active, required VoidCallback onTap}) {
      return ListTile(
        onTap: onTap,
        leading: CircleAvatar(
          backgroundColor: const Color(0xFF6C63FF).withValues(alpha: 0.12),
          child: Text(title.isNotEmpty ? title[0].toUpperCase() : '?',
              style: const TextStyle(color: Color(0xFF6C63FF), fontWeight: FontWeight.bold)),
        ),
        title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis),
        trailing: active ? const Icon(Icons.check_circle_rounded, color: Color(0xFF6C63FF)) : null,
      );
    }

    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.7),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 8, 4),
              child: Row(
                children: [
                  const Expanded(
                    child: Text('Switch Kundli profile', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
                  ),
                  IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
                ],
              ),
            ),
            if (_loading) const LinearProgressIndicator(minHeight: 2),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  tile(
                    title: selfName,
                    subtitle: s.hasBirthDetails ? 'My Kundli · ${Vedic.text(s.kundliData?['ascendant'])} Lagna' : 'Birth details not added yet',
                    active: selected == null,
                    onTap: () {
                      s.selectFamilyMember(null);
                      Navigator.pop(context);
                    },
                  ),
                  ...members.where((m) => m['kundli'] != null).map((m) => tile(
                        title: Vedic.text(m['fullName'], 'Family member'),
                        subtitle: '${Vedic.text(m['relationship'], 'Family')} · ${Vedic.text(Vedic.asMap(m['kundli'])['ascendant'])} Lagna',
                        active: selected != null && selected['id'] == m['id'],
                        onTap: () {
                          s.selectFamilyMember(m);
                          Navigator.pop(context);
                        },
                      )),
                  if (!_loading && members.isEmpty)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                      child: Text(
                        s.isAuthenticated
                            ? 'No family Kundlis yet. Add them from the More tab.'
                            : 'Log in to add and switch between family Kundlis.',
                        style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================================
// KundliExplorer – sub-tabs + content (shared by ChartTab & KundliViewScreen)
// ============================================================================

class KundliExplorer extends StatefulWidget {
  final Map<String, dynamic> kundli;
  final int initialTab;

  const KundliExplorer({super.key, required this.kundli, this.initialTab = 0});

  static const List<String> tabs = [
    'Birth Chart (D1)',
    'Navamsha (D9)',
    'Dasamsha (D10)',
    'Dasha',
    'Panchang & Avakhada',
    'Planets & Nakshatras',
    'Full Life Report',
  ];
  static const int reportTab = 6;

  @override
  State<KundliExplorer> createState() => _KundliExplorerState();
}

class _KundliExplorerState extends State<KundliExplorer> {
  late int _tab;
  ChartStyle _style = ChartStyle.north;

  String? _report;
  String? _reportError;
  bool _loadingReport = false;
  int _reportRequest = 0;

  @override
  void initState() {
    super.initState();
    _tab = widget.initialTab.clamp(0, KundliExplorer.tabs.length - 1);
    if (_tab == KundliExplorer.reportTab) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _loadReport();
      });
    }
  }

  @override
  void didUpdateWidget(covariant KundliExplorer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (Vedic.identity(oldWidget.kundli) != Vedic.identity(widget.kundli)) {
      _report = null;
      _reportError = null;
      _loadingReport = false;
      _reportRequest++;
      if (_tab == KundliExplorer.reportTab) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _loadReport();
        });
      }
    }
  }

  void _selectTab(int i) {
    setState(() => _tab = i);
    if (i == KundliExplorer.reportTab) _loadReport();
  }

  Future<void> _loadReport({bool force = false}) async {
    if (_loadingReport) return;
    if (!force && _report != null) return;
    final cached = Vedic.text(widget.kundli['aiReport'], '');
    if (!force && cached.isNotEmpty) {
      setState(() => _report = cached);
      return;
    }

    final service = Provider.of<BackendService>(context, listen: false);
    final requestId = ++_reportRequest;
    setState(() {
      _loadingReport = true;
      _reportError = null;
    });

    String? result;
    try {
      final payload = Map<String, dynamic>.from(widget.kundli)..remove('aiReport');
      result = await service.fetchAIKundliReport(payload, birthDetails: Vedic.asMap(widget.kundli['birthDetails']));
    } catch (_) {
      result = null;
    }
    if (!mounted || requestId != _reportRequest) return;
    setState(() {
      _loadingReport = false;
      if (result != null && result.trim().isNotEmpty) {
        _report = result;
      } else {
        _reportError = 'We couldn\'t generate your life report right now. Check your connection and try again.';
      }
    });
  }

  void _askAI(String prompt, String astrologer) {
    Navigator.pushNamed(context, '/chatbot', arguments: {
      'name': astrologer,
      'specialty': 'Vedic Chart Reading',
      'field': 'Chart Analysis',
      'initialMessage': prompt,
    });
  }

  @override
  Widget build(BuildContext context) {
    final k = widget.kundli;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: 44,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: KundliExplorer.tabs.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (context, i) {
              final selected = i == _tab;
              return ChoiceChip(
                label: Text(KundliExplorer.tabs[i]),
                selected: selected,
                showCheckmark: false,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                visualDensity: VisualDensity.compact,
                selectedColor: const Color(0xFF1E1A17),
                backgroundColor: Colors.white,
                labelStyle: TextStyle(
                  color: selected ? Colors.white : Colors.black87,
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                  side: BorderSide(color: selected ? Colors.transparent : Colors.grey.shade300),
                ),
                onSelected: (_) => _selectTab(i),
              );
            },
          ),
        ),
        const SizedBox(height: 16),
        if (_birthTimeUnknown(k)) ...[
          _buildBirthTimeWarning(k),
          const SizedBox(height: 12),
        ],
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 200),
          child: KeyedSubtree(key: ValueKey(_tab), child: _buildTab(k)),
        ),
      ],
    );
  }

  bool _birthTimeUnknown(Map<String, dynamic> k) => Vedic.asMap(k['birthTime'])['known'] == false;

  // The backend flags charts made without a birth time: the Lagna, houses and
  // D9/D10 Lagna are a noon estimate, and the Moon may change sign that day.
  Widget _buildBirthTimeWarning(Map<String, dynamic> k) {
    final bt = Vedic.asMap(k['birthTime']);
    final signs = (bt['possibleMoonSigns'] is List) ? (bt['possibleMoonSigns'] as List).map((e) => '$e').toList() : <String>[];
    final naks = (bt['possibleNakshatras'] is List) ? (bt['possibleNakshatras'] as List).map((e) => '$e').toList() : <String>[];
    final lines = <String>[
      'Birth time unknown, so ${Vedic.text(bt['assumedTime'], '12:00')} was assumed. Your Ascendant (Lagna), houses and D9/D10 Lagna may not be accurate.',
      if (bt['moonSignCertain'] == false && signs.length > 1)
        'Your Moon sign could be ${signs.join(' or ')} depending on the exact time.'
      else if (bt['nakshatraCertain'] == false && naks.length > 1)
        'Your Moon sign is certain, but your nakshatra could be ${naks.join(' or ')}.'
      else
        'Your Moon sign and nakshatra are certain, so Moon-based readings are reliable.',
    ];
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF4E5),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFFFC37A)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.schedule_rounded, color: Color(0xFFB45309), size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(lines.join(' '), style: const TextStyle(fontSize: 12.5, height: 1.35, color: Color(0xFF7C2D12))),
                const SizedBox(height: 6),
                GestureDetector(
                  onTap: () => Navigator.pushNamed(context, '/birth-details'),
                  child: const Text(
                    'Know your birth time? Update it',
                    style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold, color: Color(0xFFB45309), decoration: TextDecoration.underline),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTab(Map<String, dynamic> k) {
    switch (_tab) {
      case 0:
        return _buildD1(k);
      case 1:
        return _buildDivisional(k, 9);
      case 2:
        return _buildDivisional(k, 10);
      case 3:
        return _buildDasha(k);
      case 4:
        return _buildPanchangAvakhada(k);
      case 5:
        return _buildPlanetTable(Vedic.d1Planets(k), 'D1 Graha Placements', showNakshatra: true);
      default:
        return _buildReport();
    }
  }

  // ------------------------------------------------------------- cards
  BoxDecoration get _card => BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.grey.shade200),
      );

  Widget _chartCard({
    required String title,
    required IconData icon,
    required Color color,
    required String ascendant,
    required List<Map<String, dynamic>> planets,
    required String centerLabel,
    String? note,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: _card,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFCF7F1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.grey.shade300),
                  ),
                  child: Text(
                    'Lagna: $ascendant',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: color),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ChartStyleToggle(value: _style, onChanged: (s) => setState(() => _style = s)),
          const SizedBox(height: 12),
          KundliChart(ascendant: ascendant, planets: planets, style: _style, centerLabel: centerLabel),
          const SizedBox(height: 8),
          Text(
            _style == ChartStyle.north
                ? 'Top diamond = 1st house (Lagna); numbers are signs (1 Aries … 12 Pisces). (R) = retrograde.'
                : 'Signs are fixed (Pisces top-left, clockwise); the slashed box is the Lagna. (R) = retrograde.',
            style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
          ),
          if (planets.isEmpty) ...[
            const SizedBox(height: 10),
            _infoBanner(
              'Planet positions are not available for this profile. Re-generate the Kundli to see them.',
              actionLabel: 'Update birth details',
              onAction: () => Navigator.pushNamed(context, '/birth-details'),
            ),
          ],
          if (note != null) ...[
            const SizedBox(height: 10),
            _infoBanner(note),
          ],
        ],
      ),
    );
  }

  Widget _infoBanner(String text, {String? actionLabel, VoidCallback? onAction}) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFF6C63FF).withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          const Icon(Icons.info_outline_rounded, color: Color(0xFF6C63FF), size: 16),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: const TextStyle(fontSize: 11, color: Color(0xFF4A44A8), fontWeight: FontWeight.w600))),
          if (actionLabel != null && onAction != null)
            TextButton(onPressed: onAction, child: Text(actionLabel, style: const TextStyle(fontSize: 11))),
        ],
      ),
    );
  }

  Widget _askButton(String prompt, String astrologer) {
    return SizedBox(
      height: 46,
      child: ElevatedButton.icon(
        onPressed: () => _askAI(prompt, astrologer),
        icon: const Icon(Icons.auto_awesome, size: 18),
        label: const Text('Ask AI Astrologer about this', overflow: TextOverflow.ellipsis),
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF7C77E6),
          foregroundColor: Colors.white,
          textStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
      ),
    );
  }

  Widget _kvRow(String label, String value, {String? sub}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: TextStyle(fontSize: 13, color: Colors.grey.shade700, fontWeight: FontWeight.w600)),
                if (sub != null) Text(sub, style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Flexible(
            child: Text(value, textAlign: TextAlign.end, style: const TextStyle(fontSize: 13, color: Colors.black, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  // ------------------------------------------------------------- D1
  Widget _buildD1(Map<String, dynamic> k) {
    final asc = Vedic.text(k['ascendant']);
    final ascIdx = Vedic.signIndex(k['ascendant']);
    final planets = Vedic.d1Planets(k);
    final pada = Vedic.toInt(k['nakshatraPada']);
    final dasha = Vedic.vimshottari(k);
    final serverDasha = Vedic.asMap(k['dashaInfo']);
    final md = dasha?.currentMaha?.lord ?? Vedic.text(serverDasha['currentMahadasha'], '');
    final ad = dasha?.currentAntar?.lord ?? Vedic.text(serverDasha['antardasha'], '');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _chartCard(
          title: 'Birth Chart (D1 Rasi)',
          icon: Icons.brightness_7_rounded,
          color: const Color(0xFFD95D39),
          ascendant: asc,
          planets: planets,
          centerLabel: 'D1 RASI',
        ),
        const SizedBox(height: 12),
        _askButton('Analyze my Birth Chart (D1): $asc Lagna and my planetary placements.', 'Pandit Shastri'),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: _card,
          child: Column(
            children: [
              _kvRow('Lagna (Ascendant)', asc, sub: ascIdx >= 0 ? 'Lord: ${Vedic.signLords[ascIdx]}' : null),
              const Divider(height: 8),
              _kvRow('Moon Sign (Rasi)', Vedic.text(k['moonSign']), sub: 'Mind & emotions'),
              const Divider(height: 8),
              _kvRow('Sun Sign', Vedic.text(k['sunSign']), sub: 'Soul & vitality'),
              const Divider(height: 8),
              _kvRow('Nakshatra', pada != null ? '${Vedic.text(k['nakshatra'])} (Pada $pada)' : Vedic.text(k['nakshatra']), sub: 'Birth star'),
              if (md.isNotEmpty) ...[
                const Divider(height: 8),
                _kvRow('Current Dasha', ad.isNotEmpty ? '$md / $ad' : md, sub: 'Mahadasha / Antardasha'),
              ],
            ],
          ),
        ),
        const SizedBox(height: 16),
        Material(
          color: Colors.white,
          clipBehavior: Clip.antiAlias,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: BorderSide(color: Colors.grey.shade200),
          ),
          child: Theme(
            data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
            child: ExpansionTile(
              leading: const Icon(Icons.grid_view_rounded, color: Color(0xFF6C63FF)),
              title: const Text('House-by-house breakdown', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
              subtitle: Text('What occupies each of your 12 houses', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
              childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              children: List.generate(12, (i) => _houseRow(i + 1, ascIdx, planets)),
            ),
          ),
        ),
      ],
    );
  }

  Widget _houseRow(int house, int ascIdx, List<Map<String, dynamic>> planets) {
    final signIdx = ascIdx >= 0 ? (ascIdx + house - 1) % 12 : -1;
    final occupants = planets.where((p) => Vedic.toInt(p['house']) == house).toList();
    final has = occupants.isNotEmpty;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: has ? const Color(0xFF6C63FF).withValues(alpha: 0.06) : const Color(0xFFFCF7F1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: has ? const Color(0xFF6C63FF).withValues(alpha: 0.3) : Colors.grey.shade200),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 14,
            backgroundColor: has ? const Color(0xFF6C63FF) : Colors.grey.shade400,
            child: Text('$house', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  signIdx >= 0
                      ? '${kZodiacSigns[signIdx]} · lord ${Vedic.signLords[signIdx]}${house == 1 ? ' · LAGNA' : ''}'
                      : 'House $house',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                ),
                Text(kHouseMeanings[house] ?? '', style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
                if (has) ...[
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: occupants
                        .map((p) => Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(color: const Color(0xFF6C63FF), borderRadius: BorderRadius.circular(8)),
                              child: Text(
                                '${Vedic.planetKey(p['name'])}${Vedic.isRetrograde(p) && !Vedic.isNode(p['name']) ? ' (R)' : ''}',
                                style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                              ),
                            ))
                        .toList(),
                  ),
                ] else
                  Text('Empty', style: TextStyle(fontSize: 11, color: Colors.grey.shade400, fontStyle: FontStyle.italic)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ------------------------------------------------------------- D9 / D10
  Widget _buildDivisional(Map<String, dynamic> k, int division) {
    final chart = Vedic.divisional(k, division);
    final isD9 = division == 9;
    final color = isD9 ? const Color(0xFFE83D66) : const Color(0xFFD95D39);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          isD9
              ? 'The Navamsha (D9) shows marriage, dharma and the strength of each planet in the second half of life.'
              : 'The Dasamsha (D10) governs career, profession, status and public recognition.',
          style: TextStyle(fontSize: 13, color: Colors.grey.shade700, height: 1.35),
        ),
        const SizedBox(height: 12),
        _chartCard(
          title: isD9 ? 'Navamsha (D9)' : 'Dasamsha (D10)',
          icon: isD9 ? Icons.favorite_rounded : Icons.work_rounded,
          color: color,
          ascendant: chart.ascendant,
          planets: chart.planets,
          centerLabel: isD9 ? 'D9 NAVAMSHA' : 'D10 DASAMSHA',
          note: chart.lagnaApproximate
              ? 'The exact ascendant degree is not stored for this profile, so the ${isD9 ? 'D9' : 'D10'} Lagna is approximate. Planet signs are exact.'
              : null,
        ),
        const SizedBox(height: 12),
        _askButton(
          isD9
              ? 'Analyze my Navamsha (D9) chart (${chart.ascendant} Lagna) for marriage and partnership.'
              : 'Analyze my Dasamsha (D10) chart (${chart.ascendant} Lagna) for career and authority.',
          isD9 ? 'Dr. Ananya Roy' : 'Acharya Dev Sharma',
        ),
        const SizedBox(height: 16),
        _buildPlanetTable(chart.planets, isD9 ? 'D9 Placements' : 'D10 Placements', showNakshatra: false),
      ],
    );
  }

  // ------------------------------------------------------------- planets
  Widget _buildPlanetTable(List<Map<String, dynamic>> planets, String title, {required bool showNakshatra}) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _card,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          if (planets.isEmpty)
            Text('No planetary data available.', style: TextStyle(color: Colors.grey.shade600, fontSize: 13)),
          ...planets.map((p) {
            final name = Vedic.planetKey(p['name']);
            final retro = Vedic.isRetrograde(p);
            final nak = Vedic.text(p['nakshatra'], '');
            final pada = Vedic.toInt(p['nakshatraPada']);
            final lord = Vedic.text(p['planetLord'], '');
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(color: const Color(0xFF7C77E6).withValues(alpha: 0.1), shape: BoxShape.circle),
                    child: Text(Vedic.abbr(p['name']), style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF7C77E6), fontSize: 12)),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(name, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                            ),
                            if (retro) ...[
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                decoration: BoxDecoration(color: Colors.red.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(6)),
                                child: const Text('R', style: TextStyle(color: Colors.red, fontSize: 10, fontWeight: FontWeight.w900)),
                              ),
                            ],
                          ],
                        ),
                        Text(
                          'House ${Vedic.text(p['house'])} · ${Vedic.text(p['sign'])}',
                          style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                        ),
                        if (showNakshatra && nak.isNotEmpty)
                          Text(
                            '$nak${pada != null ? ' (Pada $pada)' : ''}${lord.isNotEmpty ? ' · Lord $lord' : ''}',
                            style: const TextStyle(fontSize: 11, color: Color(0xFF6C63FF), fontWeight: FontWeight.w600),
                          ),
                      ],
                    ),
                  ),
                  if (showNakshatra) ...[
                    const SizedBox(width: 8),
                    Text(
                      Vedic.formatDegree(p['degree']),
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFFD95D39)),
                    ),
                  ],
                ],
              ),
            );
          }),
          if (planets.any((p) => Vedic.isNode(p['name'])))
            Text('Rahu & Ketu always move retrograde (mean motion).', style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
        ],
      ),
    );
  }

  // ------------------------------------------------------------- Dasha
  Widget _buildDasha(Map<String, dynamic> k) {
    final t = Vedic.vimshottari(k);
    final server = Vedic.asMap(k['dashaInfo']);
    final fmt = DateFormat('d MMM yyyy');
    final now = DateTime.now().toUtc();

    if (t == null || t.currentMaha == null) {
      // Fall back to what the server stored.
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _dashaHero(
            Vedic.text(server['currentMahadasha']),
            Vedic.text(server['antardasha']),
            Vedic.text(server['dashaEndDate']),
          ),
          const SizedBox(height: 10),
          _infoBanner('A detailed dasha timeline needs the birth date, time and Moon position for this profile.'),
        ],
      );
    }

    final md = t.currentMaha!;
    final ad = t.currentAntar;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _dashaHero(md.lord, ad?.lord ?? '—', fmt.format((ad ?? md).end.toLocal()), mdEnd: fmt.format(md.end.toLocal())),
        const SizedBox(height: 12),
        _askButton('Explain my current ${md.lord} Mahadasha and ${ad?.lord ?? ''} Antardasha predictions.', 'Tarun Shastri'),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: _card,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Antardashas in ${md.lord} Mahadasha', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
              const SizedBox(height: 10),
              ...t.antardashas.map((p) => _periodRow(p, fmt, active: p.contains(now), past: p.end.isBefore(now))),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: _card,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Vimshottari Mahadasha timeline', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              Text('120-year cycle starting from your Moon nakshatra lord.', style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
              const SizedBox(height: 10),
              ...t.mahadashas.map((p) => _periodRow(p, fmt, active: p.contains(now), past: p.end.isBefore(now), showYears: true)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _dashaHero(String md, String ad, String endsOn, {String? mdEnd}) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(color: const Color(0xFF1E1A17), borderRadius: BorderRadius.circular(22)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.hourglass_top_rounded, color: Color(0xFFFFB74D), size: 20),
              SizedBox(width: 8),
              Expanded(
                child: Text('Vimshottari Dasha · Running now',
                    overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white)),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: _heroCol('Mahadasha', md, Colors.white, sub: mdEnd != null ? 'till $mdEnd' : null)),
              Expanded(child: _heroCol('Antardasha', ad, const Color(0xFFFFB74D), sub: 'till $endsOn')),
            ],
          ),
        ],
      ),
    );
  }

  Widget _heroCol(String label, String value, Color color, {String? sub}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(fontSize: 12, color: Colors.grey.shade400)),
        const SizedBox(height: 4),
        Text(value, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: color)),
        if (sub != null) Text(sub, style: const TextStyle(fontSize: 11, color: Colors.white60)),
      ],
    );
  }

  Widget _periodRow(DashaPeriod p, DateFormat fmt, {required bool active, required bool past, bool showYears = false}) {
    final color = active ? const Color(0xFF6C63FF) : (past ? Colors.grey.shade400 : Colors.black87);
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: active ? const Color(0xFF6C63FF).withValues(alpha: 0.08) : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: active ? const Color(0xFF6C63FF).withValues(alpha: 0.4) : Colors.transparent),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 78,
            child: Text(
              showYears ? '${p.lord} (${Vedic.dashaYears[p.lord]}y)' : p.lord,
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: color),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '${fmt.format(p.start.toLocal())} – ${fmt.format(p.end.toLocal())}',
              textAlign: TextAlign.end,
              style: TextStyle(fontSize: 12, color: color),
            ),
          ),
          if (active) ...[
            const SizedBox(width: 6),
            const Icon(Icons.play_arrow_rounded, color: Color(0xFF6C63FF), size: 16),
          ],
        ],
      ),
    );
  }

  // ------------------------------------------------------------- Panchang & Avakhada
  Widget _buildPanchangAvakhada(Map<String, dynamic> k) {
    final panchang = Vedic.birthPanchang(k);
    final avakhada = Vedic.avakhada(k);
    Widget card(String title, IconData icon, Color color, Map<String, String> data) {
      final entries = data.entries.toList();
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: _card,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: color, size: 20),
                const SizedBox(width: 8),
                Expanded(child: Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold))),
              ],
            ),
            const SizedBox(height: 8),
            if (entries.isEmpty) Text('Not available for this profile.', style: TextStyle(color: Colors.grey.shade600, fontSize: 13)),
            for (int i = 0; i < entries.length; i++) ...[
              if (i > 0) const Divider(height: 4),
              _kvRow(entries[i].key, entries[i].value),
            ],
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        card('Birth Panchang', Icons.wb_sunny_rounded, const Color(0xFFFF9800), panchang),
        const SizedBox(height: 16),
        card('Avakhada Chakra', Icons.auto_awesome, const Color(0xFF6C63FF), avakhada),
        const SizedBox(height: 8),
        Text(
          'Avakhada values are used for Kundli matching (Guna Milan). Birth Panchang is calculated for the birth moment in IST.',
          style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
        ),
      ],
    );
  }

  // ------------------------------------------------------------- report
  Widget _buildReport() {
    if (_loadingReport) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 40),
        child: Column(
          children: [
            CircularProgressIndicator(color: Color(0xFF6C63FF)),
            SizedBox(height: 16),
            Text('Preparing your complete life report…', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
            SizedBox(height: 4),
            Text('This can take up to a minute.', style: TextStyle(fontSize: 11, color: Colors.grey)),
          ],
        ),
      );
    }
    if (_reportError != null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 30),
        child: Column(
          children: [
            const Icon(Icons.cloud_off_rounded, color: Colors.grey, size: 40),
            const SizedBox(height: 10),
            Text(_reportError!, textAlign: TextAlign.center, style: const TextStyle(fontSize: 13)),
            const SizedBox(height: 12),
            ElevatedButton.icon(
              onPressed: () => _loadReport(force: true),
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Retry'),
            ),
          ],
        ),
      );
    }
    final r = _report;
    if (r == null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 30),
        child: Center(
          child: ElevatedButton.icon(
            onPressed: _loadReport,
            icon: const Icon(Icons.auto_awesome),
            label: const Text('Generate life report'),
          ),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        KundliReportView(report: r),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton.icon(
            onPressed: () => _loadReport(force: true),
            icon: const Icon(Icons.refresh_rounded, size: 18),
            label: const Text('Regenerate'),
          ),
        ),
      ],
    );
  }
}

// ============================================================================
// KundliViewScreen
// ============================================================================

class KundliViewScreen extends StatelessWidget {
  final int initialTab;
  const KundliViewScreen({super.key, this.initialTab = 0});

  @override
  Widget build(BuildContext context) {
    final service = Provider.of<BackendService>(context);
    final kundli = Vedic.activeKundli(service);
    final birth = Vedic.asMap(kundli?['birthDetails']);
    final relationship = Vedic.text(birth['relationship'], '');
    final name = Vedic.displayName(kundli, service: service);

    return Scaffold(
      backgroundColor: const Color(0xFFFCF7F1),
      appBar: AppBar(
        backgroundColor: const Color(0xFFFCF7F1),
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, color: Colors.black),
          tooltip: 'Back',
          onPressed: () => Navigator.maybePop(context),
        ),
        title: Text(
          relationship.isNotEmpty ? "$relationship's Vedic Kundli" : 'Your Vedic Kundli',
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
        actions: [
          IconButton(
            tooltip: 'Switch profile',
            icon: const Icon(Icons.people_alt_outlined, color: Colors.black),
            onPressed: () => showKundliProfilePicker(context),
          ),
        ],
      ),
      body: kundli == null
          ? const KundliEmptyState()
          : SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.grey.shade200),
                      boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 10, offset: const Offset(0, 4))],
                    ),
                    child: Row(
                      children: [
                        CircleAvatar(
                          radius: 24,
                          backgroundColor: const Color(0xFF6C63FF).withValues(alpha: 0.12),
                          child: const Icon(Icons.auto_awesome, color: Color(0xFF6C63FF), size: 24),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(name, maxLines: 1, overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.black)),
                              const SizedBox(height: 4),
                              Text(
                                'Born ${_formatDob(birth['dateOfBirth'])}${Vedic.text(birth['timeOfBirth'], '').isNotEmpty ? ', ${_formatTob(birth['timeOfBirth'])}' : ''} · ${Vedic.text(birth['placeOfBirth'], 'place not set')}',
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  KundliExplorer(key: ValueKey(Vedic.identity(kundli)), kundli: kundli, initialTab: initialTab),
                ],
              ),
            ),
    );
  }

  static String _formatDob(dynamic raw) {
    final s = Vedic.text(raw, '');
    if (s.isEmpty) return 'date not set';
    final dt = DateTime.tryParse(s);
    if (dt == null) return s;
    final local = dt.isUtc ? dt.add(const Duration(hours: 5, minutes: 30)) : dt;
    return DateFormat('d MMM yyyy').format(local);
  }

  static String _formatTob(dynamic raw) {
    final m = RegExp(r'(\d{1,2}):(\d{2})').firstMatch(Vedic.text(raw, ''));
    if (m == null) return Vedic.text(raw, '');
    final h = int.parse(m.group(1)!), min = int.parse(m.group(2)!);
    return DateFormat('h:mm a').format(DateTime(2000, 1, 1, h, min));
  }
}
