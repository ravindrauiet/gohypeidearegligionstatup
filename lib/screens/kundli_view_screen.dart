import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show SystemUiOverlayStyle;
import 'package:intl/intl.dart' show DateFormat;
import 'package:provider/provider.dart';

import '../services/backend_service.dart';
import '../utils/app_routes.dart';
import '../widgets/ui/app_ui.dart';
import 'home_screen.dart';
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

// Chart colours: hairline indigo grid, muted sign numbers, saffron Lagna.
final Color _chartLine = AppColors.cosmicLight.withValues(alpha: 0.32);
const Color _chartBg = AppColors.surface;
const Color _chartAccent = AppColors.primary;
const Color _chartLagnaFill = AppColors.primarySoft;

void _drawLabelBlock(
  Canvas canvas,
  List<String> items,
  Offset center,
  int perLine,
  double fontSize, {
  Color color = AppColors.textPrimary,
  FontWeight weight = FontWeight.w700,
  List<bool>? highlight,
}) {
  if (items.isEmpty) return;
  final spans = <TextSpan>[];
  for (int i = 0; i < items.length; i++) {
    if (i > 0) spans.add(TextSpan(text: i % perLine == 0 ? '\n' : ' '));
    final hl = highlight != null && i < highlight.length && highlight[i];
    spans.add(TextSpan(
      text: items[i],
      style: TextStyle(color: hl ? _chartAccent : color, fontWeight: hl ? FontWeight.w800 : weight),
    ));
  }
  final tp = TextPainter(
    text: TextSpan(
      style: TextStyle(fontSize: fontSize, fontWeight: weight, height: 1.2, color: color, letterSpacing: 0.1),
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
      ..strokeWidth = 1.0
      ..isAntiAlias = true
      ..style = PaintingStyle.stroke;
    final rect = Rect.fromLTWH(0, 0, w, h);
    canvas.drawRect(rect, Paint()..color = _chartBg);
    // Lagna (1st house) diamond gets a soft saffron tint.
    canvas.drawPath(
      Path()
        ..moveTo(w / 2, 0)
        ..lineTo(w * 0.75, h * 0.25)
        ..lineTo(w / 2, h / 2)
        ..lineTo(w * 0.25, h * 0.25)
        ..close(),
      Paint()..color = _chartLagnaFill,
    );
    canvas.drawRect(rect.deflate(0.5), line);
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

    final base = (w * 0.038).clamp(9.0, 14.0);
    final start = ascIdx >= 0 ? ascIdx : 0;

    final byHouse = List.generate(12, (_) => <String>[]);
    for (final p in planets) {
      final house = Vedic.toInt(p['house']);
      if (house != null && house >= 1 && house <= 12) byHouse[house - 1].add(Vedic.chartLabel(p));
    }

    for (int i = 0; i < 12; i++) {
      final cfg = _layout[i];
      // Sign number (1 = Aries ... 12 = Pisces)
      _drawLabelBlock(canvas, ['${(start + i) % 12 + 1}'], Offset(w * cfg[2], h * cfg[3]), 1, base * 0.82,
          color: i == 0 ? _chartAccent : AppColors.textTertiary, weight: FontWeight.w600);
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
      ..strokeWidth = 1.0
      ..style = PaintingStyle.stroke;
    canvas.drawRect(Rect.fromLTWH(0, 0, w, h), Paint()..color = _chartBg);
    if (ascIdx >= 0) {
      final r = _cells[ascIdx][0], c = _cells[ascIdx][1];
      canvas.drawRect(Rect.fromLTWH(c * cw, r * ch, cw, ch), Paint()..color = _chartLagnaFill);
    }
    canvas.drawRect(Rect.fromLTWH(0, 0, w, h).deflate(0.5), line);
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

    final base = (w * 0.038).clamp(9.0, 14.0);

    final bySign = List.generate(12, (_) => <String>[]);
    for (final p in planets) {
      final s = Vedic.signIndex(p['sign']);
      if (s >= 0) bySign[s].add(Vedic.chartLabel(p));
    }

    for (int s = 0; s < 12; s++) {
      final r = _cells[s][0], c = _cells[s][1];
      final x0 = c * cw, y0 = r * ch;
      final isAsc = s == ascIdx;
      final signTp = TextPainter(
        text: TextSpan(
          text: Vedic.signShort[s],
          style: TextStyle(
            fontSize: base * 0.78,
            color: isAsc ? _chartAccent : AppColors.textTertiary,
            fontWeight: FontWeight.w600,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      signTp.paint(canvas, Offset(x0 + cw - signTp.width - 5, y0 + 4));

      if (isAsc) {
        final accent = Paint()
          ..color = _chartAccent
          ..strokeWidth = 1.2;
        canvas.drawLine(Offset(x0, y0 + ch * 0.30), Offset(x0 + cw * 0.30, y0), accent);
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
      color: AppColors.textSecondary,
      weight: FontWeight.w600,
    );
  }

  @override
  bool shouldRepaint(covariant SouthIndianChartPainter old) =>
      old.ascIdx != ascIdx || old.centerLabel != centerLabel || !identical(old.planets, planets);
}

/// North / South Indian segmented control.
class ChartStyleToggle extends StatelessWidget {
  final ChartStyle value;
  final ValueChanged<ChartStyle> onChanged;

  const ChartStyleToggle({super.key, required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    Widget seg(ChartStyle s, String label) {
      final selected = value == s;
      return Expanded(
        child: Semantics(
          button: true,
          selected: selected,
          label: '$label chart style',
          excludeSemantics: true,
          child: Material(
            color: selected ? AppColors.surface : Colors.transparent,
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadius.sm),
              side: selected ? const BorderSide(color: AppColors.border) : BorderSide.none,
            ),
            child: InkWell(
              borderRadius: BorderRadius.circular(AppRadius.sm),
              onTap: () => onChanged(s),
              child: SizedBox(
                height: 40,
                child: Center(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                      color: selected ? AppColors.textPrimary : AppColors.textSecondary,
                    ),
                  ),
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
        color: AppColors.surfaceMuted,
        borderRadius: BorderRadius.circular(AppRadius.md),
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
      return const AppStateView(
        icon: Icons.article_outlined,
        title: 'The report is empty',
        message: 'Please try generating it again.',
        compact: true,
      );
    }

    return Column(children: sections.map((s) => _section(s[0], s[1])).toList());
  }

  Widget _section(String title, String body) {
    IconData icon = Icons.stars_rounded;
    final t = title.toLowerCase();
    if (t.contains('personality')) {
      icon = Icons.person_rounded;
    } else if (t.contains('physical')) {
      icon = Icons.fitness_center_rounded;
    } else if (t.contains('health')) {
      icon = Icons.health_and_safety_rounded;
    } else if (t.contains('career') || t.contains('wealth')) {
      icon = Icons.work_rounded;
    } else if (t.contains('marriage') || t.contains('relationship')) {
      icon = Icons.favorite_rounded;
    } else if (t.contains('dasha')) {
      icon = Icons.hourglass_bottom_rounded;
    } else if (t.contains('summary') || t.contains('final') || t.contains('guidance')) {
      icon = Icons.workspace_premium_rounded;
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (title.isNotEmpty) ...[
              Row(
                children: [
                  _IconTile(icon: icon, size: 36),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(child: Text(title, style: AppText.subtitle)),
                ],
              ),
              if (body.isNotEmpty) const SizedBox(height: AppSpacing.sm),
            ],
            if (body.isNotEmpty) SelectableText.rich(TextSpan(children: _spans(body))),
          ],
        ),
      ),
    );
  }

  static List<TextSpan> _spans(String text) {
    const normal = TextStyle(color: AppColors.textSecondary, fontSize: 14, height: 1.6);
    const bold = TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w700, fontSize: 14, height: 1.6);
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

/// Rounded tinted square holding an icon.
class _IconTile extends StatelessWidget {
  final IconData icon;
  final double size;
  static const Color color = AppColors.primary;

  const _IconTile({required this.icon, this.size = 40});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(AppRadius.sm + 2),
      ),
      child: Icon(icon, color: color, size: size * 0.5),
    );
  }
}

/// Shown when the user has not generated a Kundli yet.
class KundliEmptyState extends StatelessWidget {
  const KundliEmptyState({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 88,
              height: 88,
              decoration: const BoxDecoration(gradient: AppColors.cosmicGradient, shape: BoxShape.circle),
              child: const Icon(Icons.auto_awesome_rounded, color: AppColors.gold, size: 38),
            ),
            const SizedBox(height: AppSpacing.lg),
            const Text('Create your Vedic Kundli', textAlign: TextAlign.center, style: AppText.headline),
            const SizedBox(height: AppSpacing.xs),
            const Text(
              'Add your date, time and place of birth to see your birth chart, divisional charts, dashas and a full life report.',
              textAlign: TextAlign.center,
              style: AppText.body,
            ),
            const SizedBox(height: AppSpacing.xl),
            AppButton(
              label: 'Add birth details',
              icon: Icons.edit_calendar_rounded,
              expand: false,
              onPressed: () => Navigator.pushNamed(context, '/birth-details'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Finds a context *below* HomeScreen (so `HomeScreen.switchTab` can locate its
/// state) even when called from a pushed route or a bottom sheet.
BuildContext? _homeDescendantContext(BuildContext context) {
  if (context.findAncestorStateOfType<HomeScreenState>() != null) return context;
  BuildContext? found;
  void visit(Element e) {
    if (found != null) return;
    if (e is StatefulElement && e.state is HomeScreenState) {
      e.visitChildren((c) => found ??= c);
      return;
    }
    e.visitChildren(visit);
  }

  Navigator.of(context, rootNavigator: true).context.visitChildElements(visit);
  return found;
}

/// Opens the family profiles section in the More tab (or login for guests).
void _openFamilySection(BuildContext context) {
  final service = Provider.of<BackendService>(context, listen: false);
  final nav = Navigator.of(context, rootNavigator: true);
  if (!service.isAuthenticated) {
    nav.pushNamed(AppRoutes.login);
    return;
  }
  final homeCtx = _homeDescendantContext(context);
  nav.popUntil((r) => r.settings.name == AppRoutes.home || r.isFirst);
  HomeScreen.switchTab(homeCtx ?? context, 2, targetSection: 'family');
}

/// Bottom sheet that switches the active Kundli profile (self / family members).
Future<void> showKundliProfilePicker(BuildContext context) {
  final service = Provider.of<BackendService>(context, listen: false);
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (ctx) => _ProfilePickerSheet(service: service, hostContext: context),
  );
}

class _ProfilePickerSheet extends StatefulWidget {
  final BackendService service;
  final BuildContext hostContext;
  const _ProfilePickerSheet({required this.service, required this.hostContext});

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
      return Semantics(
        selected: active,
        button: true,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.page, vertical: 10),
            child: Row(
              children: [
                AppAvatar(name: title, size: 44),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.subtitle),
                      const SizedBox(height: 2),
                      Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.caption.copyWith(color: AppColors.textSecondary)),
                    ],
                  ),
                ),
                if (active) const Icon(Icons.check_circle_rounded, color: AppColors.primary),
              ],
            ),
          ),
        ),
      );
    }

    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.7),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(AppSpacing.page, 0, AppSpacing.xs, AppSpacing.xs),
            child: Row(
              children: [
                const Expanded(child: Text('Switch Kundli profile', style: AppText.title)),
                IconButton(tooltip: 'Close', icon: const Icon(Icons.close_rounded), onPressed: () => Navigator.pop(context)),
              ],
            ),
          ),
          if (_loading) const LinearProgressIndicator(minHeight: 2),
          Flexible(
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.only(bottom: AppSpacing.md),
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
                    padding: const EdgeInsets.fromLTRB(AppSpacing.page, AppSpacing.xs, AppSpacing.page, 0),
                    child: AppCard(
                      color: AppColors.primarySoft,
                      border: false,
                      onTap: () {
                        Navigator.pop(context);
                        _openFamilySection(widget.hostContext.mounted ? widget.hostContext : context);
                      },
                      child: Row(
                        children: [
                          const _IconTile(icon: Icons.group_add_rounded, size: 40),
                          const SizedBox(width: AppSpacing.sm),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  s.isAuthenticated ? 'No family Kundlis yet' : 'Log in to add family Kundlis',
                                  style: AppText.bodyStrong,
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  s.isAuthenticated ? 'Add family profiles from the More tab' : 'Sign in to save and switch Kundlis',
                                  style: AppText.caption.copyWith(color: AppColors.primaryDark),
                                ),
                              ],
                            ),
                          ),
                          const Icon(Icons.chevron_right_rounded, color: AppColors.primary),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// KundliExplorer – cosmic hero + sticky section tabs + content
