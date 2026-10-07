import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart' show DateFormat;

// ============================================================================
// Panchang calculation engine (pure Dart, no network)
// ----------------------------------------------------------------------------
// Sun & Moon positions use the low-precision Meeus algorithms (Sun ~0.01°,
// Moon ~0.05°), converted to sidereal longitudes with the Lahiri (Chitrapaksha)
// ayanamsa. That is accurate to a couple of minutes for Tithi / Nakshatra /
// Yoga / Karana transition times. Sunrise & sunset use the NOAA solar
// equations. Muhurat windows (Rahu Kaal, Yamaganda, Gulika, Abhijit,
// Choghadiya) follow the standard day-division rules.
// ============================================================================

class PanchangLocation {
  final String name;
  final double latitude;
  final double longitude;
  final Duration utcOffset;

  const PanchangLocation({
    required this.name,
    required this.latitude,
    required this.longitude,
    required this.utcOffset,
  });
}

const PanchangLocation kDefaultPanchangLocation = PanchangLocation(
  name: 'New Delhi, India',
  latitude: 28.6139,
  longitude: 77.2090,
  utcOffset: Duration(hours: 5, minutes: 30),
);

const List<String> kRashiNames = [
  'Aries', 'Taurus', 'Gemini', 'Cancer', 'Leo', 'Virgo',
  'Libra', 'Scorpio', 'Sagittarius', 'Capricorn', 'Aquarius', 'Pisces',
];

const List<String> kNakshatraNames = [
  'Ashwini', 'Bharani', 'Krittika', 'Rohini', 'Mrigashira', 'Ardra',
  'Punarvasu', 'Pushya', 'Ashlesha', 'Magha', 'Purva Phalguni', 'Uttara Phalguni',
  'Hasta', 'Chitra', 'Swati', 'Vishakha', 'Anuradha', 'Jyeshtha',
  'Moola', 'Purva Ashadha', 'Uttara Ashadha', 'Shravana', 'Dhanishta', 'Shatabhisha',
  'Purva Bhadrapada', 'Uttara Bhadrapada', 'Revati',
];

const List<String> _tithiBaseNames = [
  'Pratipada', 'Dwitiya', 'Tritiya', 'Chaturthi', 'Panchami', 'Shashthi', 'Saptami',
  'Ashtami', 'Navami', 'Dashami', 'Ekadashi', 'Dwadashi', 'Trayodashi', 'Chaturdashi',
];

const List<String> _yogaNames = [
  'Vishkambha', 'Priti', 'Ayushman', 'Saubhagya', 'Shobhana', 'Atiganda', 'Sukarma',
  'Dhriti', 'Shoola', 'Ganda', 'Vriddhi', 'Dhruva', 'Vyaghata', 'Harshana', 'Vajra',
  'Siddhi', 'Vyatipata', 'Variyan', 'Parigha', 'Shiva', 'Siddha', 'Sadhya', 'Shubha',
  'Shukla', 'Brahma', 'Indra', 'Vaidhriti',
];

const List<String> _movableKaranas = ['Bava', 'Balava', 'Kaulava', 'Taitila', 'Garaja', 'Vanija', 'Vishti (Bhadra)'];

const List<String> _weekdayNames = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];

/// A named Panchang element and (optionally) the instant (UTC) it ends.
class PanchangElement {
  final int index;
  final String name;
  final DateTime? endsAtUtc;

  const PanchangElement(this.index, this.name, this.endsAtUtc);
}

/// A time window, stored as UTC instants.
class TimeWindow {
  final DateTime startUtc;
  final DateTime endUtc;

  const TimeWindow(this.startUtc, this.endUtc);

  bool contains(DateTime utc) => !utc.isBefore(startUtc) && utc.isBefore(endUtc);
}

class ChoghadiyaSlot {
  final String name;
  final String meaning;
  final String status; // Best / Auspicious / Neutral / Avoid
  final TimeWindow window;

  const ChoghadiyaSlot(this.name, this.meaning, this.status, this.window);
}

