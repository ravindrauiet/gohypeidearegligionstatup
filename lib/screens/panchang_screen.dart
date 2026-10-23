import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart' show DateFormat;

import '../widgets/ui/app_ui.dart';

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
// Panchang screen: daily almanac with date navigation
// ============================================================================

class PanchangScreen extends StatefulWidget {
  final DateTime? initialDate;
  const PanchangScreen({super.key, this.initialDate});

  @override
  State<PanchangScreen> createState() => _PanchangScreenState();
}

enum _Tone { good, bad, neutral }

class _TimelineEntry {
  final String title;
  final String time;
  final String note;
  final IconData icon;
  final _Tone tone;
  final DateTime sortKey;
  final bool active;

  const _TimelineEntry(this.title, this.time, this.note, this.icon, this.tone, this.sortKey, {this.active = false});
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

  bool _sameDay(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;

  bool get _isToday => _sameDay(PanchangCalculator.todayAt(_location), _selectedDate);

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
      backgroundColor: AppColors.background,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          tooltip: 'Back',
          onPressed: () => Navigator.maybePop(context),
        ),
        title: const Text('Panchang & Muhurat', overflow: TextOverflow.ellipsis),
        actions: [
          if (!_isToday)
            TextButton(
              onPressed: () => _goTo(PanchangCalculator.todayAt(_location)),
              child: const Text('Today'),
            ),
          IconButton(
            tooltip: 'Pick a date',
            icon: const Icon(Icons.calendar_month_rounded),
            onPressed: _pickDate,
          ),
          const SizedBox(width: AppSpacing.xxs),
        ],
      ),
      body: Column(
        children: [
          _buildDateSwitcher(),
          Expanded(child: _buildBody()),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------- date switcher
  Widget _buildDateSwitcher() {
    final today = PanchangCalculator.todayAt(_location);
    final days = List.generate(7, (i) => _selectedDate.add(Duration(days: i - 3)));
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      padding: const EdgeInsets.fromLTRB(AppSpacing.page, 0, AppSpacing.xs, AppSpacing.sm),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Semantics(
                  button: true,
                  label: 'Selected date ${DateFormat('EEEE d MMMM yyyy').format(_selectedDate)}. Tap to pick a date',
                  excludeSemantics: true,
                  child: InkWell(
                    onTap: _pickDate,
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(minHeight: 44),
                      child: Row(
                        children: [
                          Flexible(
                            child: Text(
                              DateFormat('EEEE, d MMM yyyy').format(_selectedDate),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppText.subtitle,
                            ),
                          ),
                          const Icon(Icons.keyboard_arrow_down_rounded, color: AppColors.textSecondary),
                          if (_isToday) ...[
                            const SizedBox(width: AppSpacing.xxs),
                            const AppBadge(label: 'Today', color: AppColors.success),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Previous day',
                icon: const Icon(Icons.chevron_left_rounded),
                onPressed: () => _goTo(_selectedDate.subtract(const Duration(days: 1))),
              ),
              IconButton(
                tooltip: 'Next day',
                icon: const Icon(Icons.chevron_right_rounded),
                onPressed: () => _goTo(_selectedDate.add(const Duration(days: 1))),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xxs),
          Padding(
            padding: const EdgeInsets.only(right: AppSpacing.xs),
            child: Row(
              children: [
                for (final d in days)
                  Expanded(
                    child: _dayCell(d, selected: _sameDay(d, _selectedDate), isToday: _sameDay(d, today)),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _dayCell(DateTime d, {required bool selected, required bool isToday}) {
    final fg = selected ? Colors.white : AppColors.textPrimary;
    return Semantics(
      button: true,
      selected: selected,
      label: DateFormat('EEEE d MMMM').format(d),
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2),
        child: Material(
          color: selected ? AppColors.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(AppRadius.md),
          child: InkWell(
            borderRadius: BorderRadius.circular(AppRadius.md),
            onTap: () => _goTo(d),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    DateFormat('EEE').format(d),
                    maxLines: 1,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: selected ? Colors.white.withValues(alpha: 0.85) : AppColors.textTertiary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${d.day}',
                    maxLines: 1,
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: fg),
                  ),
                  const SizedBox(height: 3),
                  Container(
                    width: 4,
                    height: 4,
                    decoration: BoxDecoration(
                      color: isToday ? (selected ? Colors.white : AppColors.primary) : Colors.transparent,
                      shape: BoxShape.circle,
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

  // ---------------------------------------------------------------- body
  Widget _buildBody() {
    final p = _panchang;
    if (p == null) {
      return Center(
        child: SingleChildScrollView(
          child: AppStateView.error(
            title: 'Panchang unavailable',
            message: _error ?? 'Something went wrong.',
            onAction: () => setState(_compute),
          ),
        ),
      );
    }

    final loc = p.location;
    final nowUtc = DateTime.now().toUtc();
    String fmtW(TimeWindow w) => PanchangCalculator.formatWindow(w, loc);
    String fmtT(DateTime t) => PanchangCalculator.formatTime(t, loc);
    String fmtEnd(PanchangElement e) => PanchangCalculator.formatEnd(e.endsAtUtc, p.civilDate, loc);
    bool live(TimeWindow w) => _isToday && w.contains(nowUtc);

    final dayLen = p.dayLength;

    final timeline = <_TimelineEntry>[
      _TimelineEntry('Sunrise', fmtT(p.sunriseUtc), 'The Vedic day begins', Icons.wb_twilight_rounded, _Tone.neutral, p.sunriseUtc),
      _TimelineEntry(
        'Abhijit Muhurat',
        fmtW(p.abhijit),
        p.vaar == 'Wednesday'
            ? 'Traditionally not used on Wednesdays – prefer a Shubh/Labh/Amrit Choghadiya.'
            : 'Best window for launches, signing contracts & important tasks',
        Icons.star_rounded,
        _Tone.good,
        p.abhijit.startUtc,
        active: live(p.abhijit),
      ),
      _TimelineEntry('Rahu Kaal', fmtW(p.rahuKaal), 'Avoid starting anything new', Icons.do_not_disturb_on_rounded, _Tone.bad,
          p.rahuKaal.startUtc,
          active: live(p.rahuKaal)),
      _TimelineEntry('Yamaganda', fmtW(p.yamaganda), 'Avoid travel & deals', Icons.timer_off_rounded, _Tone.bad, p.yamaganda.startUtc,
          active: live(p.yamaganda)),
      _TimelineEntry('Gulika Kaal', fmtW(p.gulika), 'Actions tend to repeat – avoid ending tasks', Icons.hourglass_bottom_rounded,
          _Tone.bad, p.gulika.startUtc,
          active: live(p.gulika)),
      _TimelineEntry('Sunset', fmtT(p.sunsetUtc), 'Day length ${dayLen.inHours}h ${dayLen.inMinutes % 60}m',
          Icons.nights_stay_rounded, _Tone.neutral, p.sunsetUtc),
    ]..sort((a, b) => a.sortKey.compareTo(b.sortKey));

    const headerPad = EdgeInsets.fromLTRB(0, AppSpacing.xl, 0, AppSpacing.sm);

    return GestureDetector(
      // Horizontal swipe to change day.
      onHorizontalDragEnd: (details) {
        final v = details.primaryVelocity ?? 0;
        if (v > 300) _goTo(_selectedDate.subtract(const Duration(days: 1)));
        if (v < -300) _goTo(_selectedDate.add(const Duration(days: 1)));
      },
      child: ListView(
        padding: const EdgeInsets.fromLTRB(AppSpacing.page, AppSpacing.md, AppSpacing.page, AppSpacing.xxl),
        children: [
          _summaryCard(p, fmtT),
          const SectionHeader(
            title: 'Timings of the day',
            subtitle: 'Green windows are good for new work; red ones are best avoided.',
            padding: headerPad,
          ),
          AppCard(
            padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.xs, AppSpacing.md, AppSpacing.xs),
            child: Column(
              children: [
                for (int i = 0; i < timeline.length; i++)
                  _timelineRow(timeline[i], first: i == 0, last: i == timeline.length - 1),
              ],
            ),
          ),
          const SectionHeader(
            title: 'Day Choghadiya',
            subtitle: 'Eight slots from sunrise to sunset. Amrit, Shubh and Labh are favourable.',
            padding: headerPad,
          ),
          AppCard(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.xxs),
            child: Column(
              children: [
                for (int i = 0; i < p.choghadiya.length; i++) ...[
                  if (i > 0) const Divider(height: 1),
                  _choghadiyaRow(p.choghadiya[i], fmtW(p.choghadiya[i].window), live(p.choghadiya[i].window)),
                ],
              ],
            ),
          ),
          const SectionHeader(
            title: 'Five limbs (Panchang)',
            subtitle: 'The day’s tithi, nakshatra, yoga and karana, as they stand at sunrise.',
            padding: headerPad,
          ),
          _grid([
            _limbTile('Tithi', '${p.tithi.name} (${p.paksha.split(' ').first})', fmtEnd(p.tithi), Icons.brightness_3_rounded),
            _limbTile('Nakshatra', '${p.nakshatra.name} (Pada ${p.nakshatraPada})', fmtEnd(p.nakshatra), Icons.star_outline_rounded),
            _limbTile('Yoga', p.yoga.name, fmtEnd(p.yoga), Icons.join_inner_rounded),
            _limbTile('Karana', p.karana.name, fmtEnd(p.karana), Icons.timelapse_rounded),
            _limbTile('Vaar', p.vaar, 'sunrise to sunrise', Icons.calendar_today_rounded),
            _limbTile('Sun / Moon rashi', '${p.sunRashi} / ${p.moonRashi}', 'sidereal (Lahiri)', Icons.public_rounded),
            _limbTile('Day length', '${dayLen.inHours}h ${dayLen.inMinutes % 60}m', '${fmtT(p.sunriseUtc)} – ${fmtT(p.sunsetUtc)}',
                Icons.wb_sunny_outlined),
            _limbTile('Moon lit', '${p.moonIlluminationPct}%', p.paksha, Icons.dark_mode_outlined),
          ]),
          const SizedBox(height: AppSpacing.md),
          Text(
            'Calculated on-device for sunrise at ${loc.name} using Lahiri ayanamsa. Swipe left or right to change the day.',
            style: AppText.caption,
          ),
        ],
      ),
    );
  }

  Widget _summaryCard(DailyPanchang p, String Function(DateTime) fmtT) {
    Widget sun(IconData icon, String label, String value) => Expanded(
          child: Row(
            children: [
              Icon(icon, color: AppColors.gold, size: 20),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label, style: AppText.caption.copyWith(color: AppColors.textOnDarkMuted)),
                    Text(value,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppText.bodyStrong.copyWith(color: AppColors.textOnDark)),
                  ],
                ),
              ),
            ],
          ),
        );

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md + 2),
      decoration: BoxDecoration(gradient: AppColors.cosmicGradient, borderRadius: AppRadius.card),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.location_on_outlined, color: AppColors.textOnDarkMuted, size: 16),
              const SizedBox(width: AppSpacing.xxs),
              Expanded(
                child: Text(
                  '${p.location.name} · IST',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.caption.copyWith(color: AppColors.textOnDarkMuted),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Text('${p.paksha} ${p.tithi.name}', style: AppText.headline.copyWith(color: AppColors.textOnDark)),
          const SizedBox(height: AppSpacing.xxs),
          Text(
            '${p.vaar} · ${p.nakshatra.name} Nakshatra · Moon in ${p.moonRashi}',
            style: AppText.body.copyWith(color: AppColors.textOnDarkMuted),
          ),
          const SizedBox(height: AppSpacing.md),
          Container(height: 1, color: Colors.white.withValues(alpha: 0.12)),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              sun(Icons.wb_twilight_rounded, 'Sunrise', fmtT(p.sunriseUtc)),
              const SizedBox(width: AppSpacing.sm),
              sun(Icons.nights_stay_outlined, 'Sunset', fmtT(p.sunsetUtc)),
            ],
          ),
        ],
      ),
    );
  }

  (Color, Color, String) _toneStyle(_Tone t) => switch (t) {
        _Tone.good => (AppColors.success, AppColors.successSoft, 'Good'),
        _Tone.bad => (AppColors.danger, AppColors.dangerSoft, 'Avoid'),
        _Tone.neutral => (AppColors.textSecondary, AppColors.surfaceMuted, ''),
      };

  Widget _timelineRow(_TimelineEntry e, {required bool first, required bool last}) {
    final (color, soft, label) = _toneStyle(e.tone);
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Rail
          SizedBox(
            width: 36,
            child: Column(
              children: [
                Expanded(child: Container(width: 1.5, color: first ? Colors.transparent : AppColors.border)),
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(color: soft, shape: BoxShape.circle),
                  child: Icon(e.icon, size: 17, color: color),
                ),
                Expanded(child: Container(width: 1.5, color: last ? Colors.transparent : AppColors.border)),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(e.title, style: AppText.bodyStrong),
                      if (label.isNotEmpty) AppBadge(label: label, color: color),
                      if (e.active) AppBadge(label: 'Now', color: Colors.white, background: color),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(e.time,
                      style: AppText.bodyStrong.copyWith(
                          fontSize: 15, color: e.tone == _Tone.neutral ? AppColors.textPrimary : color)),
                  Text(e.note, style: AppText.caption.copyWith(color: AppColors.textSecondary)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _choghadiyaRow(ChoghadiyaSlot c, String window, bool isNow) {
    final good = c.status == 'Best' || c.status == 'Auspicious';
    final bad = c.status == 'Avoid';
    final color = good ? AppColors.success : (bad ? AppColors.danger : AppColors.textSecondary);
    final row = Padding(
      padding: EdgeInsets.symmetric(vertical: 12, horizontal: isNow ? AppSpacing.xs : 0),
      child: Row(
        children: [
          Container(width: 4, height: 32, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2))),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${c.name} · ${c.meaning}', maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.bodyStrong),
                Text(window, style: AppText.caption.copyWith(color: AppColors.textSecondary)),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.xs),
          if (isNow) ...[
            AppBadge(label: 'Now', color: Colors.white, background: color),
            const SizedBox(width: 4),
          ],
          AppBadge(label: c.status, color: color),
        ],
      ),
    );
    if (!isNow) return row;
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 2),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(AppRadius.sm)),
      child: row,
    );
  }

  /// Two-column grid with equal-height rows.
  Widget _grid(List<Widget> tiles) {
    final rows = <Widget>[];
    for (int i = 0; i < tiles.length; i += 2) {
      if (i > 0) rows.add(const SizedBox(height: AppSpacing.sm));
      rows.add(IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(child: tiles[i]),
            const SizedBox(width: AppSpacing.sm),
            Expanded(child: i + 1 < tiles.length ? tiles[i + 1] : const SizedBox.shrink()),
          ],
        ),
      ));
    }
    return Column(children: rows);
  }

  Widget _limbTile(String title, String value, String sub, IconData icon) {
    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: AppColors.primary),
              const SizedBox(width: 6),
              Expanded(
                child: Text(title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.caption.copyWith(color: AppColors.textSecondary)),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(value, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppText.bodyStrong),
          const SizedBox(height: 2),
          Text(sub, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppText.caption),
        ],
      ),
    );
  }
}