// (shared by ChartTab & KundliViewScreen)
// ============================================================================

class KundliExplorer extends StatefulWidget {
  final Map<String, dynamic> kundli;
  final int initialTab;

  /// Shows a back arrow in the hero (for the pushed full-screen route).
  final bool showBack;

  /// When set, the hero shows an "open full screen" action.
  final VoidCallback? onOpenFullScreen;

  const KundliExplorer({
    super.key,
    required this.kundli,
    this.initialTab = 0,
    this.showBack = false,
    this.onOpenFullScreen,
  });

  static const List<String> tabs = [
    'Birth chart',
    'Navamsha D9',
    'Career D10',
    'Dasha',
    'Panchang',
    'Planets',
    'Life report',
  ];
  static const int reportTab = 6;

  @override
  State<KundliExplorer> createState() => _KundliExplorerState();
}

class _KundliExplorerState extends State<KundliExplorer> with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  late int _tab;
  final ScrollController _scroll = ScrollController();
  final GlobalKey _heroKey = GlobalKey();
  ChartStyle _style = ChartStyle.north;

  String? _report;
  String? _reportError;
  bool _loadingReport = false;
  int _reportRequest = 0;

  @override
  void initState() {
    super.initState();
    _tab = widget.initialTab.clamp(0, KundliExplorer.tabs.length - 1);
    _tabs = TabController(length: KundliExplorer.tabs.length, vsync: this, initialIndex: _tab)
      ..addListener(_onTabController);
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

  @override
  void dispose() {
    _tabs.removeListener(_onTabController);
    _tabs.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _onTabController() {
    if (_tabs.index != _tab) _selectTab(_tabs.index);
  }

  void _selectTab(int i) {
    setState(() => _tab = i);
    // Keep the sticky tab bar at the top so the new section starts in view.
    final heroH = _heroKey.currentContext?.size?.height;
    if (heroH != null && _scroll.hasClients && _scroll.offset > heroH) _scroll.jumpTo(heroH);
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
    final service = Provider.of<BackendService>(context);
    final reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final topInset = MediaQuery.paddingOf(context).top;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Column(
        children: [
          // Status-bar strip so the sticky tab bar never slides under the clock.
          Container(height: topInset, color: AppColors.cosmic),
          Expanded(
            child: CustomScrollView(
              controller: _scroll,
              slivers: [
                SliverToBoxAdapter(child: _hero(k, service)),
                SliverPersistentHeader(
                  pinned: true,
                  delegate: _TabBarHeader(
                    TabBar(
                      controller: _tabs,
                      isScrollable: true,
                      tabAlignment: TabAlignment.start,
                      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
                      labelPadding: const EdgeInsets.symmetric(horizontal: 12),
                      indicatorSize: TabBarIndicatorSize.label,
                      indicator: const UnderlineTabIndicator(
                        borderSide: BorderSide(color: AppColors.primary, width: 2.5),
                        borderRadius: BorderRadius.vertical(top: Radius.circular(2)),
                      ),
                      tabs: [for (final t in KundliExplorer.tabs) Tab(text: t, height: 48)],
                    ),
                  ),
                ),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(AppSpacing.page, AppSpacing.lg, AppSpacing.page, AppSpacing.xxl),
                  sliver: SliverToBoxAdapter(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (_birthTimeUnknown(k)) ...[
                          _buildBirthTimeWarning(k),
                          const SizedBox(height: AppSpacing.md),
                        ],
                        AnimatedSwitcher(
                          duration: reduceMotion ? Duration.zero : const Duration(milliseconds: 200),
                          child: KeyedSubtree(key: ValueKey(_tab), child: _buildTab(k)),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ------------------------------------------------------------- hero
  Widget _hero(Map<String, dynamic> k, BackendService service) {
    final birth = Vedic.asMap(k['birthDetails']);
    final relationship = Vedic.text(birth['relationship'], '');
    final name = Vedic.displayName(k, service: service);
    final pada = Vedic.toInt(k['nakshatraPada']);
    final asc = Vedic.text(k['ascendant']);
    final moon = Vedic.text(k['moonSign']);
    final nak = Vedic.text(k['nakshatra']);
    final tob = Vedic.text(birth['timeOfBirth'], '');
    final birthLine =
        'Born ${_formatDob(birth['dateOfBirth'])}${tob.isNotEmpty ? ', ${_formatTob(tob)}' : ''} · ${Vedic.text(birth['placeOfBirth'], 'place not set')}';

    final members = service.familyMembers.where((m) => m['kundli'] != null).toList();
    final selected = service.selectedFamilyMember;
    final showProfiles = service.isAuthenticated || members.isNotEmpty;

    const iconColor = AppColors.textOnDark;
    return Container(
      key: _heroKey,
      decoration: const BoxDecoration(gradient: AppColors.cosmicGradient),
      padding: const EdgeInsets.fromLTRB(AppSpacing.page, 0, AppSpacing.page, AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: 52,
            child: Row(
              children: [
                if (widget.showBack)
                  IconButton(
                    tooltip: 'Back',
                    icon: const Icon(Icons.arrow_back_rounded, color: iconColor),
                    onPressed: () => Navigator.maybePop(context),
                  )
                else
                  const SizedBox(width: 0),
                if (widget.showBack) const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    relationship.isNotEmpty ? "$relationship's Kundli" : 'My Kundli',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.title.copyWith(color: AppColors.textOnDark),
                  ),
                ),
                IconButton(
                  tooltip: 'Switch profile',
                  icon: const Icon(Icons.swap_horiz_rounded, color: iconColor),
                  onPressed: () => showKundliProfilePicker(context),
                ),
                if (widget.onOpenFullScreen != null)
                  IconButton(
                    tooltip: 'Open full-screen Kundli',
                    icon: const Icon(Icons.open_in_full_rounded, color: iconColor, size: 20),
                    onPressed: widget.onOpenFullScreen,
                  ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Row(
            children: [
              AppAvatar(name: name, size: 52, color: AppColors.gold),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppText.headline.copyWith(color: AppColors.textOnDark)),
                    const SizedBox(height: 2),
                    Text(birthLine,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: AppText.caption.copyWith(color: AppColors.textOnDarkMuted)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: _heroStat('Lagna', asc, Icons.north_east_rounded)),
                const SizedBox(width: AppSpacing.xs),
                Expanded(child: _heroStat('Moon sign', moon, Icons.nightlight_round)),
                const SizedBox(width: AppSpacing.xs),
                Expanded(child: _heroStat('Nakshatra', nak, Icons.star_rounded, sub: pada != null ? 'Pada $pada' : null)),
              ],
            ),
          ),
          if (showProfiles) ...[
            const SizedBox(height: AppSpacing.sm),
            SizedBox(
              height: 44,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  _profileChip(
                    label: 'Me',
                    selected: selected == null,
                    onTap: () => service.selectFamilyMember(null),
                  ),
                  for (final m in members)
                    _profileChip(
                      label: _firstName(Vedic.text(m['fullName'], Vedic.text(m['relationship'], 'Family'))),
                      selected: selected != null && selected['id'] == m['id'],
                      onTap: () => service.selectFamilyMember(m),
                    ),
                  _profileChip(
                    label: members.isEmpty ? 'Add family' : 'Add',
                    icon: Icons.add_rounded,
                    selected: false,
                    onTap: () => _openFamilySection(context),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.md),
          AppButton(
            label: 'Ask AI about my Kundli',
            icon: Icons.auto_awesome_rounded,
            onPressed: () => _askAI(
              'Please read my Kundli: $asc Lagna, $moon Moon sign and $nak nakshatra. '
                  'What are the key themes of my chart for career, relationships and health?',
              'Pandit Shastri',
            ),
          ),
        ],
      ),
    );
  }

  static String _firstName(String s) {
    final first = s.trim().split(RegExp(r'\s+')).first;
    return first.isEmpty ? s : first;
  }

  Widget _heroStat(String label, String value, IconData icon, {String? sub}) {
    return Semantics(
      label: '$label: $value${sub != null ? ', $sub' : ''}',
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.fromLTRB(10, 10, 8, 10),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.07),
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 13, color: AppColors.gold),
                const SizedBox(width: 4),
                Flexible(
                  child: Text(label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.caption.copyWith(color: AppColors.textOnDarkMuted)),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(value,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 15, height: 1.2, fontWeight: FontWeight.w700, color: AppColors.textOnDark)),
            if (sub != null)
              Text(sub,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.caption.copyWith(color: AppColors.textOnDarkMuted)),
          ],
        ),
      ),
    );
  }

  Widget _profileChip({required String label, required bool selected, required VoidCallback onTap, IconData? icon}) {
    return Padding(
      padding: const EdgeInsets.only(right: AppSpacing.xs),
      child: Semantics(
        button: true,
        selected: selected,
        label: icon != null ? label : 'Show $label Kundli',
        excludeSemantics: true,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppRadius.pill),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: selected ? AppColors.surface : Colors.white.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(AppRadius.pill),
                border: Border.all(color: selected ? AppColors.surface : Colors.white.withValues(alpha: 0.22)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (icon != null) ...[
                    Icon(icon, size: 16, color: AppColors.textOnDark),
                    const SizedBox(width: 4),
                  ],
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                      color: selected ? AppColors.cosmic : AppColors.textOnDark,
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
      padding: const EdgeInsets.fromLTRB(AppSpacing.sm, AppSpacing.sm, AppSpacing.sm, 0),
      decoration: BoxDecoration(
        color: AppColors.warningSoft,
        borderRadius: AppRadius.card,
        border: Border.all(color: AppColors.warning.withValues(alpha: 0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 1),
            child: Icon(Icons.schedule_rounded, color: AppColors.warning, size: 20),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(lines.join(' '), style: AppText.body.copyWith(fontSize: 13, color: AppColors.textPrimary)),
                TextButton(
                  onPressed: () => Navigator.pushNamed(context, '/birth-details'),
                  style: TextButton.styleFrom(
                    padding: EdgeInsets.zero,
                    minimumSize: const Size(0, 44),
                    foregroundColor: AppColors.primaryDark,
                  ),
                  child: const Text('Know your birth time? Update it'),
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
        return _section(
          'Planet positions',
          'Where each planet sat when you were born: its sign, house and birth star (nakshatra).',
          [_buildPlanetTable(Vedic.d1Planets(k), 'D1 graha placements', showNakshatra: true)],
        );
      default:
        return _buildReport();
    }
  }

  // ------------------------------------------------------------- building blocks
  /// Section title + one-line plain-English explanation + content.
  Widget _section(String title, String explanation, List<Widget> children) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(title, style: AppText.title),
        const SizedBox(height: AppSpacing.xxs),
        Text(explanation, style: AppText.body),
        const SizedBox(height: AppSpacing.md),
        ...children,
      ],
    );
  }

  Widget _cardTitle(String title, {Widget? trailing, IconData? icon}) {
    return Row(
      children: [
        if (icon != null) ...[
          _IconTile(icon: icon, size: 36),
          const SizedBox(width: AppSpacing.sm),
        ],
        Expanded(child: Text(title, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppText.subtitle)),
        if (trailing != null) ...[const SizedBox(width: AppSpacing.xs), trailing],
      ],
    );
  }

  Widget _chartCard({
    required String title,
    required String ascendant,
    required List<Map<String, dynamic>> planets,
    required String centerLabel,
    String? note,
  }) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _cardTitle(
            title,
            trailing: Flexible(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppColors.primarySoft,
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                ),
                child: Text(
                  'Lagna · $ascendant',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.primaryDark, height: 1.2),
                ),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          ChartStyleToggle(value: _style, onChanged: (s) => setState(() => _style = s)),
          const SizedBox(height: AppSpacing.md),
          KundliChart(ascendant: ascendant, planets: planets, style: _style, centerLabel: centerLabel),
          const SizedBox(height: AppSpacing.sm),
          Text(
            _style == ChartStyle.north
                ? 'Top diamond (shaded) = 1st house, your Lagna. Numbers are signs (1 Aries … 12 Pisces). (R) = retrograde.'
                : 'Signs are fixed (Pisces top-left, clockwise). The shaded box is your Lagna. (R) = retrograde.',
            style: AppText.caption,
          ),
          if (planets.isEmpty) ...[
            const SizedBox(height: AppSpacing.sm),
            _infoBanner(
              'Planet positions are not available for this profile. Re-generate the Kundli to see them.',
              actionLabel: 'Update birth details',
              onAction: () => Navigator.pushNamed(context, '/birth-details'),
            ),
          ],
          if (note != null) ...[
            const SizedBox(height: AppSpacing.sm),
            _infoBanner(note),
          ],
        ],
      ),
    );
  }

  Widget _infoBanner(String text, {String? actionLabel, VoidCallback? onAction}) {
    final hasAction = actionLabel != null && onAction != null;
    return Container(
      padding: EdgeInsets.fromLTRB(AppSpacing.sm, 10, AppSpacing.sm, hasAction ? 0 : 10),
      decoration: BoxDecoration(color: AppColors.infoSoft, borderRadius: BorderRadius.circular(AppRadius.md)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info_outline_rounded, color: AppColors.info, size: 18),
          const SizedBox(width: AppSpacing.xs),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(text, style: AppText.caption.copyWith(color: AppColors.textPrimary, fontSize: 12.5)),
                if (hasAction)
                  TextButton(
                    onPressed: onAction,
                    style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: const Size(0, 44)),
                    child: Text(actionLabel, style: const TextStyle(fontSize: 13)),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _askButton(String prompt, String astrologer) {
    return AppButton(
      label: 'Ask AI about this',
      icon: Icons.auto_awesome_rounded,
      variant: AppButtonVariant.secondary,
      height: 48,
      onPressed: () => _askAI(prompt, astrologer),
    );
  }

  Widget _kvRow(String label, String value, {String? sub}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: AppText.body.copyWith(color: AppColors.textPrimary)),
                if (sub != null) Text(sub, style: AppText.caption),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Flexible(
            child: Text(value, textAlign: TextAlign.end, style: AppText.bodyStrong),
          ),
        ],
      ),
    );
  }

  /// Interleaves [rows] with hairline dividers.
  List<Widget> _divided(List<Widget> rows) => [
        for (int i = 0; i < rows.length; i++) ...[
          if (i > 0) const Divider(height: 1),
          rows[i],
        ],
      ];

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

    return _section(
      'Your birth chart',
      'A snapshot of the sky at the moment you were born. Each box is a house, an area of life such as career or marriage.',
      [
        _chartCard(title: 'Rasi chart (D1)', ascendant: asc, planets: planets, centerLabel: 'Rasi (D1)'),
        const SizedBox(height: AppSpacing.sm),
        _askButton('Analyze my Birth Chart (D1): $asc Lagna and my planetary placements.', 'Pandit Shastri'),
        const SizedBox(height: AppSpacing.xl),
        AppCard(
          padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.md, AppSpacing.md, AppSpacing.xxs),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _cardTitle('Key facts', icon: Icons.fact_check_outlined),
              const SizedBox(height: AppSpacing.xxs),
              ..._divided([
                _kvRow('Lagna (Ascendant)', asc, sub: ascIdx >= 0 ? 'How you meet the world · lord ${Vedic.signLords[ascIdx]}' : null),
                _kvRow('Moon sign (Rasi)', Vedic.text(k['moonSign']), sub: 'Mind & emotions'),
                _kvRow('Sun sign', Vedic.text(k['sunSign']), sub: 'Soul & vitality'),
                _kvRow('Nakshatra', pada != null ? '${Vedic.text(k['nakshatra'])} (Pada $pada)' : Vedic.text(k['nakshatra']),
                    sub: 'Birth star'),
                if (md.isNotEmpty)
                  _kvRow('Current dasha', ad.isNotEmpty ? '$md / $ad' : md, sub: 'Mahadasha / Antardasha'),
              ]),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        Material(
          color: AppColors.surface,
          clipBehavior: Clip.antiAlias,
          shape: RoundedRectangleBorder(borderRadius: AppRadius.card, side: const BorderSide(color: AppColors.border)),
          child: Theme(
            data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
            child: ExpansionTile(
              leading: const _IconTile(icon: Icons.grid_view_rounded, size: 36),
              title: const Text('House-by-house breakdown', style: AppText.subtitle),
              subtitle: Text('What occupies each of your 12 houses', style: AppText.caption.copyWith(color: AppColors.textSecondary)),
              iconColor: AppColors.textSecondary,
              collapsedIconColor: AppColors.textSecondary,
              childrenPadding: const EdgeInsets.fromLTRB(AppSpacing.md, 0, AppSpacing.md, AppSpacing.xs),
              children: _divided(List.generate(12, (i) => _houseRow(i + 1, ascIdx, planets))),
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        const Text('Sidereal zodiac · Lahiri ayanamsa · Whole-sign houses', style: AppText.caption),
      ],
    );
  }

  Widget _houseRow(int house, int ascIdx, List<Map<String, dynamic>> planets) {
    final signIdx = ascIdx >= 0 ? (ascIdx + house - 1) % 12 : -1;
    final occupants = planets.where((p) => Vedic.toInt(p['house']) == house).toList();
    final has = occupants.isNotEmpty;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 30,
            height: 30,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: house == 1 ? AppColors.primarySoft : AppColors.surfaceMuted,
              shape: BoxShape.circle,
            ),
            child: Text(
              '$house',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 12,
                color: house == 1 ? AppColors.primaryDark : AppColors.textSecondary,
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  signIdx >= 0
                      ? '${kZodiacSigns[signIdx]} · lord ${Vedic.signLords[signIdx]}${house == 1 ? ' · Lagna' : ''}'
                      : 'House $house',
                  style: AppText.bodyStrong,
                ),
                Text(kHouseMeanings[house] ?? '', style: AppText.caption.copyWith(color: AppColors.textSecondary)),
                const SizedBox(height: 2),
                Text(
                  has
                      ? occupants
                          .map((p) =>
                              '${Vedic.planetKey(p['name'])}${Vedic.isRetrograde(p) && !Vedic.isNode(p['name']) ? ' (R)' : ''}')
                          .join(', ')
                      : 'No planets',
                  style: has
                      ? const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.primaryDark)
                      : AppText.caption,
                ),
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
    return _section(
      isD9 ? 'Navamsha chart (D9)' : 'Dasamsha chart (D10)',
      isD9
          ? 'A finer chart read for marriage, dharma and how strong each planet really is, especially later in life.'
          : 'A zoomed-in chart for career, profession, status and public recognition.',
      [
        _chartCard(
          title: isD9 ? 'Navamsha (D9)' : 'Dasamsha (D10)',
          ascendant: chart.ascendant,
          planets: chart.planets,
          centerLabel: isD9 ? 'Navamsha (D9)' : 'Dasamsha (D10)',
          note: chart.lagnaApproximate
              ? 'The exact ascendant degree is not stored for this profile, so the ${isD9 ? 'D9' : 'D10'} Lagna is approximate. Planet signs are exact.'
              : null,
        ),
        const SizedBox(height: AppSpacing.sm),
        _askButton(
          isD9
              ? 'Analyze my Navamsha (D9) chart (${chart.ascendant} Lagna) for marriage and partnership.'
              : 'Analyze my Dasamsha (D10) chart (${chart.ascendant} Lagna) for career and authority.',
          isD9 ? 'Dr. Ananya Roy' : 'Acharya Dev Sharma',
        ),
        const SizedBox(height: AppSpacing.xl),
        _buildPlanetTable(chart.planets, isD9 ? 'D9 placements' : 'D10 placements', showNakshatra: false),
      ],
    );
  }

  // ------------------------------------------------------------- planets
  Widget _buildPlanetTable(List<Map<String, dynamic>> planets, String title, {required bool showNakshatra}) {
    final rows = planets.map((p) {
      final name = Vedic.planetKey(p['name']);
      final retro = Vedic.isRetrograde(p);
      final nak = Vedic.text(p['nakshatra'], '');
      final pada = Vedic.toInt(p['nakshatraPada']);
      final lord = Vedic.text(p['planetLord'], '');
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: AppColors.surfaceMuted,
                borderRadius: BorderRadius.circular(AppRadius.sm + 2),
              ),
              child: Text(
                Vedic.abbr(p['name']),
                style: const TextStyle(fontWeight: FontWeight.w800, color: AppColors.cosmicLight, fontSize: 13),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(child: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.bodyStrong)),
                      if (retro) ...[
                        const SizedBox(width: 6),
                        const AppBadge(label: 'R', color: AppColors.danger),
                      ],
                    ],
                  ),
                  Text(
                    '${Vedic.text(p['sign'])} · House ${Vedic.text(p['house'])}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.caption.copyWith(color: AppColors.textSecondary, fontSize: 13),
                  ),
                  if (showNakshatra && nak.isNotEmpty)
                    Text(
                      '$nak${pada != null ? ' (Pada $pada)' : ''}${lord.isNotEmpty ? ' · Lord $lord' : ''}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.caption,
                    ),
                ],
              ),
            ),
            if (showNakshatra) ...[
              const SizedBox(width: AppSpacing.xs),
              Text(
                Vedic.formatDegree(p['degree']),
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                  color: AppColors.textPrimary,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ],
        ),
      );
    }).toList();

    return AppCard(
      padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.md, AppSpacing.md, AppSpacing.xs),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _cardTitle(title, icon: Icons.public_rounded),
          const SizedBox(height: AppSpacing.xxs),
          if (planets.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: AppSpacing.md),
              child: Text('No planetary data available.', style: AppText.body),
            ),
          ..._divided(rows),
          if (planets.any((p) => Vedic.isNode(p['name'])))
            const Padding(
              padding: EdgeInsets.only(top: AppSpacing.xxs, bottom: AppSpacing.xs),
              child: Text('Rahu & Ketu always move retrograde (mean motion). R = retrograde.', style: AppText.caption),
            ),
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
    const title = 'Planetary periods (Dasha)';
    const explanation =
        'Life unfolds in planetary periods. The planet running now colours the main themes of this phase of your life.';

    if (t == null || t.currentMaha == null) {
      // Fall back to what the server stored.
      return _section(title, explanation, [
        _dashaHero(
          Vedic.text(server['currentMahadasha']),
          Vedic.text(server['antardasha']),
          Vedic.text(server['dashaEndDate']),
        ),
        const SizedBox(height: AppSpacing.sm),
        _infoBanner('A detailed dasha timeline needs the birth date, time and Moon position for this profile.'),
      ]);
    }

    final md = t.currentMaha!;
    final ad = t.currentAntar;
    return _section(title, explanation, [
      _dashaHero(md.lord, ad?.lord ?? '—', fmt.format((ad ?? md).end.toLocal()), mdEnd: fmt.format(md.end.toLocal())),
      const SizedBox(height: AppSpacing.sm),
      _askButton('Explain my current ${md.lord} Mahadasha and ${ad?.lord ?? ''} Antardasha predictions.', 'Tarun Shastri'),
      const SizedBox(height: AppSpacing.xl),
      AppCard(
        padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.md, AppSpacing.md, AppSpacing.xs),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _cardTitle('Sub-periods in ${md.lord} Mahadasha', icon: Icons.timelapse_rounded),
            const SizedBox(height: AppSpacing.xs),
            ..._divided(t.antardashas
                .map((p) => _periodRow(p, fmt, active: p.contains(now), past: p.end.isBefore(now)))
                .toList()),
          ],
        ),
      ),
      const SizedBox(height: AppSpacing.md),
      AppCard(
        padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.md, AppSpacing.md, AppSpacing.xs),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _cardTitle('Vimshottari Mahadasha timeline', icon: Icons.timeline_rounded),
            const SizedBox(height: AppSpacing.xxs),
            const Text('A 120-year cycle that starts from the lord of your Moon nakshatra.', style: AppText.caption),
            const SizedBox(height: AppSpacing.xs),
            ..._divided(t.mahadashas
                .map((p) => _periodRow(p, fmt, active: p.contains(now), past: p.end.isBefore(now), showYears: true))
                .toList()),
          ],
        ),
      ),
    ]);
  }

  Widget _dashaHero(String md, String ad, String endsOn, {String? mdEnd}) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md + 2),
      decoration: BoxDecoration(gradient: AppColors.cosmicGradient, borderRadius: AppRadius.card),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.hourglass_top_rounded, color: AppColors.gold, size: 18),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: Text('Running now',
                    overflow: TextOverflow.ellipsis,
                    style: AppText.caption.copyWith(color: AppColors.textOnDarkMuted, fontSize: 13)),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: _heroCol('Mahadasha', md, AppColors.textOnDark, sub: mdEnd != null ? 'till $mdEnd' : null)),
              const SizedBox(width: AppSpacing.sm),
              Expanded(child: _heroCol('Antardasha', ad, AppColors.gold, sub: 'till $endsOn')),
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
        Text(label, style: AppText.caption.copyWith(color: AppColors.textOnDarkMuted)),
        const SizedBox(height: 2),
        Text(value, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.headline.copyWith(color: color)),
        if (sub != null) Text(sub, style: AppText.caption.copyWith(color: AppColors.textOnDarkMuted)),
      ],
    );
  }

  Widget _periodRow(DashaPeriod p, DateFormat fmt, {required bool active, required bool past, bool showYears = false}) {
    final color = past ? AppColors.textTertiary : AppColors.textPrimary;
    final row = Padding(
      padding: EdgeInsets.symmetric(vertical: 10, horizontal: active ? AppSpacing.xs : 0),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  showYears ? '${p.lord} · ${Vedic.dashaYears[p.lord]} yrs' : p.lord,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontWeight: active ? FontWeight.w700 : FontWeight.w600, fontSize: 14, color: color),
                ),
                const SizedBox(height: 2),
                Text(
                  '${fmt.format(p.start.toLocal())} – ${fmt.format(p.end.toLocal())}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12.5, color: past ? AppColors.textTertiary : AppColors.textSecondary),
                ),
              ],
            ),
          ),
          if (active) ...[const SizedBox(width: AppSpacing.xs), const AppBadge(label: 'Now')],
          if (past && !active) ...[
            const SizedBox(width: AppSpacing.xs),
            const Icon(Icons.check_rounded, size: 16, color: AppColors.textTertiary),
          ],
        ],
      ),
    );
    if (!active) return row;
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 2),
      decoration: BoxDecoration(color: AppColors.primarySoft, borderRadius: BorderRadius.circular(AppRadius.sm)),
      child: row,
    );
  }

  // ------------------------------------------------------------- Panchang & Avakhada
  Widget _buildPanchangAvakhada(Map<String, dynamic> k) {
    final panchang = Vedic.birthPanchang(k);
    final avakhada = Vedic.avakhada(k);
    Widget card(String title, IconData icon, Map<String, String> data) {
      final entries = data.entries.toList();
      return AppCard(
        padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.md, AppSpacing.md, AppSpacing.xxs),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _cardTitle(title, icon: icon),
            const SizedBox(height: AppSpacing.xxs),
            if (entries.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: AppSpacing.md),
                child: Text('Not available for this profile.', style: AppText.body),
              ),
            ..._divided([for (final e in entries) _kvRow(e.key, e.value)]),
          ],
        ),
      );
    }

    return _section(
      'Birth Panchang',
      'The Hindu calendar at your birth moment (tithi, nakshatra, yoga), plus the Avakhada values used for Kundli matching.',
      [
        card('Birth Panchang', Icons.wb_sunny_outlined, panchang),
        const SizedBox(height: AppSpacing.md),
        card('Avakhada Chakra', Icons.auto_awesome_outlined, avakhada),
        const SizedBox(height: AppSpacing.sm),
        const Text(
          'Avakhada values are used for Kundli matching (Guna Milan). Birth Panchang is calculated for the birth moment in IST.',
          style: AppText.caption,
        ),
      ],
    );
  }

  // ------------------------------------------------------------- report
  Widget _buildReport() {
    const title = 'Your life report';
    const explanation = 'A plain-language reading of your whole chart: personality, career, relationships, health and timing.';
    if (_loadingReport) {
      return _section(title, explanation, [
        Semantics(
          label: 'Preparing your complete life report',
          child: AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    SkeletonBox(width: 36, height: 36),
                    SizedBox(width: AppSpacing.sm),
                    Expanded(child: SkeletonBox(height: 16)),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),
                for (final f in const [1.0, 0.95, 0.9, 0.7]) ...[
                  FractionallySizedBox(widthFactor: f, child: const SkeletonBox(height: 12, radius: 6)),
                  const SizedBox(height: 10),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        const Text('Preparing your complete life report… This can take up to a minute.', style: AppText.caption),
      ]);
    }
    if (_reportError != null) {
      return _section(title, explanation, [
        AppCard(
          child: AppStateView.error(
            title: 'Report not ready',
            message: _reportError,
            compact: true,
            onAction: () => _loadReport(force: true),
          ),
        ),
      ]);
    }
    final r = _report;
    if (r == null) {
      return _section(title, explanation, [
        AppCard(
          child: AppStateView(
            icon: Icons.auto_awesome_rounded,
            title: 'Get your full life report',
            message: 'Our AI astrologer reads your complete chart and explains it in simple words.',
            actionLabel: 'Generate life report',
            compact: true,
            onAction: _loadReport,
          ),
        ),
      ]);
    }
    return _section(title, explanation, [
      KundliReportView(report: r),
      Align(
        alignment: Alignment.centerRight,
        child: TextButton.icon(
          onPressed: () => _loadReport(force: true),
          icon: const Icon(Icons.refresh_rounded, size: 18),
          label: const Text('Regenerate'),
        ),
      ),
    ]);
  }
}