class DailyPanchang {
  final DateTime civilDate; // y/m/d at the location
  final PanchangLocation location;
  final String vaar;
  final String paksha;
  final PanchangElement tithi;
  final PanchangElement nakshatra;
  final int nakshatraPada;
  final PanchangElement yoga;
  final PanchangElement karana;
  final String moonRashi;
  final String sunRashi;
  final int moonIlluminationPct;
  final DateTime sunriseUtc;
  final DateTime sunsetUtc;
  final TimeWindow rahuKaal;
  final TimeWindow yamaganda;
  final TimeWindow gulika;
  final TimeWindow abhijit;
  final List<ChoghadiyaSlot> choghadiya;

  const DailyPanchang({
    required this.civilDate,
    required this.location,
    required this.vaar,
    required this.paksha,
    required this.tithi,
    required this.nakshatra,
    required this.nakshatraPada,
    required this.yoga,
    required this.karana,
    required this.moonRashi,
    required this.sunRashi,
    required this.moonIlluminationPct,
    required this.sunriseUtc,
    required this.sunsetUtc,
    required this.rahuKaal,
    required this.yamaganda,
    required this.gulika,
    required this.abhijit,
    required this.choghadiya,
  });

  Duration get dayLength => sunsetUtc.difference(sunriseUtc);
}

/// Snapshot of the five limbs at an arbitrary instant (used for birth Panchang).
class PanchangSnapshot {
  final String tithi;
  final String paksha;
  final String nakshatra;
  final int nakshatraPada;
  final String yoga;
  final String karana;
  final String vaar;

  const PanchangSnapshot({
    required this.tithi,
    required this.paksha,
    required this.nakshatra,
    required this.nakshatraPada,
    required this.yoga,
    required this.karana,
    required this.vaar,
  });
}

class PanchangCalculator {
  static const double _deg = math.pi / 180.0;
  static const double _nakSpan = 360.0 / 27.0;

  static double _norm(double d) {
    final r = d % 360.0;
    return r < 0 ? r + 360.0 : r;
  }

  static double julianDay(DateTime utc) => utc.toUtc().millisecondsSinceEpoch / 86400000.0 + 2440587.5;

  /// Apparent tropical longitude of the Sun (degrees).
  static double sunTropical(double jd) {
    final t = (jd - 2451545.0) / 36525.0;
    final l0 = 280.46646 + 36000.76983 * t + 0.0003032 * t * t;
    final m = (357.52911 + 35999.05029 * t - 0.0001537 * t * t) * _deg;
    final c = (1.914602 - 0.004817 * t - 0.000014 * t * t) * math.sin(m) +
        (0.019993 - 0.000101 * t) * math.sin(2 * m) +
        0.000289 * math.sin(3 * m);
    final omega = (125.04 - 1934.136 * t) * _deg;
    return _norm(l0 + c - 0.00569 - 0.00478 * math.sin(omega));
  }

  /// Tropical longitude of the Moon (degrees), main periodic terms of Meeus ch. 47.
  static double moonTropical(double jd) {
    final t = (jd - 2451545.0) / 36525.0;
    final lp = 218.3164477 + 481267.88123421 * t - 0.0015786 * t * t;
    final d = (297.8501921 + 445267.1114034 * t - 0.0018819 * t * t) * _deg;
    final m = (357.5291092 + 35999.0502909 * t - 0.0001536 * t * t) * _deg;
    final mp = (134.9633964 + 477198.8675055 * t + 0.0087414 * t * t) * _deg;
    final f = (93.2720950 + 483202.0175233 * t - 0.0036539 * t * t) * _deg;
    final e = 1 - 0.002516 * t - 0.0000074 * t * t;

    double s = 0;
    s += 6.288774 * math.sin(mp);
    s += 1.274027 * math.sin(2 * d - mp);
    s += 0.658314 * math.sin(2 * d);
    s += 0.213618 * math.sin(2 * mp);
    s += -0.185116 * e * math.sin(m);
    s += -0.114332 * math.sin(2 * f);
    s += 0.058793 * math.sin(2 * d - 2 * mp);
    s += 0.057066 * e * math.sin(2 * d - m - mp);
    s += 0.053322 * math.sin(2 * d + mp);
    s += 0.045758 * e * math.sin(2 * d - m);
    s += -0.040923 * e * math.sin(m - mp);
    s += -0.034720 * math.sin(d);
    s += -0.030383 * e * math.sin(m + mp);
    s += 0.015327 * math.sin(2 * d - 2 * f);
    s += -0.012528 * math.sin(mp + 2 * f);
    s += 0.010980 * math.sin(mp - 2 * f);
    s += 0.010675 * math.sin(4 * d - mp);
    s += 0.010034 * math.sin(3 * mp);
    s += 0.008548 * math.sin(4 * d - 2 * mp);
    s += -0.007888 * e * math.sin(2 * d + m - mp);
    s += -0.006766 * e * math.sin(2 * d + m);
    s += -0.005163 * math.sin(d - mp);
    s += 0.004987 * e * math.sin(d + m);
    s += 0.004036 * e * math.sin(2 * d - m + mp);
    s += 0.003994 * math.sin(2 * d + 2 * mp);
    s += 0.003861 * math.sin(4 * d);
    s += 0.003665 * math.sin(2 * d - 3 * mp);
    s += -0.002689 * e * math.sin(m - 2 * mp);
    s += -0.002602 * math.sin(2 * d - mp + 2 * f);
    s += 0.002390 * e * math.sin(2 * d - m - 2 * mp);
    s += -0.002348 * math.sin(d + mp);
    s += 0.002236 * e * e * math.sin(2 * d - 2 * m);
    s += -0.002120 * e * math.sin(m + 2 * mp);
    s += -0.002069 * e * e * math.sin(2 * m);

    // Nutation in longitude (dominant term) so it matches the apparent Sun.
    final omega = (125.04452 - 1934.136261 * t) * _deg;
    return _norm(lp + s - 0.004778 * math.sin(omega));
  }

  /// Lahiri (Chitrapaksha) ayanamsa in degrees.
  static double lahiriAyanamsa(double jd) {
    final years = (jd - 2451545.0) / 365.25;
    return 23.85709 + years * (50.2788 / 3600.0);
  }

  static double siderealSun(DateTime utc) {
    final jd = julianDay(utc);
    return _norm(sunTropical(jd) - lahiriAyanamsa(jd));
  }

  static double siderealMoon(DateTime utc) {
    final jd = julianDay(utc);
    return _norm(moonTropical(jd) - lahiriAyanamsa(jd));
  }

  static double _elongation(DateTime utc) {
    final jd = julianDay(utc);
    return _norm(moonTropical(jd) - sunTropical(jd));
  }

  static int tithiIndexAt(DateTime utc) => (_elongation(utc) / 12.0).floor() % 30;
  static int karanaIndexAt(DateTime utc) => (_elongation(utc) / 6.0).floor() % 60;
  static int nakshatraIndexAt(DateTime utc) => (siderealMoon(utc) / _nakSpan).floor() % 27;
  static int yogaIndexAt(DateTime utc) => (_norm(siderealSun(utc) + siderealMoon(utc)) / _nakSpan).floor() % 27;

  static String tithiName(int idx) {
    if (idx == 14) return 'Purnima';
    if (idx == 29) return 'Amavasya';
    return _tithiBaseNames[idx % 15];
  }

  static String pakshaFor(int tithiIdx) => tithiIdx < 15 ? 'Shukla Paksha' : 'Krishna Paksha';

  static String karanaName(int idx) {
    if (idx == 0) return 'Kimstughna';
    if (idx == 57) return 'Shakuni';
    if (idx == 58) return 'Chatushpada';
    if (idx == 59) return 'Naga';
    return _movableKaranas[(idx - 1) % 7];
  }

  /// Finds when [indexAt] changes value after [start] (searches up to [maxHours]).
  static DateTime? _findChange(DateTime start, int Function(DateTime) indexAt, {int maxHours = 40}) {
    final startIdx = indexAt(start);
    DateTime lo = start;
    DateTime? hi;
    for (int h = 1; h <= maxHours; h++) {
      final probe = start.add(Duration(hours: h));
      if (indexAt(probe) != startIdx) {
        hi = probe;
        break;
      }
      lo = probe;
    }
    if (hi == null) return null;
    while (hi!.difference(lo).inSeconds > 30) {
      final mid = lo.add(Duration(milliseconds: hi.difference(lo).inMilliseconds ~/ 2));
      if (indexAt(mid) == startIdx) {
        lo = mid;
      } else {
        hi = mid;
      }
    }
    return hi;
  }