/// White, pinned section tab bar.
class _TabBarHeader extends SliverPersistentHeaderDelegate {
  final TabBar tabBar;
  const _TabBarHeader(this.tabBar);

  @override
  double get minExtent => 49;
  @override
  double get maxExtent => 49;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: const Border(bottom: BorderSide(color: AppColors.border)),
        boxShadow: overlapsContent || shrinkOffset > 0 ? AppShadows.card : null,
      ),
      child: tabBar,
    );
  }

  @override
  bool shouldRebuild(covariant _TabBarHeader oldDelegate) => oldDelegate.tabBar != tabBar;
}

String _formatDob(dynamic raw) {
  final s = Vedic.text(raw, '');
  if (s.isEmpty) return 'date not set';
  final dt = DateTime.tryParse(s);
  if (dt == null) return s;
  final local = dt.isUtc ? dt.add(const Duration(hours: 5, minutes: 30)) : dt;
  return DateFormat('d MMM yyyy').format(local);
}

String _formatTob(dynamic raw) {
  final m = RegExp(r'(\d{1,2}):(\d{2})').firstMatch(Vedic.text(raw, ''));
  if (m == null) return Vedic.text(raw, '');
  final h = int.parse(m.group(1)!), min = int.parse(m.group(2)!);
  if (h > 23 || min > 59) return Vedic.text(raw, '');
  return DateFormat('h:mm a').format(DateTime(2000, 1, 1, h, min));
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

    if (kundli == null) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Kundli'),
          actions: [
            IconButton(
              tooltip: 'Switch profile',
              icon: const Icon(Icons.swap_horiz_rounded),
              onPressed: () => showKundliProfilePicker(context),
            ),
          ],
        ),
        body: const KundliEmptyState(),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      body: KundliExplorer(
        key: ValueKey(Vedic.identity(kundli)),
        kundli: kundli,
        initialTab: initialTab,
        showBack: true,
      ),
    );
  }
}