  /// Sunrise & sunset (UTC) for a civil date at a location (NOAA equations).
  static (DateTime, DateTime) sunriseSunset(DateTime civilDate, double lat, double lon) {
    final y = civilDate.year, mo = civilDate.month, d = civilDate.day;
    final dayOfYear = DateTime.utc(y, mo, d).difference(DateTime.utc(y, 1, 1)).inDays + 1;
    final isLeap = (y % 4 == 0 && y % 100 != 0) || y % 400 == 0;
    final gamma = 2 * math.pi / (isLeap ? 366 : 365) * (dayOfYear - 1);
    final eqTime = 229.18 *
        (0.000075 +
            0.001868 * math.cos(gamma) -
            0.032077 * math.sin(gamma) -
            0.014615 * math.cos(2 * gamma) -
            0.040849 * math.sin(2 * gamma));
    final decl = 0.006918 -
        0.399912 * math.cos(gamma) +
        0.070257 * math.sin(gamma) -
        0.006758 * math.cos(2 * gamma) +
        0.000907 * math.sin(2 * gamma) -
        0.002697 * math.cos(3 * gamma) +
        0.00148 * math.sin(3 * gamma);
    final latR = lat * _deg;
    var cosHa = math.cos(90.833 * _deg) / (math.cos(latR) * math.cos(decl)) - math.tan(latR) * math.tan(decl);
    cosHa = cosHa.clamp(-1.0, 1.0);
    final haDeg = math.acos(cosHa) / _deg;
    final riseMin = 720 - 4 * (lon + haDeg) - eqTime;
    final setMin = 720 - 4 * (lon - haDeg) - eqTime;
    final base = DateTime.utc(y, mo, d);
    return (
      base.add(Duration(seconds: (riseMin * 60).round())),
      base.add(Duration(seconds: (setMin * 60).round())),
    );
  }

  /// Weekday name for a civil date (Vedic day starts at sunrise; caller passes the sunrise date).
  static String weekdayName(DateTime civilDate) => _weekdayNames[civilDate.weekday - 1];

  // Rahu Kaal / Yamaganda / Gulika segment (1-based of 8 day parts), indexed Mon..Sun.
  static const List<int> _rahuSeg = [2, 7, 5, 6, 4, 3, 8];
  static const List<int> _yamaSeg = [4, 3, 2, 1, 7, 6, 5];
  static const List<int> _gulikaSeg = [6, 5, 4, 3, 2, 1, 7];

  // Choghadiya cycle and the first slot of the day per weekday (Mon..Sun).
  static const List<String> _choghadiyaCycle = ['Udveg', 'Char', 'Labh', 'Amrit', 'Kaal', 'Shubh', 'Rog'];
  static const List<int> _choghadiyaStart = [3, 6, 2, 5, 1, 4, 0];
  static const Map<String, List<String>> _choghadiyaInfo = {
    'Udveg': ['Anxiety', 'Avoid'],
    'Char': ['Good for travel', 'Neutral'],
    'Labh': ['Gain', 'Auspicious'],
    'Amrit': ['Nectar – best', 'Best'],
    'Kaal': ['Loss', 'Avoid'],
    'Shubh': ['Auspicious', 'Auspicious'],
    'Rog': ['Illness', 'Avoid'],
  };

  static DailyPanchang compute(DateTime civilDate, {PanchangLocation location = kDefaultPanchangLocation}) {
    final date = DateTime.utc(civilDate.year, civilDate.month, civilDate.day);
    final (sunrise, sunset) = sunriseSunset(date, location.latitude, location.longitude);
    final dayLen = sunset.difference(sunrise);
    final part = Duration(milliseconds: dayLen.inMilliseconds ~/ 8);
    final wd = date.weekday - 1; // 0 = Monday

    TimeWindow seg(int oneBased) => TimeWindow(
          sunrise.add(part * (oneBased - 1)),
          sunrise.add(part * oneBased),
        );

    final muhurta = Duration(milliseconds: dayLen.inMilliseconds ~/ 15);
    final abhijit = TimeWindow(sunrise.add(muhurta * 7), sunrise.add(muhurta * 8));

    final chog = <ChoghadiyaSlot>[];
    for (int i = 0; i < 8; i++) {
      final name = _choghadiyaCycle[(_choghadiyaStart[wd] + i) % 7];
      final info = _choghadiyaInfo[name]!;
      chog.add(ChoghadiyaSlot(name, info[0], info[1], seg(i + 1)));
    }

    final tIdx = tithiIndexAt(sunrise);
    final nIdx = nakshatraIndexAt(sunrise);
    final yIdx = yogaIndexAt(sunrise);
    final kIdx = karanaIndexAt(sunrise);
    final moonSid = siderealMoon(sunrise);
    final sunSid = siderealSun(sunrise);
    final elong = _elongation(sunrise);

    return DailyPanchang(
      civilDate: date,
      location: location,
      vaar: weekdayName(date),
      paksha: pakshaFor(tIdx),
      tithi: PanchangElement(tIdx, tithiName(tIdx), _findChange(sunrise, tithiIndexAt)),
      nakshatra: PanchangElement(nIdx, kNakshatraNames[nIdx], _findChange(sunrise, nakshatraIndexAt)),
      nakshatraPada: ((moonSid % _nakSpan) / (_nakSpan / 4)).floor() + 1,
      yoga: PanchangElement(yIdx, _yogaNames[yIdx], _findChange(sunrise, yogaIndexAt)),
      karana: PanchangElement(kIdx, karanaName(kIdx), _findChange(sunrise, karanaIndexAt, maxHours: 20)),
      moonRashi: kRashiNames[(moonSid / 30).floor() % 12],
      sunRashi: kRashiNames[(sunSid / 30).floor() % 12],
      moonIlluminationPct: ((1 - math.cos(elong * _deg)) / 2 * 100).round(),
      sunriseUtc: sunrise,
      sunsetUtc: sunset,
      rahuKaal: seg(_rahuSeg[wd]),
      yamaganda: seg(_yamaSeg[wd]),
      gulika: seg(_gulikaSeg[wd]),
      abhijit: abhijit,
      choghadiya: chog,
    );
  }

  /// Five limbs at an exact instant (e.g. birth time). [lat]/[lon] and [utcOffset]
  /// determine the Vedic weekday (which changes at local sunrise).
  static PanchangSnapshot snapshotAt(
    DateTime utc, {
    double lat = 28.6139,
    double lon = 77.2090,
    Duration utcOffset = const Duration(hours: 5, minutes: 30),
  }) {
    final tIdx = tithiIndexAt(utc);
    final moonSid = siderealMoon(utc);
    final nIdx = (moonSid / _nakSpan).floor() % 27;
    final local = utc.add(utcOffset);
    var civil = DateTime.utc(local.year, local.month, local.day);
    final (sunrise, _) = sunriseSunset(civil, lat, lon);
    if (utc.isBefore(sunrise)) civil = civil.subtract(const Duration(days: 1));
    return PanchangSnapshot(
      tithi: tithiName(tIdx),
      paksha: pakshaFor(tIdx),
      nakshatra: kNakshatraNames[nIdx],
      nakshatraPada: ((moonSid % _nakSpan) / (_nakSpan / 4)).floor() + 1,
      yoga: _yogaNames[yogaIndexAt(utc)],
      karana: karanaName(karanaIndexAt(utc)),
      vaar: weekdayName(civil),
    );
  }

  /// Today's civil date at the location.
  static DateTime todayAt(PanchangLocation location) {
    final local = DateTime.now().toUtc().add(location.utcOffset);
    return DateTime.utc(local.year, local.month, local.day);
  }

  static final Map<String, DailyPanchang> _cache = {};

  /// Cached daily computation (keyed by date + location).
  static DailyPanchang cached(DateTime civilDate, {PanchangLocation location = kDefaultPanchangLocation}) {
    final key = '${location.name}|${civilDate.year}-${civilDate.month}-${civilDate.day}';
    final hit = _cache[key];
    if (hit != null) return hit;
    if (_cache.length > 60) _cache.clear();
    return _cache[key] = compute(civilDate, location: location);
  }

  /// Formats a UTC instant as local wall-clock time at the location.
  static String formatTime(DateTime utc, PanchangLocation location) =>
      DateFormat('hh:mm a').format(utc.add(location.utcOffset));

  static String formatWindow(TimeWindow w, PanchangLocation location) =>
      '${formatTime(w.startUtc, location)} – ${formatTime(w.endUtc, location)}';

  /// "till 04:12 PM" or "till 04:12 PM (Tue)" when the end falls on another day.
  static String formatEnd(DateTime? endUtc, DateTime civilDate, PanchangLocation location) {
    if (endUtc == null) return 'full day';
    final local = endUtc.add(location.utcOffset);
    final sameDay = local.year == civilDate.year && local.month == civilDate.month && local.day == civilDate.day;
    final time = DateFormat('hh:mm a').format(local);
    return sameDay ? 'till $time' : 'till $time, ${DateFormat('EEE').format(local)}';
  }
}

// ============================================================================
// Panchang screen with date navigation
// ============================================================================

class PanchangScreen extends StatefulWidget {
  final DateTime? initialDate;
  const PanchangScreen({super.key, this.initialDate});

  @override
  State<PanchangScreen> createState() => _PanchangScreenState();
}

class _PanchangScreenState extends State<PanchangScreen> {
  static const PanchangLocation _location = kDefaultPanchangLocation;

  late DateTime _selectedDate;
  DailyPanchang? _panchang;
  String? _error;

  @override
  void initState() {
    super.initState();
    final init = widget.initialDate;
    _selectedDate = init != null ? DateTime.utc(init.year, init.month, init.day) : PanchangCalculator.todayAt(_location);
    _compute();
  }

  void _compute() {
    try {
      _panchang = PanchangCalculator.cached(_selectedDate, location: _location);
      _error = null;
    } catch (e) {
      _panchang = null;
      _error = 'Could not calculate the Panchang for this date.';
    }
  }

  void _goTo(DateTime date) {
    setState(() {
      _selectedDate = DateTime.utc(date.year, date.month, date.day);
      _compute();
    });
  }

  bool get _isToday {
    final t = PanchangCalculator.todayAt(_location);
    return t.year == _selectedDate.year && t.month == _selectedDate.month && t.day == _selectedDate.day;
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime(_selectedDate.year, _selectedDate.month, _selectedDate.day),
      firstDate: DateTime(1900),
      lastDate: DateTime(2100, 12, 31),
      helpText: 'Select Panchang date',
    );
    if (!mounted || picked == null) return;
    _goTo(picked);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFCF7F1),
      appBar: AppBar(
        backgroundColor: const Color(0xFFFCF7F1),
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.black),
          tooltip: 'Back',
          onPressed: () => Navigator.maybePop(context),
        ),
        title: const Text(
          'Panchang & Muhurat',
          overflow: TextOverflow.ellipsis,
          style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 18),
        ),
        actions: [
          if (!_isToday)
            TextButton(
              onPressed: () => _goTo(PanchangCalculator.todayAt(_location)),
              child: const Text('Today', style: TextStyle(color: Color(0xFFE83D66), fontWeight: FontWeight.bold)),
            ),
          IconButton(
            tooltip: 'Pick a date',
            icon: const Icon(Icons.calendar_month_rounded, color: Colors.black),
            onPressed: _pickDate,
          ),
        ],
      ),
      body: Column(
        children: [
          _buildDateNavigator(),
          Expanded(child: _buildBody()),
        ],
      ),
    );
  }

  Widget _buildDateNavigator() {
    final label = DateFormat('EEE, d MMM yyyy').format(_selectedDate);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.grey.shade200),
        ),
        child: Row(
          children: [
            IconButton(
              tooltip: 'Previous day',
              icon: const Icon(Icons.chevron_left_rounded),
              onPressed: () => _goTo(_selectedDate.subtract(const Duration(days: 1))),
            ),
            Expanded(
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: _pickDate,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: Column(
                    children: [
                      Text(
                        label,
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: Colors.black),
                      ),
                      if (_isToday)
                        const Text('Today', style: TextStyle(fontSize: 11, color: Color(0xFFE83D66), fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
              ),
            ),
            IconButton(
              tooltip: 'Next day',
              icon: const Icon(Icons.chevron_right_rounded),
              onPressed: () => _goTo(_selectedDate.add(const Duration(days: 1))),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody() {
    final p = _panchang;
    if (p == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline_rounded, color: Colors.redAccent, size: 40),
              const SizedBox(height: 12),
              Text(_error ?? 'Something went wrong.', textAlign: TextAlign.center),
              const SizedBox(height: 12),
              ElevatedButton.icon(
                onPressed: () => setState(_compute),
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    final loc = p.location;
    final nowUtc = DateTime.now().toUtc();
    String fmtW(TimeWindow w) => PanchangCalculator.formatWindow(w, loc);
    String fmtT(DateTime t) => PanchangCalculator.formatTime(t, loc);
    String fmtEnd(PanchangElement e) => PanchangCalculator.formatEnd(e.endsAtUtc, p.civilDate, loc);

    final dayLen = p.dayLength;

    return GestureDetector(
      // Horizontal swipe to change day.
      onHorizontalDragEnd: (details) {
        final v = details.primaryVelocity ?? 0;
        if (v > 300) _goTo(_selectedDate.subtract(const Duration(days: 1)));
        if (v < -300) _goTo(_selectedDate.add(const Duration(days: 1)));
      },
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
        children: [
          // 1. Date & Location Banner
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF1E1A38), Color(0xFF2E2452)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.location_on_rounded, color: Color(0xFFFFD700), size: 18),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        '${loc.name} · IST',
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  '${p.paksha} ${p.tithi.name}',
                  style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 4),
                Text(
                  '${p.vaar} · ${p.nakshatra.name} Nakshatra · Moon in ${p.moonRashi}',
                  style: const TextStyle(color: Color(0xFFFFD700), fontSize: 12, fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),
          _sectionLabel('INAUSPICIOUS TIMINGS', Icons.warning_amber_rounded),
          const SizedBox(height: 10),

          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _timingCard('RAHU KAAL', fmtW(p.rahuKaal), 'Avoid new starts', Colors.red, Icons.access_time_filled_rounded,
                    active: _isToday && p.rahuKaal.contains(nowUtc)),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _timingCard('YAMAGANDA', fmtW(p.yamaganda), 'Avoid travel & deals', Colors.orange, Icons.timer_rounded,
                    active: _isToday && p.yamaganda.contains(nowUtc)),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _timingCard('GULIKA KAAL', fmtW(p.gulika), 'Actions repeat – avoid ending tasks', Colors.brown, Icons.hourglass_bottom_rounded,
              active: _isToday && p.gulika.contains(nowUtc)),

          const SizedBox(height: 20),
          _sectionLabel('AUSPICIOUS MUHURAT', Icons.auto_awesome_rounded),
          const SizedBox(height: 10),

          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF059669).withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: const Color(0xFF059669).withValues(alpha: 0.3)),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: const BoxDecoration(color: Color(0xFF059669), shape: BoxShape.circle),
                  child: const Icon(Icons.star_rounded, color: Colors.white, size: 20),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('ABHIJIT MUHURAT', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF047857))),
                      const SizedBox(height: 2),
                      Text(fmtW(p.abhijit), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: Colors.black)),
                      const SizedBox(height: 2),
                      Text(
                        p.vaar == 'Wednesday'
                            ? 'Traditionally not used on Wednesdays – prefer a Shubh/Labh/Amrit Choghadiya.'
                            : 'Ideal for launches, signing contracts & important tasks',
                        style: const TextStyle(fontSize: 11, color: Colors.black87),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 14),

          // Choghadiya
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.grey.shade200),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Day Choghadiya', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.black)),
                const SizedBox(height: 12),
                ...p.choghadiya.map((c) {
                  Color badgeColor = Colors.blueGrey;
                  if (c.status == 'Best' || c.status == 'Auspicious') {
                    badgeColor = const Color(0xFF059669);
                  } else if (c.status == 'Avoid') {
                    badgeColor = Colors.red;
                  }
                  final isNow = _isToday && c.window.contains(nowUtc);

                  return Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color: isNow ? badgeColor.withValues(alpha: 0.08) : const Color(0xFFFCF7F1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: isNow ? badgeColor : Colors.transparent),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                isNow ? '${c.name} (${c.meaning}) · NOW' : '${c.name} (${c.meaning})',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                              ),
                              Text(fmtW(c.window), style: const TextStyle(fontSize: 11, color: Colors.grey)),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: badgeColor.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            c.status,
                            style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: badgeColor),
                          ),
                        ),
                      ],
                    ),
                  );
                }),
              ],
            ),
          ),

          const SizedBox(height: 20),
          _sectionLabel('SUN & MOON', Icons.wb_sunny_outlined),
          const SizedBox(height: 10),

          LayoutBuilder(builder: (context, c) {
            final tileW = (c.maxWidth - 10) / 2;
            return Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                SizedBox(width: tileW, child: _celestialTile('Sunrise', fmtT(p.sunriseUtc), Icons.wb_sunny_rounded, Colors.orange)),
                SizedBox(width: tileW, child: _celestialTile('Sunset', fmtT(p.sunsetUtc), Icons.nights_stay_rounded, Colors.indigo)),
                SizedBox(
                  width: tileW,
                  child: _celestialTile('Day length', '${dayLen.inHours}h ${dayLen.inMinutes % 60}m', Icons.timelapse_rounded, Colors.teal),
                ),
                SizedBox(
                  width: tileW,
                  child: _celestialTile('Moon lit', '${p.moonIlluminationPct}%', Icons.dark_mode_rounded, Colors.purple),
                ),
              ],
            );
          }),

          const SizedBox(height: 20),
          _sectionLabel('PANCHANG – 5 LIMBS (AT SUNRISE)', Icons.menu_book_rounded),
          const SizedBox(height: 10),

          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.grey.shade200),
            ),
            child: Column(
              children: [
                _limbRow('Tithi', '${p.tithi.name} (${p.paksha.split(' ').first})', fmtEnd(p.tithi)),
                const Divider(height: 18),
                _limbRow('Vaar', p.vaar, 'sunrise to sunrise'),
                const Divider(height: 18),
                _limbRow('Nakshatra', '${p.nakshatra.name} (Pada ${p.nakshatraPada})', fmtEnd(p.nakshatra)),
                const Divider(height: 18),
                _limbRow('Yoga', p.yoga.name, fmtEnd(p.yoga)),
                const Divider(height: 18),
                _limbRow('Karana', p.karana.name, fmtEnd(p.karana)),
                const Divider(height: 18),
                _limbRow('Sun / Moon Rashi', '${p.sunRashi} / ${p.moonRashi}', 'sidereal (Lahiri)'),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Calculated on-device for sunrise at ${loc.name} using Lahiri ayanamsa. Swipe left/right to change the day.',
            style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
          ),
        ],
      ),
    );
  }

  Widget _sectionLabel(String text, IconData icon) {
    return Row(
      children: [
        Icon(icon, size: 14, color: Colors.grey),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            text,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w900, color: Colors.grey, letterSpacing: 1.0),
          ),
        ),
      ],
    );
  }

  Widget _timingCard(String title, String time, String note, Color color, IconData icon, {bool active = false}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: color.withValues(alpha: active ? 0.9 : 0.3), width: active ? 1.5 : 1),
        boxShadow: [
          BoxShadow(color: color.withValues(alpha: 0.05), blurRadius: 10, offset: const Offset(0, 4)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 16),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  active ? '$title · NOW' : title,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900, color: color),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(time, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.black)),
          const SizedBox(height: 2),
          Text(note, style: const TextStyle(fontSize: 10, color: Colors.grey)),
        ],
      ),
    );
  }

  Widget _celestialTile(String title, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: color.withValues(alpha: 0.12), shape: BoxShape.circle),
            child: Icon(icon, color: color, size: 18),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11, color: Colors.grey, fontWeight: FontWeight.bold)),
                Text(value, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.black)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _limbRow(String title, String value, String sub) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 96,
          child: Text(title, style: TextStyle(fontSize: 13, color: Colors.grey.shade700, fontWeight: FontWeight.w600)),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(value, textAlign: TextAlign.end, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.black)),
              Text(sub, textAlign: TextAlign.end, style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
            ],
          ),
        ),
      ],
    );
  }
}
