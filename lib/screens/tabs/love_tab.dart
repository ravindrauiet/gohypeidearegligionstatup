import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../services/backend_service.dart';
import '../../services/city_autocomplete_service.dart';
import '../../utils/app_routes.dart';
import '../../widgets/ui/app_ui.dart';

// =============================================================================
// Ashtakoot (36-point) Guna Milan engine
// Computed deterministically from each person's Moon sign + Moon nakshatra (+pada).
// =============================================================================

const List<String> _kSigns = [
  'Aries', 'Taurus', 'Gemini', 'Cancer', 'Leo', 'Virgo', //
  'Libra', 'Scorpio', 'Sagittarius', 'Capricorn', 'Aquarius', 'Pisces',
];

const List<String> _kNakshatras = [
  'Ashwini', 'Bharani', 'Krittika', 'Rohini', 'Mrigashira', 'Ardra', 'Punarvasu', //
  'Pushya', 'Ashlesha', 'Magha', 'Purva Phalguni', 'Uttara Phalguni', 'Hasta', 'Chitra',
  'Swati', 'Vishakha', 'Anuradha', 'Jyeshtha', 'Moola', 'Purva Ashadha', 'Uttara Ashadha',
  'Shravana', 'Dhanishta', 'Shatabhisha', 'Purva Bhadrapada', 'Uttara Bhadrapada', 'Revati',
];

const Map<String, int> _kNakshatraAliases = {
  'ashwini': 0, 'ashvini': 0, 'aswini': 0, 'asvini': 0,
  'bharani': 1,
  'krittika': 2, 'kritika': 2, 'krithika': 2, 'kruthika': 2,
  'rohini': 3,
  'mrigashira': 4, 'mrigashirsha': 4, 'mrigasira': 4, 'mrigshira': 4, 'mrigasirsha': 4,
  'ardra': 5, 'aridra': 5, 'arudra': 5, 'aardra': 5,
  'punarvasu': 6, 'punarpoosam': 6,
  'pushya': 7, 'pushyami': 7, 'pooyam': 7, 'pusya': 7,
  'ashlesha': 8, 'aslesha': 8, 'ashlesa': 8, 'ayilyam': 8,
  'magha': 9, 'makha': 9, 'magam': 9,
  'purvaphalguni': 10, 'poorvaphalguni': 10, 'purvaphalgun': 10, 'pubba': 10,
  'uttaraphalguni': 11, 'uttaraphalgun': 11, 'uttraphalguni': 11, 'uttara': 11,
  'hasta': 12, 'hastha': 12,
  'chitra': 13, 'chithra': 13, 'chitta': 13,
  'swati': 14, 'svati': 14, 'swathi': 14,
  'vishakha': 15, 'visakha': 15, 'vishaka': 15, 'vishakam': 15,
  'anuradha': 16, 'anusham': 16,
  'jyeshtha': 17, 'jyeshta': 17, 'jyestha': 17, 'jyesta': 17,
  'moola': 18, 'mula': 18, 'moolam': 18,
  'purvaashadha': 19, 'purvashadha': 19, 'poorvashadha': 19, 'poorvaashadha': 19, 'purvasadha': 19,
  'uttaraashadha': 20, 'uttarashadha': 20, 'uttarasadha': 20, 'uthradam': 20,
  'shravana': 21, 'sravana': 21, 'shravan': 21, 'thiruvonam': 21,
  'dhanishta': 22, 'dhanishtha': 22, 'dhanista': 22, 'shravishtha': 22,
  'shatabhisha': 23, 'shatabhishak': 23, 'satabhisha': 23, 'shatbhisha': 23, 'sadayam': 23,
  'purvabhadrapada': 24, 'purvabhadra': 24, 'poorvabhadrapada': 24, 'purvabhadrapad': 24,
  'uttarabhadrapada': 25, 'uttarabhadra': 25, 'uttarabhadrapad': 25, 'uthrattathi': 25,
  'revati': 26, 'revathi': 26,
};

const Map<String, int> _kSignAliases = {
  'aries': 0, 'mesha': 0, 'mesh': 0,
  'taurus': 1, 'vrishabha': 1, 'vrishabh': 1, 'vrish': 1,
  'gemini': 2, 'mithuna': 2, 'mithun': 2,
  'cancer': 3, 'karka': 3, 'kark': 3, 'karkata': 3,
  'leo': 4, 'simha': 4, 'singh': 4,
  'virgo': 5, 'kanya': 5,
  'libra': 6, 'tula': 6,
  'scorpio': 7, 'vrishchika': 7, 'vrischika': 7, 'vrishchik': 7,
  'sagittarius': 8, 'dhanu': 8, 'dhanus': 8,
  'capricorn': 9, 'makara': 9, 'makar': 9,
  'aquarius': 10, 'kumbha': 10, 'kumbh': 10,
  'pisces': 11, 'meena': 11, 'meen': 11,
};

String _normKey(String s) => s.toLowerCase().replaceAll(RegExp(r'[^a-z]'), '');

int? _signIndex(dynamic raw) {
  if (raw == null) return null;
  return _kSignAliases[_normKey(raw.toString())];
}

int? _nakshatraIndex(dynamic raw) {
  if (raw == null) return null;
  return _kNakshatraAliases[_normKey(raw.toString())];
}

List<Map<String, dynamic>> _planetList(dynamic raw) {
  dynamic v = raw;
  if (v is String && v.isNotEmpty) {
    try {
      v = jsonDecode(v);
    } catch (_) {
      return const [];
    }
  }
  if (v is List) {
    return v.whereType<Map>().map((m) => Map<String, dynamic>.from(m)).toList();
  }
  return const [];
}

/// Minimal astro profile needed for Guna Milan.
class _MoonProfile {
  final String name;
  final int moonSign; // 0..11
  final int nakshatra; // 0..26
  final int? pada; // 1..4
  final int? marsHouse;
  final Map<String, int> planetSigns; // Sun / Moon / Venus / Mars -> sign index

  _MoonProfile({
    required this.name,
    required this.moonSign,
    required this.nakshatra,
    this.pada,
    this.marsHouse,
    this.planetSigns = const {},
  });

  /// Builds a profile from a backend kundli map (user or family member). Returns null
  /// when the Moon sign / nakshatra are missing or unrecognised.
  static _MoonProfile? fromKundli(String name, Map? kundli) {
    if (kundli == null) return null;
    final sign = _signIndex(kundli['moonSign'] ?? kundli['moon_sign']);
    final nak = _nakshatraIndex(kundli['nakshatra']);
    if (sign == null || nak == null) return null;
    final pada = int.tryParse((kundli['nakshatraPada'] ?? kundli['nakshatra_pada'])?.toString() ?? '');

    final planets = _planetList(kundli['planetaryPositions'] ?? kundli['planetary_positions']);
    final signs = <String, int>{};
    int? marsHouse;
    for (final p in planets) {
      final pname = p['name']?.toString().toLowerCase() ?? '';
      final s = _signIndex(p['sign']);
      for (final key in const ['sun', 'moon', 'venus', 'mars']) {
        if (pname.startsWith(key) && s != null) signs[key] = s;
      }
      if (pname.startsWith('mars')) marsHouse = int.tryParse(p['house']?.toString() ?? '');
    }
    signs['moon'] = sign;
    final sunSign = _signIndex(kundli['sunSign'] ?? kundli['sun_sign']);
    if (sunSign != null) signs.putIfAbsent('sun', () => sunSign);

    return _MoonProfile(
      name: name,
      moonSign: sign,
      nakshatra: nak,
      pada: (pada != null && pada >= 1 && pada <= 4) ? pada : null,
      marsHouse: marsHouse,
      planetSigns: signs,
    );
  }

  /// Approximate degree of the Moon inside its sign (used for Vashya of Sagittarius /
  /// Capricorn which change category at 15°).
  double get degreeInSign {
    const nakSpan = 360 / 27;
    const padaSpan = nakSpan / 4;
    final start = nakshatra * nakSpan;
    final lon = pada != null ? start + (pada! - 0.5) * padaSpan : start + nakSpan / 2;
    final d = lon - moonSign * 30;
    return (d >= 0 && d < 30) ? d : 15;
  }
}

class _Koota {
  final String name;
  final double score;
  final int max;
  final String meaning;
  final String verdict;
  const _Koota(this.name, this.score, this.max, this.meaning, this.verdict);
}

class _AshtakootEngine {
  // Varna rank by Moon sign: Brahmin 4, Kshatriya 3, Vaishya 2, Shudra 1.
  static const List<int> _varnaRank = [3, 2, 1, 4, 3, 2, 1, 4, 3, 2, 1, 4];
  static const List<String> _varnaName = ['', 'Shudra', 'Vaishya', 'Kshatriya', 'Brahmin'];

  // Vashya groups: 0 Chatushpada, 1 Manava, 2 Jalachara, 3 Vanachara, 4 Keeta.
  static const List<String> _vashyaName = ['Chatushpada', 'Manava', 'Jalachara', 'Vanachara', 'Keeta'];
  static const List<List<double>> _vashyaTable = [
    [2, 1, 1, 0.5, 1],
    [1, 2, 0.5, 0, 1],
    [1, 0.5, 2, 1, 1],
    [0.5, 0, 1, 2, 0],
    [1, 1, 1, 0, 2],
  ];

  static int _vashyaGroup(_MoonProfile p) {
    switch (p.moonSign) {
      case 0:
      case 1:
        return 0;
      case 2:
      case 5:
      case 6:
      case 10:
        return 1;
      case 3:
      case 11:
        return 2;
      case 4:
        return 3;
      case 7:
        return 4;
      case 8:
        return p.degreeInSign < 15 ? 1 : 0;
      case 9:
        return p.degreeInSign < 15 ? 0 : 2;
    }
    return 1;
  }

  // Yoni per nakshatra (index into _yoniName).
  static const List<String> _yoniName = [
    'Horse', 'Elephant', 'Sheep', 'Serpent', 'Dog', 'Cat', 'Rat', //
    'Cow', 'Buffalo', 'Tiger', 'Deer', 'Monkey', 'Mongoose', 'Lion',
  ];
  static const List<int> _nakYoni = [0, 1, 2, 3, 3, 4, 5, 2, 5, 6, 6, 7, 8, 9, 8, 9, 10, 10, 4, 11, 12, 11, 13, 0, 13, 7, 1];
  static const List<List<int>> _yoniTable = [
    [4, 2, 2, 3, 2, 2, 2, 1, 0, 1, 3, 3, 2, 1],
    [2, 4, 3, 3, 2, 2, 2, 2, 3, 1, 2, 3, 2, 0],
    [2, 3, 4, 2, 1, 2, 1, 3, 3, 1, 2, 0, 3, 1],
    [3, 3, 2, 4, 2, 1, 1, 1, 1, 2, 2, 2, 0, 2],
    [2, 2, 1, 2, 4, 2, 1, 2, 2, 1, 0, 2, 1, 1],
    [2, 2, 2, 1, 2, 4, 0, 2, 2, 1, 3, 3, 2, 1],
    [2, 2, 1, 1, 1, 0, 4, 2, 2, 2, 2, 2, 1, 2],
    [1, 2, 3, 1, 2, 2, 2, 4, 3, 0, 3, 2, 2, 1],
    [0, 3, 3, 1, 2, 2, 2, 3, 4, 1, 2, 2, 2, 1],
    [1, 1, 1, 2, 1, 1, 2, 0, 1, 4, 1, 1, 2, 1],
    [3, 2, 2, 2, 0, 3, 2, 3, 2, 1, 4, 2, 2, 1],
    [3, 3, 0, 2, 2, 3, 2, 2, 2, 1, 2, 4, 3, 2],
    [2, 2, 3, 0, 1, 2, 1, 2, 2, 2, 2, 3, 4, 2],
    [1, 0, 1, 2, 1, 1, 2, 1, 1, 1, 1, 2, 2, 4],
  ];

  // Sign lords: 0 Sun, 1 Moon, 2 Mars, 3 Mercury, 4 Jupiter, 5 Venus, 6 Saturn.
  static const List<String> _planetName = ['Sun', 'Moon', 'Mars', 'Mercury', 'Jupiter', 'Venus', 'Saturn'];
  static const List<int> _signLord = [2, 5, 3, 1, 0, 3, 5, 2, 4, 6, 6, 4];
  // Natural relationship of row planet towards column planet: 1 friend, 0 neutral, -1 enemy.
  static const List<List<int>> _relation = [
    [1, 1, 1, 0, 1, -1, -1], // Sun
    [1, 1, 0, 1, 0, 0, 0], // Moon
    [1, 1, 1, -1, 1, 0, 0], // Mars
    [1, -1, 0, 1, 0, 1, 0], // Mercury
    [1, 1, 1, -1, 1, -1, 0], // Jupiter
    [-1, -1, 0, 1, 0, 1, 1], // Venus
    [-1, -1, -1, 1, 0, 1, 1], // Saturn
  ];

  // Gana per nakshatra: 0 Deva, 1 Manushya, 2 Rakshasa.
  static const List<String> _ganaName = ['Deva', 'Manushya', 'Rakshasa'];
  static const List<int> _nakGana = [0, 1, 2, 1, 0, 1, 0, 0, 2, 2, 1, 1, 0, 2, 0, 2, 0, 2, 2, 1, 1, 0, 2, 2, 1, 1, 0];
  // Rows: boy's gana, columns: girl's gana.
  static const List<List<double>> _ganaTable = [
    [6, 6, 1],
    [5, 6, 0],
    [1, 0, 6],
  ];

  // Nadi per nakshatra: 0 Adi, 1 Madhya, 2 Antya.
  static const List<String> _nadiName = ['Adi (Vata)', 'Madhya (Pitta)', 'Antya (Kapha)'];
  static const List<int> _nakNadi = [0, 1, 2, 2, 1, 0, 0, 1, 2, 2, 1, 0, 0, 1, 2, 2, 1, 0, 0, 1, 2, 2, 1, 0, 0, 1, 2];

  static List<_Koota> compute(_MoonProfile boy, _MoonProfile girl) {
    final result = <_Koota>[];

    // 1. Varna (1)
    final vb = _varnaRank[boy.moonSign], vg = _varnaRank[girl.moonSign];
    final varna = vb >= vg ? 1.0 : 0.0;
    result.add(_Koota('Varna', varna, 1, 'Work & Ego Alignment',
        '${_varnaName[vb]} (boy) · ${_varnaName[vg]} (girl)${varna == 1 ? ' — compatible' : ' — mismatch'}'));

    // 2. Vashya (2)
    final gb = _vashyaGroup(boy), gg = _vashyaGroup(girl);
    final vashya = _vashyaTable[gb][gg];
    result.add(_Koota('Vashya', vashya, 2, 'Mutual Influence & Control', '${_vashyaName[gb]} · ${_vashyaName[gg]}'));

    // 3. Tara (3) — counted both ways; 3rd, 5th, 7th taras are inauspicious.
    bool good(int from, int to) {
      final count = ((to - from + 27) % 27) + 1;
      final tara = count % 9;
      return !(tara == 3 || tara == 5 || tara == 7);
    }

    final t1 = good(girl.nakshatra, boy.nakshatra), t2 = good(boy.nakshatra, girl.nakshatra);
    final tara = (t1 ? 1.5 : 0) + (t2 ? 1.5 : 0);
    result.add(_Koota('Tara', tara.toDouble(), 3, 'Destiny & Astral Luck',
        t1 && t2 ? 'Auspicious both ways' : (t1 || t2 ? 'Auspicious one way' : 'Inauspicious Tara')));

    // 4. Yoni (4)
    final yb = _nakYoni[boy.nakshatra], yg = _nakYoni[girl.nakshatra];
    final yoni = _yoniTable[yb][yg].toDouble();
    result.add(_Koota('Yoni', yoni, 4, 'Physical & Intimate Affinity',
        '${_yoniName[yb]} · ${_yoniName[yg]}${yoni == 0 ? ' — sworn enemies (Yoni Dosha)' : ''}'));

    // 5. Graha Maitri (5)
    final lb = _signLord[boy.moonSign], lg = _signLord[girl.moonSign];
    double maitri;
    if (lb == lg) {
      maitri = 5;
    } else {
      final a = _relation[lb][lg], b = _relation[lg][lb];
      final sum = a + b;
      if (a == 1 && b == 1) {
        maitri = 5;
      } else if (sum == 1) {
        maitri = 4; // friend + neutral
      } else if (a == 0 && b == 0) {
        maitri = 3;
      } else if (sum == 0) {
        maitri = 1; // friend + enemy
      } else if (sum == -1) {
        maitri = 0.5; // neutral + enemy
      } else {
        maitri = 0;
      }
    }
    result.add(_Koota('Graha Maitri', maitri, 5, 'Mental Compatibility',
        'Moon-sign lords ${_planetName[lb]} · ${_planetName[lg]}'));

    // 6. Gana (6)
    final ganaB = _nakGana[boy.nakshatra], ganaG = _nakGana[girl.nakshatra];
    final gana = _ganaTable[ganaB][ganaG];
    result.add(_Koota('Gana', gana, 6, 'Behaviour & Temperament', '${_ganaName[ganaB]} · ${_ganaName[ganaG]}'));

    // 7. Bhakoot (7) — counted from girl's Moon sign to boy's.
    final dist = ((boy.moonSign - girl.moonSign + 12) % 12) + 1;
    final reverse = ((girl.moonSign - boy.moonSign + 12) % 12) + 1;
    const badDistances = {2, 12, 5, 9, 6, 8};
    final bhakoot = badDistances.contains(dist) ? 0.0 : 7.0;
    result.add(_Koota('Bhakoot', bhakoot, 7, 'Emotional & Financial Growth',
        bhakoot == 0 ? '$dist/$reverse axis — Bhakoot Dosha' : '$dist/$reverse axis — no Bhakoot Dosha'));

    // 8. Nadi (8)
    final nb = _nakNadi[boy.nakshatra], ng = _nakNadi[girl.nakshatra];
    final nadi = nb == ng ? 0.0 : 8.0;
    result.add(_Koota('Nadi', nadi, 8, 'Genetics, Health & Progeny',
        nb == ng ? 'Both ${_nadiName[nb]} — Nadi Dosha' : '${_nadiName[nb]} · ${_nadiName[ng]}'));

    return result;
  }

  static String nadiName(int nakshatra) => _nadiName[_nakNadi[nakshatra]];
}

String _fmtScore(num v) => v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(1);

/// Partner details captured by the partner sheet or picked from saved family profiles.
class PartnerInfo {
  final String name;
  final String gender;
  final String dob;
  final String tob;
  final String pob;
  final Map<String, dynamic>? kundli;
  final String? familyId;
  /// Birth-place coordinates (the backend derives the birth timezone from them).
  final double? latitude;
  final double? longitude;

  const PartnerInfo({
    required this.name,
    required this.gender,
    required this.dob,
    required this.tob,
    required this.pob,
    this.kundli,
    this.familyId,
    this.latitude,
    this.longitude,
  });
}

double? _toCoord(dynamic v) => v is num ? v.toDouble() : double.tryParse(v?.toString() ?? '');

DateTime? _parseDate(dynamic raw) {
  final s = raw?.toString() ?? '';
  if (s.isEmpty) return null;
  final d = DateTime.tryParse(s);
  if (d == null) return null;
  return s.contains('T') ? d.toLocal() : d;
}

String _isoDate(dynamic raw) {
  final d = _parseDate(raw);
  return d == null ? (raw?.toString() ?? '') : DateFormat('yyyy-MM-dd').format(d);
}


/// Plain-English one-liners for each Koota, shown under its score bar.
const Map<String, String> _kKootaPlain = {
  'varna': 'How your values and approach to work line up.',
  'vashya': 'How naturally you influence and support each other.',
  'tara': 'Shared luck and good timing through life.',
  'yoni': 'Physical closeness and the way you show affection.',
  'graha maitri': 'How easily your minds and moods connect.',
  'grahamaitri': 'How easily your minds and moods connect.',
  'gana': 'Temperament and day-to-day nature.',
  'bhakoot': 'Emotional bond and money matters as a family.',
  'nadi': 'Health and children; traditionally the most important area.',
};

double _num(dynamic v, [double fallback = 0]) =>
    v is num ? v.toDouble() : (double.tryParse(v?.toString() ?? '') ?? fallback);

/// One-word verdict on the traditional 36-point scale.
(String, Color) _verdictFor(double total) {
  if (total >= 33) return ('Excellent', AppColors.success);
  if (total >= 25) return ('Good', AppColors.success);
  if (total >= 18) return ('Average', AppColors.warning);
  return ('Challenging', AppColors.danger);
}

Color _barColor(double pct) {
  if (pct >= 0.75) return AppColors.success;
  if (pct >= 0.4) return AppColors.warning;
  return AppColors.danger;
}

class LoveTab extends StatefulWidget {
  const LoveTab({super.key});

  @override
  State<LoveTab> createState() => _LoveTabState();
}

class _LoveTabState extends State<LoveTab> {
  PartnerInfo? _partner;

  bool _isMatching = false;
  String? _matchError;
  /// The match failed because the user has no Kundli yet.
  bool _matchNeedsBirthDetails = false;
  Map<String, dynamic>? _synastryData;

  /// True when the result was computed locally from both real Moon charts; false when
  /// it is the backend's AI estimate (partner chart unavailable).
  bool _isExactCalculation = false;
  bool _showDeepAstroAnalysis = false;

  /// Saved-profiles list state (first load only; later refreshes keep the cached list).
  bool _familyLoading = false;
  bool _familyLoadFailed = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final s = Provider.of<BackendService>(context, listen: false);
      if (s.isAuthenticated && s.familyMembers.isEmpty) _loadFamily();
    });
  }

  Future<void> _loadFamily() async {
    final s = Provider.of<BackendService>(context, listen: false);
    setState(() {
      _familyLoading = true;
      _familyLoadFailed = false;
    });
    final res = await s.fetchFamilyKundlis();
    if (!mounted) return;
    setState(() {
      _familyLoading = false;
      _familyLoadFailed = res == null;
    });
  }

  String _userName(BackendService s) {
    final k = s.kundliData;
    return k?['birthDetails']?['fullName']?.toString() ?? s.user?['fullName']?.toString() ?? 'You';
  }

  String? _userGender(BackendService s) {
    return (s.user?['gender'] ?? s.kundliData?['birthDetails']?['gender'])?.toString();
  }

  @override
  Widget build(BuildContext context) {
    final backendService = Provider.of<BackendService>(context);
    final familyMembers = backendService.familyMembers;
    final kundli = backendService.kundliData;
    final userName = _userName(backendService);
    final userMoon = kundli?['moonSign']?.toString();
    final partner = _partner;
    final partnerName = partner?.name ?? 'Partner';

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: const Text('Love & Matching'),
        actions: [
          IconButton(
            tooltip: 'About Guna Milan',
            icon: const Icon(Icons.info_outline_rounded),
            onPressed: () => _showInfoDialog(context),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(AppSpacing.page, AppSpacing.md, AppSpacing.page, AppSpacing.xxl),
        children: [
          if (kundli == null || userMoon == null) ...[
            _buildMissingBirthDetailsCard(),
            const SizedBox(height: AppSpacing.md),
          ],
          _buildHeroCard(userName, userMoon, partner),
          if (_matchNeedsBirthDetails && !_isMatching && (kundli != null && userMoon != null)) ...[
            const SizedBox(height: AppSpacing.md),
            _buildMissingBirthDetailsCard(),
          ] else if (_matchError != null && !_isMatching) ...[
            const SizedBox(height: AppSpacing.md),
            AppCard(
              padding: EdgeInsets.zero,
              child: AppStateView.error(
                compact: true,
                title: 'Could not check this match',
                message: _matchError,
                onAction: _calculateSynastryMatch,
              ),
            ),
          ],
          if (backendService.isAuthenticated) ..._buildSavedProfilesSection(familyMembers),
          if (_isMatching && _synastryData == null) ...[
            const SizedBox(height: AppSpacing.xl),
            const _ResultsSkeleton(),
          ],
          if (_synastryData != null) ..._buildResults(userName, partnerName),
          const SizedBox(height: AppSpacing.xl),
          _buildCircleLink(),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Top of the tab
  // ---------------------------------------------------------------------------

  Widget _buildHeroCard(String userName, String? userMoon, PartnerInfo? partner) {
    final partnerSub = partner == null
        ? 'Tap to add'
        : (partner.kundli?['moonSign'] != null
            ? '${partner.kundli!['moonSign']} Moon'
            : DateFormat('dd MMM yyyy').format(_parseDate(partner.dob) ?? DateTime.now()));

    return AppCard(
      shadow: true,
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('Check compatibility with someone', style: AppText.title),
          const SizedBox(height: 4),
          const Text(
            'Vedic Guna Milan compares both Moon charts across 8 areas, scored out of 36.',
            style: AppText.body,
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _PersonTile(
                  label: 'You',
                  name: userName,
                  subtitle: userMoon != null ? '$userMoon Moon' : 'Add birth details',
                  onTap: userMoon == null ? () => Navigator.pushNamed(context, AppRoutes.birthDetails) : null,
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(top: 14),
                child: Container(
                  width: 36,
                  height: 36,
                  decoration: const BoxDecoration(color: AppColors.loveSoft, shape: BoxShape.circle),
                  child: const Icon(Icons.favorite_rounded, color: AppColors.love, size: 18),
                ),
              ),
              Expanded(
                child: _PersonTile(
                  label: 'Partner',
                  name: partner?.name ?? 'Add partner',
                  subtitle: partnerSub,
                  empty: partner == null,
                  accent: AppColors.love,
                  actionHint: partner == null ? null : 'Edit',
                  onTap: _isMatching ? null : _showAddPartnerDialog,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          AppButton(
            label: partner == null ? 'Add partner details' : 'Check compatibility',
            icon: partner == null ? Icons.person_add_alt_1_rounded : Icons.favorite_border_rounded,
            loading: _isMatching,
            onPressed: _isMatching ? null : _calculateSynastryMatch,
          ),
        ],
      ),
    );
  }

  Widget _buildMissingBirthDetailsCard() {
    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(color: AppColors.primarySoft, borderRadius: BorderRadius.circular(AppRadius.md)),
            child: const Icon(Icons.edit_calendar_rounded, color: AppColors.primary, size: 20),
          ),
          const SizedBox(width: AppSpacing.sm),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Add your birth details', style: AppText.bodyStrong),
                SizedBox(height: 2),
                Text('Needed for an exact match based on your Moon chart.', style: AppText.caption),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.xs),
          TextButton(
            onPressed: () => Navigator.pushNamed(context, AppRoutes.birthDetails),
            style: TextButton.styleFrom(minimumSize: const Size(48, 44)),
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Saved profiles
  // ---------------------------------------------------------------------------

  List<Widget> _buildSavedProfilesSection(List<Map<String, dynamic>> familyMembers) {
    const header = SectionHeader(
      title: 'Saved profiles',
      subtitle: 'Tap someone to check your match',
      padding: EdgeInsets.fromLTRB(0, AppSpacing.xl, 0, AppSpacing.sm),
    );

    if (familyMembers.isEmpty) {
      if (_familyLoading) {
        return [
          header,
          const SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            physics: NeverScrollableScrollPhysics(),
            child: Row(children: [
              SkeletonBox(width: 132, height: 128, radius: AppRadius.lg),
              SizedBox(width: AppSpacing.sm),
              SkeletonBox(width: 132, height: 128, radius: AppRadius.lg),
              SizedBox(width: AppSpacing.sm),
              SkeletonBox(width: 132, height: 128, radius: AppRadius.lg),
            ]),
          ),
        ];
      }
      if (_familyLoadFailed) {
        return [
          header,
          AppCard(
            padding: EdgeInsets.zero,
            child: AppStateView.error(
              compact: true,
              title: 'Could not load saved profiles',
              onAction: _loadFamily,
            ),
          ),
        ];
      }
      return const [];
    }

    return [
      header,
      SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        clipBehavior: Clip.none,
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _AddProfileCard(onTap: _isMatching ? null : _showAddPartnerDialog),
              for (final member in familyMembers) ...[
                const SizedBox(width: AppSpacing.sm),
                _buildProfileCard(member),
              ],
            ],
          ),
        ),
      ),
    ];
  }

  Widget _buildProfileCard(Map<String, dynamic> member) {
    final name = (member['fullName'] ?? member['name'] ?? 'Family').toString();
    final rel = (member['relationship'] ?? 'Member').toString();
    final id = member['id']?.toString();
    final isSelected = _partner != null && id != null && _partner!.familyId == id;
    final moon = member['kundli'] is Map ? member['kundli']['moonSign']?.toString() : null;

    void select() {
      setState(() {
        _partner = PartnerInfo(
          name: name,
          gender: member['gender']?.toString() ?? 'Not Specified',
          dob: _isoDate(member['dateOfBirth']),
          tob: member['timeOfBirth']?.toString() ?? '12:00',
          pob: member['placeOfBirth']?.toString() ?? '',
          kundli: member['kundli'] is Map ? Map<String, dynamic>.from(member['kundli']) : null,
          familyId: id,
          latitude: _toCoord(member['latitude'] ?? (member['kundli'] is Map ? member['kundli']['latitude'] : null)),
          longitude: _toCoord(member['longitude'] ?? (member['kundli'] is Map ? member['kundli']['longitude'] : null)),
        );
      });
      _calculateSynastryMatch();
    }

    return Semantics(
      button: true,
      selected: isSelected,
      label: 'Match with $name, $rel',
      child: SizedBox(
        width: 140,
        child: Material(
          color: isSelected ? AppColors.loveSoft : AppColors.surface,
          shape: RoundedRectangleBorder(
            borderRadius: AppRadius.card,
            side: BorderSide(color: isSelected ? AppColors.love : AppColors.border, width: isSelected ? 1.4 : 1),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: _isMatching ? null : select,
            onLongPress: () => _confirmDeletePartnerProfile(member),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(AppSpacing.sm, AppSpacing.sm, 0, AppSpacing.sm),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      AppAvatar(name: name, size: 40, color: AppColors.love),
                      const Spacer(),
                      SizedBox(
                        width: 44,
                        height: 44,
                        child: IconButton(
                          tooltip: 'Remove $name',
                          padding: EdgeInsets.zero,
                          icon: const Icon(Icons.close_rounded, size: 18, color: AppColors.textTertiary),
                          onPressed: () => _confirmDeletePartnerProfile(member),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Padding(
                    padding: const EdgeInsets.only(right: AppSpacing.sm),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.bodyStrong),
                        Text(
                          moon != null ? '$rel · $moon Moon' : rel,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppText.caption,
                        ),
                        if (isSelected) ...[
                          const SizedBox(height: 6),
                          const Row(
                            children: [
                              Icon(Icons.check_circle_rounded, size: 14, color: AppColors.love),
                              SizedBox(width: 4),
                              Flexible(
                                child: Text(
                                  'Selected',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.love),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ],
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

  Future<void> _confirmDeletePartnerProfile(Map<String, dynamic> member) async {
    final name = (member['fullName'] ?? member['name'] ?? 'Partner').toString();
    final rel = (member['relationship'] ?? 'Member').toString();
    final idStr = member['id']?.toString();
    final id = int.tryParse(idStr ?? '');
    if (id == null) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Remove $name?'),
        content: Text(
          '$name ($rel) and their saved Kundli will be deleted from your account.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            style: TextButton.styleFrom(foregroundColor: AppColors.textSecondary),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.danger),
            child: const Text('Remove'),
          ),
        ],
      ),
    );

    if (confirm != true || !mounted) return;

    final backendService = Provider.of<BackendService>(context, listen: false);
    final ok = await backendService.deleteFamilyKundli(id);
    if (!mounted) return;

    if (ok) {
      if (_partner?.familyId == idStr) {
        setState(() {
          _partner = null;
          _synastryData = null;
        });
      }
      await backendService.fetchFamilyKundlis();
      if (mounted) showAppSnack(context, '$name removed from saved profiles');
    } else {
      showAppSnack(context, backendService.lastError ?? 'Could not remove profile', error: true);
    }
  }

  Widget _buildCircleLink() {
    return AppCard(
      onTap: () => Navigator.pushNamed(context, AppRoutes.gamesCircle),
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: AppColors.info.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(AppRadius.md),
            ),
            child: const Icon(Icons.groups_rounded, color: AppColors.info, size: 22),
          ),
          const SizedBox(width: AppSpacing.sm),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Cosmic Circle', style: AppText.bodyStrong),
                SizedBox(height: 2),
                Text('See how you match with friends and family', style: AppText.caption),
              ],
            ),
          ),
          const Icon(Icons.chevron_right_rounded, color: AppColors.textTertiary),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Results
  // ---------------------------------------------------------------------------

  List<Widget> _buildResults(String userName, String partnerName) {
    final data = _synastryData!;
    return [
      const SizedBox(height: AppSpacing.xl),
      if (!_isExactCalculation) ...[
        const _Callout(
          color: AppColors.warning,
          background: AppColors.warningSoft,
          icon: Icons.info_outline_rounded,
          title: 'This is an AI estimate',
          body: 'The partner\'s exact Moon chart is not available. Save them to your profiles '
              '(or pick a saved profile) for an exact calculation.',
        ),
        const SizedBox(height: AppSpacing.md),
      ],
      _buildScoreCard(data, userName, partnerName),
      const SizedBox(height: AppSpacing.md),
      _buildKootaCard(data['ashtakoot'], userName, partnerName),
      ..._buildDoshaCallout(data, userName, partnerName),
      const SizedBox(height: AppSpacing.md),
      _buildCollapsibleDeepAnalysis(data, userName, partnerName),
      const SizedBox(height: AppSpacing.lg),
      _buildAskAstrologerButton(userName, partnerName),
      const SizedBox(height: AppSpacing.sm),
      _buildShareButton(userName, partnerName),
    ];
  }

  Widget _buildScoreCard(Map<String, dynamic> data, String userName, String partnerName) {
    final List kootas = data['ashtakoot'] is List ? data['ashtakoot'] : const [];
    double total;
    if (data['gunaTotal'] is num) {
      total = (data['gunaTotal'] as num).toDouble();
    } else {
      total = kootas.whereType<Map>().fold<double>(0, (s, k) => s + _num(k['score']));
    }
    total = total.clamp(0, 36).toDouble();
    final pct = data['score'] is num ? (data['score'] as num).round() : (total / 36 * 100).round();
    final (word, color) = _verdictFor(total);
    final strong = kootas.whereType<Map>().where((k) {
      final m = _num(k['max'], 1);
      return m > 0 && _num(k['score']) / m >= 0.75;
    }).length;
    final weak = kootas.whereType<Map>().where((k) {
      final m = _num(k['max'], 1);
      return m > 0 && _num(k['score']) / m < 0.5;
    }).length;
    final detail = data['verdict']?.toString() ?? '';

    return Semantics(
      label: 'Match score ${_fmtScore(total)} out of 36, $word',
      child: AppCard(
        shadow: true,
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '$userName & $partnerName',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppText.caption.copyWith(color: AppColors.textSecondary),
            ),
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: [
                _ScoreRing(value: total / 36, label: '${_fmtScore(total)}/36'),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(word, style: AppText.headline.copyWith(color: color)),
                      const SizedBox(height: 2),
                      Text('$pct% match', style: AppText.bodyStrong),
                      if (detail.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(detail, maxLines: 3, overflow: TextOverflow.ellipsis, style: AppText.caption),
                      ],
                    ],
                  ),
                ),
              ],
            ),
            if (kootas.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.md),
              const Divider(),
              const SizedBox(height: AppSpacing.sm),
              Row(
                children: [
                  Expanded(child: _MiniStat(icon: Icons.check_circle_rounded, color: AppColors.success, text: '$strong strong areas')),
                  const SizedBox(width: AppSpacing.xs),
                  Expanded(
                    child: _MiniStat(
                      icon: weak == 0 ? Icons.verified_rounded : Icons.error_outline_rounded,
                      color: weak == 0 ? AppColors.success : AppColors.warning,
                      text: weak == 0 ? 'No weak areas' : '$weak need care',
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildKootaCard(dynamic ashtakootData, String userName, String partnerName) {
    final List list = ashtakootData is List ? ashtakootData : const [];
    if (list.isEmpty) return const SizedBox.shrink();
    final items = list.whereType<Map>().toList();

    return AppCard(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.md, AppSpacing.md, AppSpacing.xs),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('The 8 Kootas', style: AppText.title),
                SizedBox(height: 2),
                Text('Tap any area for its meaning and remedies', style: AppText.caption),
              ],
            ),
          ),
          for (var i = 0; i < items.length; i++) ...[
            if (i > 0) const Divider(indent: AppSpacing.md, endIndent: AppSpacing.md),
            _buildKootaRow(Map<String, dynamic>.from(items[i]), userName, partnerName),
          ],
          const SizedBox(height: AppSpacing.xs),
        ],
      ),
    );
  }

  Widget _buildKootaRow(Map<String, dynamic> item, String userName, String partnerName) {
    final name = item['name']?.toString() ?? 'Guna';
    final score = _num(item['score']);
    final max = _num(item['max'], 1);
    final meaning = item['meaning']?.toString() ?? '';
    final verdict = item['verdict']?.toString() ?? '';
    final pct = max <= 0 ? 0.0 : (score / max).clamp(0.0, 1.0);
    final isWeak = pct < 0.5;
    final color = _barColor(pct);
    final plain = _kKootaPlain[name.toLowerCase()] ?? meaning;

    return Semantics(
      button: true,
      label: '$name, ${_fmtScore(score)} of ${_fmtScore(max)}',
      child: InkWell(
        onTap: () => _showKootaRemedySheet(context, item, userName, partnerName),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.subtitle),
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  Text(
                    '${_fmtScore(score)}/${_fmtScore(max)}',
                    style: AppText.bodyStrong.copyWith(color: color),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              ClipRRect(
                borderRadius: BorderRadius.circular(AppRadius.pill),
                child: LinearProgressIndicator(
                  value: pct,
                  minHeight: 6,
                  backgroundColor: AppColors.surfaceMuted,
                  color: color,
                ),
              ),
              const SizedBox(height: 6),
              if (plain.isNotEmpty) Text(plain, style: AppText.body),
              if (verdict.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(verdict, style: AppText.caption),
              ],
              if (isWeak) ...[
                const SizedBox(height: 4),
                const Row(
                  children: [
                    Text('See remedies',
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.primary)),
                    Icon(Icons.chevron_right_rounded, size: 18, color: AppColors.primary),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _buildDoshaCallout(Map<String, dynamic> data, String userName, String partnerName) {
    final manglik = data['manglikCheck'] is Map ? data['manglikCheck'] as Map : null;
    final nb = data['nadiBhakootAnalysis'] is Map ? data['nadiBhakootAnalysis'] as Map : null;
    if (manglik == null && nb == null) return const [];

    final kootas = data['ashtakoot'] is List ? (data['ashtakoot'] as List).whereType<Map>() : const <Map>[];
    bool zero(String n) => kootas.any((k) => k['name']?.toString().toLowerCase() == n && _num(k['score']) == 0);
    final m1 = manglik?['person1Status']?.toString() ?? 'Unknown';
    final m2 = manglik?['person2Status']?.toString() ?? 'Unknown';
    final manglikMismatch = m1.startsWith('Manglik') != m2.startsWith('Manglik') && m1 != 'Unknown' && m2 != 'Unknown';
    final concern = zero('nadi') || zero('bhakoot') || manglikMismatch;

    final color = concern ? AppColors.warning : AppColors.success;
    final entries = <(String, String)>[
      if (manglik != null)
        (
          'Manglik',
          '$userName: $m1 · $partnerName: $m2'
              '${(manglik['manglikVerdict']?.toString() ?? '').isNotEmpty ? '\n${manglik['manglikVerdict']}' : ''}'
        ),
      if ((nb?['nadiVerdict']?.toString() ?? '').isNotEmpty) ('Nadi', nb!['nadiVerdict'].toString()),
      if ((nb?['bhakootVerdict']?.toString() ?? '').isNotEmpty) ('Bhakoot', nb!['bhakootVerdict'].toString()),
    ];
    if (entries.isEmpty) return const [];

    return [
      const SizedBox(height: AppSpacing.md),
      Container(
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: concern ? AppColors.warningSoft : AppColors.successSoft,
          borderRadius: AppRadius.card,
          border: Border.all(color: color.withValues(alpha: 0.35)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(concern ? Icons.shield_outlined : Icons.verified_user_outlined, color: color, size: 22),
                const SizedBox(width: AppSpacing.xs),
                Expanded(
                  child: Text(
                    concern ? 'Doshas to look at' : 'No major dosha',
                    style: AppText.subtitle,
                  ),
                ),
              ],
            ),
            for (final e in entries) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(e.$1, style: AppText.overline.copyWith(color: AppColors.textSecondary)),
              const SizedBox(height: 2),
              Text(e.$2, style: AppText.body.copyWith(color: AppColors.textPrimary)),
            ],
          ],
        ),
      ),
    ];
  }

  // Collapsible section for the deeper astrology so first-time users are not overwhelmed.
  Widget _buildCollapsibleDeepAnalysis(Map<String, dynamic> data, String userName, String partnerName) {
    final synastry = data['planetarySynastry'];
    final report = (data['relationshipReport'] ?? data['summary'] ?? '').toString();
    final hasSynastry = synastry is List && synastry.isNotEmpty;
    if (!hasSynastry && report.trim().isEmpty) return const SizedBox.shrink();

    return AppCard(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            button: true,
            expanded: _showDeepAstroAnalysis,
            child: InkWell(
              onTap: () => setState(() => _showDeepAstroAnalysis = !_showDeepAstroAnalysis),
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.md),
                child: Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: AppColors.info.withValues(alpha: 0.10),
                        borderRadius: BorderRadius.circular(AppRadius.md),
                      ),
                      child: const Icon(Icons.auto_stories_outlined, color: AppColors.info, size: 20),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Full report', style: AppText.bodyStrong),
                          SizedBox(height: 2),
                          Text('Sun, Moon, Venus & Mars alignment and written guidance', style: AppText.caption),
                        ],
                      ),
                    ),
                    Icon(
                      _showDeepAstroAnalysis ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded,
                      color: AppColors.textSecondary,
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (_showDeepAstroAnalysis) ...[
            const Divider(),
            Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (hasSynastry) ...[
                    _buildPlanetarySynastry(synastry, userName, partnerName),
                    const SizedBox(height: AppSpacing.md),
                  ],
                  _buildRelationshipReport(report),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildPlanetarySynastry(List list, String userName, String partnerName) {
    final items = list.whereType<Map>().toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Planet alignment', style: AppText.subtitle),
        const SizedBox(height: AppSpacing.xs),
        for (final item in items)
          Container(
            margin: const EdgeInsets.only(bottom: AppSpacing.xs),
            padding: const EdgeInsets.all(AppSpacing.sm),
            decoration: BoxDecoration(
              color: AppColors.surfaceMuted,
              borderRadius: BorderRadius.circular(AppRadius.md),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: AppSpacing.xs,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(item['planet']?.toString() ?? 'Planet', style: AppText.bodyStrong),
                    if ((item['alignment']?.toString() ?? '').isNotEmpty)
                      AppBadge(label: item['alignment'].toString(), color: AppColors.info),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  '$userName: ${item['p1Sign'] ?? '—'}  ·  $partnerName: ${item['p2Sign'] ?? '—'}',
                  style: AppText.body,
                ),
                if ((item['verdict']?.toString() ?? '').isNotEmpty)
                  Text(item['verdict'].toString(), style: AppText.caption),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildRelationshipReport(String reportText) {
    if (reportText.trim().isEmpty) return const SizedBox.shrink();
    final blocks = reportText.split('###').where((b) => b.trim().isNotEmpty).toList();

    if (blocks.length <= 1 && !reportText.contains('###')) {
      return SelectableText.rich(TextSpan(children: _parseFormattedSpans(reportText.trim())));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final block in blocks)
          Builder(builder: (context) {
            final lines = block.trim().split('\n');
            final title = lines.first.trim();
            final body = lines.sublist(1).join('\n').trim();
            return Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: AppText.subtitle),
                  if (body.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    SelectableText.rich(TextSpan(children: _parseFormattedSpans(body))),
                  ],
                ],
              ),
            );
          }),
      ],
    );
  }

  List<TextSpan> _parseFormattedSpans(String text) {
    const normal = TextStyle(color: AppColors.textSecondary, fontSize: 14, height: 1.55);
    const bold = TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w700, fontSize: 14, height: 1.55);
    final spans = <TextSpan>[];
    final exp = RegExp(r'\*\*(.*?)\*\*');
    var start = 0;
    for (final match in exp.allMatches(text)) {
      if (match.start > start) spans.add(TextSpan(text: text.substring(start, match.start), style: normal));
      spans.add(TextSpan(text: match.group(1), style: bold));
      start = match.end;
    }
    if (start < text.length) spans.add(TextSpan(text: text.substring(start), style: normal));
    return spans;
  }

  String _shareSummary(String p1, String p2) {
    final d = _synastryData ?? const {};
    final buffer = StringBuffer('Guna Milan: $p1 & $p2\n')
      ..writeln('${d['gunas'] ?? ''} — ${d['verdict'] ?? ''}');
    final list = d['ashtakoot'];
    if (list is List) {
      for (final k in list.whereType<Map>()) {
        final s = num.tryParse(k['score']?.toString() ?? '') ?? 0;
        buffer.writeln('• ${k['name']}: ${_fmtScore(s)}/${k['max']}');
      }
    }
    buffer.write('Calculated with CosmicGuide');
    return buffer.toString();
  }

  Widget _buildShareButton(String p1, String p2) {
    return AppButton(
      label: 'Share result',
      icon: Icons.ios_share_rounded,
      variant: AppButtonVariant.outline,
      onPressed: () async {
        final text = _shareSummary(p1, p2);
        bool launched = false;
        try {
          launched = await launchUrl(
            Uri.parse('https://wa.me/?text=${Uri.encodeComponent(text)}'),
            mode: LaunchMode.externalApplication,
          );
        } catch (_) {
          launched = false;
        }
        if (launched) return;
        await Clipboard.setData(ClipboardData(text: text));
        if (!mounted) return;
        showAppSnack(context, 'Match summary copied to clipboard');
      },
    );
  }

  Widget _buildAskAstrologerButton(String p1, String p2) {
    return AppButton(
      label: 'Ask AI about this match',
      icon: Icons.auto_awesome_rounded,
      onPressed: () {
        final d = _synastryData ?? const {};
        final partner = _partner;
        final kootas = (d['ashtakoot'] is List)
            ? (d['ashtakoot'] as List).whereType<Map>().map((k) => '${k['name']} ${k['score']}/${k['max']}').join(', ')
            : '';
        Navigator.pushNamed(context, AppRoutes.chatbot, arguments: {
          'name': 'Vedic Love Specialist',
          'specialty': 'Guna Milan & Synastry',
          'field': 'Marriage Consultation',
          'initialMessage': 'Please give relationship guidance for $p1 and $p2'
              '${partner != null ? ' (partner born ${partner.dob} at ${partner.tob}, ${partner.pob})' : ''}. '
              'Our Ashtakoot Guna Milan is ${d['gunas'] ?? ''}${kootas.isNotEmpty ? ' ($kootas)' : ''}. '
              'What are the strengths, challenges and remedies?',
        });
      },
    );
  }

  // ---------------------------------------------------------------------------
  // Koota remedies sheet
  // ---------------------------------------------------------------------------

  Map<String, dynamic> _getKootaRemedyInfo(String kootaName, double score, double max, String verdict) {
    switch (kootaName.toLowerCase()) {
      case 'bhakoot':
        return {
          'title': 'Bhakoot Dosha (0/7)',
          'domain': 'Emotional bonding & financial harmony',
          'explanation':
              'Bhakoot refers to the relative Moon sign placement (6/8, 9/5, or 12/2 axis). When scored 0/7, traditional astrology notes emotional or financial rhythm differences. However, classical texts like Muhurta Chintamani specify that if Moon-sign lords are mutual friends, this dosha is largely cancelled.',
          'remedies': [
            'Chant the Maha Mrityunjaya Mantra 108 times daily for emotional peace and domestic prosperity.',
            'Perform Shiva-Parvati Abhishek on Mondays with milk, honey and bilva leaves.',
            'Keep joint finances transparent; avoid large purchases without agreeing together.',
            'Donate yellow lentils (Chana dal) or wheat to the needy on Thursdays.',
          ],
          'panditQuery':
              'Namaste Pandit Ji, in our Ashtakoot Milan we scored 0/7 in Bhakoot (Bhakoot Dosha). Please examine our Moon signs and advise specific Vedic pujas, pariharas and remedies to neutralize this dosha.',
        };
      case 'nadi':
        return {
          'title': 'Nadi Dosha (${score.toStringAsFixed(0)}/8)',
          'domain': 'Health, physical balance & children',
          'explanation':
              'Nadi represents bio-energetic and genetic compatibility (Vata, Pitta, Kapha). Both sharing the same Nadi leads to 0/8 points. In classical parihara, if the Nakshatras differ while sharing a sign, or signs differ while sharing a nakshatra, the dosha is mitigated.',
          'remedies': [
            'Maha Mrityunjaya Japa with a formal Sankalpa for health, longevity and happy progeny.',
            'Perform Swarna Nadi Daan or gold/grain charity to elderly priests on an auspicious muhurat.',
            'Consider pre-marital medical tests (Rh factor, genetic carrier screening) for peace of mind.',
            'Feed green grass, spinach and fresh jaggery to cows on Wednesday mornings.',
          ],
          'panditQuery':
              'Namaste Pandit Ji, our Kundli Milan shows Nadi Dosha (${score.toStringAsFixed(0)}/8). Are there cancellations present in our charts and what specific parihara puja is needed?',
        };
      case 'graha maitri':
      case 'grahamaitri':
        return {
          'title': 'Graha Maitri (${score.toStringAsFixed(1)}/5)',
          'domain': 'Mental outlook & understanding',
          'explanation':
              'Graha Maitri evaluates planetary friendship between both Moon-sign rulers. A score below 3 points indicates differing approaches to problem-solving, intellectual views, or communication tempos.',
          'remedies': [
            'Recite the Gayatri Mantra or Vishnu Sahasranama together every morning.',
            'Worship the ruling planets of both partners\' Moon signs.',
            'Practise patient listening during disagreements; respect each other\'s views.',
            'Light a ghee lamp near a Holy Basil (Tulsi) plant every evening.',
          ],
          'panditQuery':
              'Namaste Pandit Ji, our Graha Maitri score is $score/5. What planetary remedies will harmonize our intellectual wavelength and communication?',
        };
      case 'gana':
        return {
          'title': 'Gana (${score.toStringAsFixed(0)}/6)',
          'domain': 'Temperament & lifestyle rhythm',
          'explanation':
              'Gana classifies individuals into Deva (divine/calm), Manushya (human/balanced), and Rakshasa (fiery/assertive). Different Ganas can lead to clashes in expectations, tempo, or how stress is handled.',
          'remedies': [
            'Recite Hanuman Chalisa daily to ease ego clashes and build mutual humility.',
            'Offer red flowers and vermilion to Lord Hanuman on Tuesday mornings.',
            'Avoid arguing when hungry or tired; cool down before resolving disputes.',
            'Feed bread or biscuits to stray dogs on Saturdays.',
          ],
          'panditQuery':
              'Namaste Pandit Ji, our Ashtakoot Milan shows a Gana difference ($score/6). How can we balance our temperaments and prevent emotional misunderstandings?',
        };
      case 'yoni':
        return {
          'title': 'Yoni (${score.toStringAsFixed(1)}/4)',
          'domain': 'Physical intimacy & affection',
          'explanation':
              'Yoni represents instinctive biological affinity and physical affection. A low score implies differing romantic gestures or needs for affection.',
          'remedies': [
            'Offer fragrant white flowers to Lord Shiva and Goddess Parvati on Fridays.',
            'Keep natural scents (sandalwood, rose, lavender) in the bedroom.',
            'Make time for kind words, gentle touch and regular date nights.',
            'Donate white rice, curd or sugar to a family in need on Fridays.',
          ],
          'panditQuery':
              'Namaste Pandit Ji, our Yoni score is $score/4. Please suggest Vedic pariharas to foster lifelong physical affection and intimacy.',
        };
      case 'tara':
        return {
          'title': 'Tara (${score.toStringAsFixed(1)}/3)',
          'domain': 'Destiny, luck & timing',
          'explanation':
              'Tara measures the Nakshatra distance and mutual fortune. A low score indicates that major transitions may encounter occasional timing friction.',
          'remedies': [
            'Recite the Navagraha Stotram on Saturday mornings.',
            'Offer black sesame seeds and mustard oil at a Shani temple on Saturdays.',
            'Check the Panchang before major moves or property investments.',
          ],
          'panditQuery':
              'Namaste Pandit Ji, we scored $score/3 in Tara Guna. What astrological remedies will protect our mutual luck and auspicious timing?',
        };
      default:
        return {
          'title': '$kootaName (${_fmtScore(score)}/${_fmtScore(max)})',
          'domain': 'Vedic compatibility factor',
          'explanation':
              'Vedic astrology offers remedies (parihara) to harmonise this aspect and strengthen your bond.',
          'remedies': [
            'A short shared prayer or gratitude practice each day.',
            'Worship Lord Ganesha with Durva grass to remove obstacles in married life.',
            'Keep trust, respect and patient communication at the centre.',
          ],
          'panditQuery':
              'Namaste Pandit Ji, please guide us on Vedic remedies for $kootaName ($score/$max) in our Kundli Milan.',
        };
    }
  }

  void _showKootaRemedySheet(BuildContext context, Map<String, dynamic> item, String p1, String p2) {
    final String name = item['name']?.toString() ?? 'Guna';
    final double score = _num(item['score']);
    final double max = _num(item['max'], 1);
    final String verdict = item['verdict']?.toString() ?? '';
    final remedyInfo = _getKootaRemedyInfo(name, score, max, verdict);
    final pct = max <= 0 ? 0.0 : (score / max).clamp(0.0, 1.0);
    final color = _barColor(pct);

    showAppSheet(
      context,
      builder: (ctx) => ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(ctx).height * 0.85),
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(
              AppSpacing.page, 0, AppSpacing.page, AppSpacing.xl + MediaQuery.paddingOf(ctx).bottom),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(remedyInfo['title'] as String, style: AppText.title),
                        const SizedBox(height: 2),
                        Text(remedyInfo['domain'] as String, style: AppText.caption),
                      ],
                    ),
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  AppBadge(label: '${_fmtScore(score)}/${_fmtScore(max)}', color: color),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              Text(remedyInfo['explanation'] as String, style: AppText.body),
              if (verdict.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.sm),
                _Callout(
                  color: color,
                  background: color.withValues(alpha: 0.08),
                  icon: Icons.insights_rounded,
                  title: 'In your charts',
                  body: verdict,
                ),
              ],
              const SizedBox(height: AppSpacing.lg),
              const Text('Suggested remedies', style: AppText.subtitle),
              const SizedBox(height: AppSpacing.xs),
              for (final remedy in remedyInfo['remedies'] as List<String>)
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Padding(
                        padding: EdgeInsets.only(top: 2),
                        child: Icon(Icons.check_circle_outline_rounded, size: 18, color: AppColors.success),
                      ),
                      const SizedBox(width: AppSpacing.xs),
                      Expanded(child: Text(remedy, style: AppText.body.copyWith(color: AppColors.textPrimary))),
                    ],
                  ),
                ),
              const SizedBox(height: AppSpacing.md),
              AppCard(
                gradient: AppColors.cosmicGradient,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      'Want advice for your exact charts?',
                      style: TextStyle(color: AppColors.textOnDark, fontWeight: FontWeight.w700, fontSize: 15),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Our AI astrologer can suggest a puja, mantra timing or other remedies for this area.',
                      style: TextStyle(color: AppColors.textOnDarkMuted, fontSize: 13, height: 1.4),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    AppButton(
                      label: 'Ask AI about this',
                      icon: Icons.chat_bubble_outline_rounded,
                      onPressed: () {
                        Navigator.pop(ctx);
                        Navigator.pushNamed(context, AppRoutes.chatbot, arguments: {
                          'name': 'Vedic Love & Dosha Specialist',
                          'specialty': 'Guna Milan & Parihara Remedies',
                          'field': 'Marriage Remedies',
                          'initialMessage': remedyInfo['panditQuery'],
                        });
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Matching logic
  // ---------------------------------------------------------------------------

  Future<void> _showAddPartnerDialog() async {
    if (_isMatching) return;
    final result = await showAppSheet<PartnerInfo>(
      context,
      builder: (ctx) => PartnerBirthDetailsSheet(initial: _partner),
    );
    if (result == null || !mounted) return;
    setState(() => _partner = result);
    _calculateSynastryMatch();
  }

  Future<void> _calculateSynastryMatch() async {
    if (_isMatching) return;
    final partner = _partner;
    if (partner == null) {
      _showAddPartnerDialog();
      return;
    }
    final backendService = Provider.of<BackendService>(context, listen: false);

    setState(() {
      _isMatching = true;
      _matchError = null;
      _matchNeedsBirthDetails = false;
    });

    final userName = _userName(backendService);
    final userProfile = _MoonProfile.fromKundli(userName, backendService.kundliData);
    final partnerProfile = _MoonProfile.fromKundli(partner.name, partner.kundli);

    if (userProfile != null && partnerProfile != null) {
      final data = _buildLocalResult(userProfile, partnerProfile, _userGender(backendService), partner.gender);
      if (!mounted) return;
      setState(() {
        _isMatching = false;
        _isExactCalculation = true;
        _synastryData = data;
      });
      return;
    }

    // Partner's (or user's) Moon chart is unknown → ask the backend for an AI estimate.
    Map<String, dynamic>? result;
    try {
      result = await backendService.fetchSynastryMatch(
        partnerName: partner.name,
        partnerGender: partner.gender,
        partnerDob: partner.dob,
        partnerTob: partner.tob,
        partnerPob: partner.pob,
        // Timezone is resolved server-side from the birth-place coordinates.
        partnerLatitude: partner.latitude,
        partnerLongitude: partner.longitude,
      );
    } catch (e) {
      result = null;
    }
    if (!mounted) return;

    setState(() {
      _isMatching = false;
      if (result != null && result['ashtakoot'] is List) {
        _isExactCalculation = false;
        _synastryData = result;
      } else if (!backendService.hasBirthDetails) {
        // Synastry needs the user's own saved chart.
        _synastryData = null;
        _matchNeedsBirthDetails = true;
      } else {
        _matchError = backendService.lastError ?? 'Could not calculate the match. Please check your connection and try again.';
      }
    });
  }

  Map<String, dynamic> _buildLocalResult(_MoonProfile user, _MoonProfile partner, String? userGender, String partnerGender) {
    // Ashtakoot is directional (boy vs girl). Default the account holder to the boy's
    // side unless the user is female or only the partner is male.
    final userIsFemale = (userGender ?? '').toLowerCase().startsWith('f');
    final partnerIsMale = partnerGender.toLowerCase().startsWith('m');
    final boyIsPartner = userIsFemale || (partnerIsMale && !(userGender ?? '').toLowerCase().startsWith('m'));
    final boy = boyIsPartner ? partner : user;
    final girl = boyIsPartner ? user : partner;

    final kootas = _AshtakootEngine.compute(boy, girl);
    final total = kootas.fold<double>(0, (s, k) => s + k.score);
    final pct = (total / 36 * 100).round();

    String verdict;
    if (total < 18) {
      verdict = 'Low Compatibility — below 18 Gunas (not recommended)';
    } else if (total < 25) {
      verdict = 'Average Compatibility (Madhyam Milan)';
    } else if (total < 33) {
      verdict = 'Very Good Compatibility (Uttam Milan)';
    } else {
      verdict = 'Excellent Compatibility (Ati Uttam Milan)';
    }

    final nadi = kootas.firstWhere((k) => k.name == 'Nadi');
    final bhakoot = kootas.firstWhere((k) => k.name == 'Bhakoot');
    final sameNakshatra = user.nakshatra == partner.nakshatra;
    final sameSign = user.moonSign == partner.moonSign;

    String nadiVerdict;
    if (nadi.score == 8) {
      nadiVerdict =
          'No Nadi Dosha (8/8). ${user.name} is ${_AshtakootEngine.nadiName(user.nakshatra)} and ${partner.name} is ${_AshtakootEngine.nadiName(partner.nakshatra)} Nadi — favourable for health and progeny.';
    } else {
      final cancel = (sameSign && !sameNakshatra) || (sameNakshatra && !sameSign)
          ? ' Classical texts consider this dosha mitigated because the Moon ${sameSign ? 'sign is shared but nakshatras differ' : 'nakshatra is shared but signs differ'}.'
          : ' Consider consulting an astrologer for Nadi Dosha remedies (parihara).';
      nadiVerdict = 'Nadi Dosha (0/8): both partners share ${_AshtakootEngine.nadiName(user.nakshatra)} Nadi.$cancel';
    }

    final String bhakootVerdict;
    final boyLord = _AshtakootEngine._signLord[boy.moonSign];
    final girlLord = _AshtakootEngine._signLord[girl.moonSign];
    final friendlyLords = boyLord == girlLord ||
        (_AshtakootEngine._relation[boyLord][girlLord] == 1 && _AshtakootEngine._relation[girlLord][boyLord] == 1);
    if (bhakoot.score == 7) {
      bhakootVerdict = 'No Bhakoot Dosha (7/7): ${bhakoot.verdict.split(' — ').first} Moon-sign relationship supports prosperity and emotional bonding.';
    } else {
      bhakootVerdict = 'Bhakoot Dosha (0/7) on the ${bhakoot.verdict.split(' — ').first} axis.'
          '${friendlyLords ? ' The Moon-sign lords are the same or mutual friends, which traditionally cancels this dosha.' : ' Remedies and careful financial planning are advised.'}';
    }

    // Manglik (Mars in 1, 2, 4, 7, 8 or 12 from Lagna).
    const manglikHouses = {1, 2, 4, 7, 8, 12};
    String manglikStatus(_MoonProfile p) {
      if (p.marsHouse == null) return 'Unknown';
      return manglikHouses.contains(p.marsHouse) ? 'Manglik (Mars in house ${p.marsHouse})' : 'Non-Manglik';
    }

    final m1 = manglikStatus(user), m2 = manglikStatus(partner);
    String manglikVerdict;
    if (m1 == 'Unknown' || m2 == 'Unknown') {
      manglikVerdict = 'Full planetary positions are needed for both charts to assess Manglik Dosha.';
    } else if (m1.startsWith('Manglik') == m2.startsWith('Manglik')) {
      manglikVerdict = m1.startsWith('Manglik')
          ? 'Both partners are Manglik — the dosha is mutually cancelled.'
          : 'Neither partner is Manglik — no Mangal Dosha concern.';
    } else {
      manglikVerdict = 'Only one partner is Manglik. Check for cancellations and consider remedies before marriage.';
    }

    // Planetary synastry for Sun, Moon, Venus & Mars by sign distance.
    const planets = [
      ['sun', 'Sun (Willpower)'],
      ['moon', 'Moon (Emotions)'],
      ['venus', 'Venus (Romance)'],
      ['mars', 'Mars (Passion)'],
    ];
    final synastry = <Map<String, dynamic>>[];
    for (final p in planets) {
      final s1 = user.planetSigns[p[0]], s2 = partner.planetSigns[p[0]];
      if (s1 == null || s2 == null) continue;
      final d = (s2 - s1 + 12) % 12;
      String alignment, v;
      switch (d) {
        case 0:
          alignment = 'Conjunction (same sign)';
          v = 'Strong blending of energies';
          break;
        case 4:
        case 8:
          alignment = 'Trine (120°)';
          v = 'Harmonious, natural flow';
          break;
        case 2:
        case 10:
          alignment = 'Sextile (60°)';
          v = 'Supportive and cooperative';
          break;
        case 6:
          alignment = 'Opposition (180°)';
          v = 'Magnetic attraction with polarity';
          break;
        case 3:
        case 9:
          alignment = 'Square (90°)';
          v = 'Friction that needs conscious effort';
          break;
        default:
          alignment = 'Inconjunct';
          v = 'Requires adjustment and patience';
      }
      synastry.add({'planet': p[1], 'p1Sign': _kSigns[s1], 'p2Sign': _kSigns[s2], 'alignment': alignment, 'verdict': v});
    }

    final strong = kootas.where((k) => k.score >= k.max * 0.75).map((k) => k.name).toList();
    final weak = kootas.where((k) => k.score <= k.max * 0.25).map((k) => k.name).toList();

    final report = StringBuffer()
      ..writeln('### Emotional Bond & Mutual Understanding')
      ..writeln('${user.name} (Moon in **${_kSigns[user.moonSign]}**, **${_kNakshatras[user.nakshatra]}** nakshatra) and '
          '${partner.name} (Moon in **${_kSigns[partner.moonSign]}**, **${_kNakshatras[partner.nakshatra]}** nakshatra) score '
          '**${_fmtScore(total)} of 36 Gunas**.')
      ..writeln(strong.isNotEmpty ? 'Strongest areas: **${strong.join(', ')}**.' : '')
      ..writeln()
      ..writeln('### Marriage Longevity & Progeny Compatibility')
      ..writeln(total >= 18
          ? 'The score is above the traditional 18-Guna threshold for marriage. ${nadi.score == 8 && bhakoot.score == 7 ? 'With no Nadi or Bhakoot Dosha, the foundation for health, family and finances is supportive.' : 'Pay attention to the doshas noted above.'}'
          : 'The score is below the traditional 18-Guna threshold. A detailed reading of both full charts (7th house, Venus and Navamsha) is strongly recommended before deciding.')
      ..writeln()
      ..writeln('### Sacred Guidance & Relationship Remedies')
      ..writeln(weak.isNotEmpty
          ? 'Areas needing care: **${weak.join(', ')}**. Honest communication, shared spiritual practice and appropriate remedies prescribed by an astrologer help balance these factors.'
          : 'No koota is critically weak. Keep nurturing the bond through shared rituals, patience and open communication.');

    return {
      'score': pct,
      'gunaTotal': total,
      'gunas': '${_fmtScore(total)} / 36 Gunas',
      'verdict': verdict,
      'ashtakoot': kootas
          .map((k) => {'name': k.name, 'score': k.score, 'max': k.max, 'meaning': k.meaning, 'verdict': k.verdict})
          .toList(),
      'planetarySynastry': synastry,
      'manglikCheck': {'person1Status': m1, 'person2Status': m2, 'manglikVerdict': manglikVerdict},
      'nadiBhakootAnalysis': {'nadiVerdict': nadiVerdict, 'bhakootVerdict': bhakootVerdict},
      'relationshipReport': report.toString(),
    };
  }

  void _showInfoDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('What is Guna Milan?'),
        content: const SingleChildScrollView(
          child: Text(
            'Ashtakoot Guna Milan compares the Moon sign and Moon nakshatra of both partners across 8 kootas: '
            'Varna (1), Vashya (2), Tara (3), Yoni (4), Graha Maitri (5), Gana (6), Bhakoot (7) and Nadi (8), '
            '36 points in total.\n\n'
            '18+ is traditionally acceptable, 25+ very good and 33+ excellent. '
            'Pick a saved profile (or save the partner as one) so both Moon charts are calculated exactly.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Got it'),
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// Private building blocks
// =============================================================================

/// Avatar + name + one-line context for "You" / "Partner" in the hero card.
class _PersonTile extends StatelessWidget {
  final String label;
  final String name;
  final String subtitle;
  final bool empty;
  final Color accent;
  final String? actionHint;
  final VoidCallback? onTap;

  const _PersonTile({
    required this.label,
    required this.name,
    required this.subtitle,
    this.empty = false,
    this.accent = AppColors.cosmicLight,
    this.actionHint,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final avatar = empty
        ? Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: AppColors.loveSoft,
              shape: BoxShape.circle,
              border: Border.all(color: AppColors.love.withValues(alpha: 0.4)),
            ),
            child: const Icon(Icons.add_rounded, color: AppColors.love, size: 26),
          )
        : AppAvatar(name: name, size: 56, color: accent);

    return Semantics(
      button: onTap != null,
      label: '$label: $name, $subtitle',
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
          child: Column(
            children: [
              avatar,
              const SizedBox(height: AppSpacing.xs),
              Text(label, style: AppText.overline),
              const SizedBox(height: 2),
              Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center, style: AppText.bodyStrong),
              Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center, style: AppText.caption),
              if (actionHint != null)
                Text(actionHint!,
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.primary)),
            ],
          ),
        ),
      ),
    );
  }
}

/// First card of the saved-profiles rail: add a new person.
class _AddProfileCard extends StatelessWidget {
  final VoidCallback? onTap;
  const _AddProfileCard({this.onTap});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 120,
      child: Semantics(
        button: true,
        label: 'Add someone new',
        excludeSemantics: true,
        child: AppCard(
          onTap: onTap,
          padding: const EdgeInsets.all(AppSpacing.sm),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: const BoxDecoration(color: AppColors.primarySoft, shape: BoxShape.circle),
                child: const Icon(Icons.person_add_alt_1_rounded, color: AppColors.primary, size: 20),
              ),
              const SizedBox(height: AppSpacing.xs),
              const Text('Add someone', textAlign: TextAlign.center, style: AppText.bodyStrong),
            ],
          ),
        ),
      ),
    );
  }
}

/// Circular "27/36" score ring.
class _ScoreRing extends StatelessWidget {
  final double value;
  final String label;
  const _ScoreRing({required this.value, required this.label});

  @override
  Widget build(BuildContext context) {
    final reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    return SizedBox(
      width: 108,
      height: 108,
      child: TweenAnimationBuilder<double>(
        duration: reduce ? Duration.zero : const Duration(milliseconds: 700),
        curve: Curves.easeOutCubic,
        tween: Tween(begin: 0, end: value.clamp(0.0, 1.0)),
        builder: (context, v, _) => Stack(
          fit: StackFit.expand,
          children: [
            CircularProgressIndicator(
              value: v,
              strokeWidth: 9,
              strokeCap: StrokeCap.round,
              backgroundColor: AppColors.loveSoft,
              color: AppColors.love,
            ),
            Padding(
              padding: const EdgeInsets.all(18),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(label, style: AppText.headline),
                    const Text('Gunas', style: AppText.caption),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MiniStat extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String text;
  const _MiniStat({required this.icon, required this.color, required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(width: 6),
        Expanded(
          child: Text(text, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.bodyStrong),
        ),
      ],
    );
  }
}

/// Tinted callout used for notices and chart findings.
class _Callout extends StatelessWidget {
  final Color color;
  final Color background;
  final IconData icon;
  final String title;
  final String body;

  const _Callout({
    required this.color,
    required this.background,
    required this.icon,
    required this.title,
    required this.body,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: color.withValues(alpha: 0.30)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: AppSpacing.xs),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: AppText.bodyStrong),
                const SizedBox(height: 2),
                Text(body, style: AppText.body),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Loading placeholder shaped like the results (ring + koota rows).
class _ResultsSkeleton extends StatelessWidget {
  const _ResultsSkeleton();

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Calculating match',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const AppCard(
            child: Row(
              children: [
                SkeletonBox(width: 108, height: 108, radius: 54),
                SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SkeletonBox(width: 120, height: 22),
                      SizedBox(height: AppSpacing.xs),
                      SkeletonBox(width: 80, height: 14),
                      SizedBox(height: AppSpacing.xs),
                      SkeletonBox(height: 12),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var i = 0; i < 4; i++) ...[
                  if (i > 0) const SizedBox(height: AppSpacing.md),
                  const SkeletonBox(width: 110, height: 14),
                  const SizedBox(height: AppSpacing.xs),
                  const SkeletonBox(height: 6),
                  const SizedBox(height: AppSpacing.xs),
                  const SkeletonBox(width: 200, height: 12),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// Partner birth-details sheet
// =============================================================================

class PartnerBirthDetailsSheet extends StatefulWidget {
  final PartnerInfo? initial;

  const PartnerBirthDetailsSheet({super.key, this.initial});

  @override
  State<PartnerBirthDetailsSheet> createState() => _PartnerBirthDetailsSheetState();
}

class _PartnerBirthDetailsSheetState extends State<PartnerBirthDetailsSheet> {
  final TextEditingController _nameController = TextEditingController();
  String _gender = 'Female';

  DateTime? _selectedDate;
  TimeOfDay? _selectedTime;
  bool _dontKnowTime = false;

  final TextEditingController _placeController = TextEditingController();
  List<CitySuggestion> _placeSuggestions = [];
  bool _isSearchingPlace = false;
  Timer? _debounceTimer;
  double? _latitude;
  double? _longitude;
  String? _selectedPlaceName;

  bool _saveToFamily = true;
  bool _isSaving = false;
  String? _errorText;

  @override
  void initState() {
    super.initState();
    final p = widget.initial;
    if (p != null) {
      _nameController.text = p.name;
      if (const ['Male', 'Female', 'Other'].contains(p.gender)) _gender = p.gender;
      _selectedDate = _parseDate(p.dob);
      final m = RegExp(r'^(\d{1,2}):(\d{2})').firstMatch(p.tob);
      if (m != null) {
        _selectedTime = TimeOfDay(hour: int.parse(m.group(1)!) % 24, minute: int.parse(m.group(2)!) % 60);
      }
      _placeController.text = p.pob;
      _selectedPlaceName = p.pob;
    }
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _nameController.dispose();
    _placeController.dispose();
    super.dispose();
  }

  void _onPlaceSearchChanged(String query) {
    if (_selectedPlaceName != null && query != _selectedPlaceName) {
      _selectedPlaceName = null;
      _latitude = null;
      _longitude = null;
    }
    _debounceTimer?.cancel();
    final q = query.trim();
    if (q.length < 2) {
      setState(() {
        _placeSuggestions = [];
        _isSearchingPlace = false;
      });
      return;
    }

    _debounceTimer = Timer(const Duration(milliseconds: 300), () async {
      if (!mounted) return;
      setState(() => _isSearchingPlace = true);
      List<CitySuggestion> suggestions = const [];
      try {
        suggestions = await CityAutocompleteService.fetchCitySuggestions(q);
      } catch (e) {
        debugPrint('City search failed: $e');
      }
      if (!mounted || _placeController.text.trim() != q) return;
      setState(() {
        _placeSuggestions = suggestions;
        _isSearchingPlace = false;
      });
    });
  }

  void _selectSuggestion(CitySuggestion suggestion) {
    _debounceTimer?.cancel();
    setState(() {
      _placeController.text = suggestion.fullDisplayName;
      _selectedPlaceName = suggestion.fullDisplayName;
      _latitude = suggestion.latitude;
      _longitude = suggestion.longitude;
      _placeSuggestions = [];
      _isSearchingPlace = false;
    });
    FocusScope.of(context).unfocus();
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate ?? DateTime(now.year - 25, 1, 1),
      firstDate: DateTime(1900),
      lastDate: now,
    );
    if (picked != null && mounted) setState(() => _selectedDate = picked);
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _selectedTime ?? const TimeOfDay(hour: 12, minute: 0),
    );
    if (picked != null && mounted) {
      setState(() {
        _selectedTime = picked;
        _dontKnowTime = false;
      });
    }
  }

  Future<void> _submitForm() async {
    FocusScope.of(context).unfocus();
    final name = _nameController.text.trim();
    String? error;
    if (name.length < 2) {
      error = 'Please enter partner\'s full name';
    } else if (_selectedDate == null) {
      error = 'Please select partner\'s date of birth';
    } else if (_selectedTime == null && !_dontKnowTime) {
      error = 'Please select time of birth or tick "I don\'t know the exact time"';
    } else if (_placeController.text.trim().isEmpty) {
      error = 'Please enter partner\'s place of birth';
    }
    if (error != null) {
      setState(() => _errorText = error);
      return;
    }

    final dobStr = DateFormat('yyyy-MM-dd').format(_selectedDate!);
    final tobStr = _dontKnowTime || _selectedTime == null
        ? '12:00'
        : '${_selectedTime!.hour.toString().padLeft(2, '0')}:${_selectedTime!.minute.toString().padLeft(2, '0')}';
    final pobStr = _placeController.text.trim();

    final backendService = Provider.of<BackendService>(context, listen: false);
    Map<String, dynamic>? saved;
    if (_saveToFamily && backendService.isAuthenticated) {
      setState(() {
        _isSaving = true;
        _errorText = null;
      });
      try {
        saved = await backendService.addFamilyKundli(
          relationship: 'Partner',
          fullName: name,
          gender: _gender,
          dateOfBirth: dobStr,
          timeOfBirth: tobStr,
          placeOfBirth: pobStr,
          latitude: _latitude,
          longitude: _longitude,
          birthTimeKnown: !_dontKnowTime,
        );
      } catch (e) {
        saved = null;
      }
      if (!mounted) return;
      setState(() => _isSaving = false);
      if (saved == null) {
        setState(() => _errorText = '${backendService.lastError ?? 'Could not save the partner profile.'} '
            'Untick "Save to Family Profiles" to continue with an AI estimate, or try again.');
        return;
      }
    }

    if (!mounted) return;
    Navigator.pop(
      context,
      PartnerInfo(
        name: name,
        gender: _gender,
        dob: dobStr,
        tob: tobStr,
        pob: pobStr,
        kundli: saved?['kundli'] is Map ? Map<String, dynamic>.from(saved!['kundli']) : null,
        familyId: saved?['id']?.toString(),
        latitude: _latitude,
        longitude: _longitude,
      ),
    );
  }

  // ---------------------------------------------------------------- steps
  // One question per screen: name, gender, date, time, place.
  static const _stepCount = 5;
  int _step = 0;
  bool _forward = true;

  String get _partnerFirstName {
    final n = _nameController.text.trim().split(RegExp(r'\s+')).first;
    return n.isEmpty ? 'your partner' : n;
  }

  /// Validates one step; returns an error message or null.
  String? _stepError(int step) {
    switch (step) {
      case 0:
        return _nameController.text.trim().length < 2 ? "Please enter partner's full name" : null;
      case 2:
        return _selectedDate == null ? "Please select partner's date of birth" : null;
      case 3:
        return _selectedTime == null && !_dontKnowTime
            ? 'Please select time of birth or tick "I don\'t know the exact time"'
            : null;
      case 4:
        return _placeController.text.trim().isEmpty ? "Please enter partner's place of birth" : null;
      default:
        return null;
    }
  }

  void _next() {
    final error = _stepError(_step);
    if (error != null) {
      setState(() => _errorText = error);
      return;
    }
    if (_step == _stepCount - 1) {
      _submitForm();
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _errorText = null;
      _forward = true;
      _step++;
    });
  }

  void _back() {
    if (_isSaving) return;
    if (_step == 0) {
      Navigator.pop(context);
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _errorText = null;
      _forward = false;
      _step--;
    });
  }

  Widget _stepHeader(IconData icon, String title, String subtitle) {
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.md, bottom: AppSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(color: AppColors.loveSoft, borderRadius: BorderRadius.circular(AppRadius.md)),
            child: Icon(icon, color: AppColors.love, size: 24),
          ),
          const SizedBox(height: AppSpacing.md),
          Text(title, style: AppText.headline),
          const SizedBox(height: 6),
          Text(subtitle, style: AppText.body),
        ],
      ),
    );
  }

  /// Large tappable tile used for the date and time answers.
  Widget _answerTile({
    required IconData icon,
    required String label,
    required String? value,
    required String placeholder,
    required VoidCallback onTap,
  }) {
    final has = value != null;
    return Semantics(
      button: true,
      label: '$label: ${value ?? 'not set'}',
      onTap: onTap,
      excludeSemantics: true,
      child: AppCard(
        onTap: onTap,
        color: has ? AppColors.primarySoft : AppColors.surface,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.lg),
        child: Row(
          children: [
            Icon(icon, color: has ? AppColors.primary : AppColors.textTertiary),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: AppText.caption),
                  const SizedBox(height: 2),
                  Text(
                    value ?? placeholder,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: has ? AppText.title : AppText.subtitle.copyWith(color: AppColors.textTertiary),
                  ),
                ],
              ),
            ),
            Icon(has ? Icons.edit_rounded : Icons.chevron_right_rounded, color: AppColors.textTertiary, size: 20),
          ],
        ),
      ),
    );
  }

  Widget _nameStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _stepHeader(Icons.favorite_rounded, "What's your partner's name?",
            "We'll work out their Moon chart and match it with yours."),
        TextField(
          controller: _nameController,
          autofocus: widget.initial == null,
          textCapitalization: TextCapitalization.words,
          textInputAction: TextInputAction.next,
          maxLength: 60,
          onChanged: (_) {
            if (_errorText != null) setState(() => _errorText = null);
          },
          onSubmitted: (_) => _next(),
          style: AppText.subtitle,
          decoration: const InputDecoration(
            labelText: 'Full name',
            hintText: 'e.g. Priya Sharma',
            counterText: '',
            prefixIcon: Icon(Icons.person_outline_rounded),
          ),
        ),
      ],
    );
  }

  Widget _genderStep() {
    const options = [
      ('Female', Icons.female_rounded),
      ('Male', Icons.male_rounded),
      ('Other', Icons.transgender_rounded),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _stepHeader(Icons.person_rounded, '$_partnerFirstName is…', 'Used for the right Guna Milan calculation.'),
        for (final (g, icon) in options) ...[
          _choiceCard(
            label: g,
            icon: icon,
            selected: _gender == g,
            onTap: () {
              setState(() => _gender = g);
              // Answering moves straight on, like a conversation.
              Future.delayed(const Duration(milliseconds: 200), () {
                if (mounted && _step == 1) _next();
              });
            },
          ),
          const SizedBox(height: AppSpacing.sm),
        ],
      ],
    );
  }

  Widget _choiceCard({
    required String label,
    required IconData icon,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      onTap: onTap,
      excludeSemantics: true,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        decoration: BoxDecoration(
          color: selected ? AppColors.primarySoft : AppColors.surface,
          borderRadius: AppRadius.card,
          border: Border.all(color: selected ? AppColors.primary : AppColors.border, width: selected ? 1.6 : 1),
        ),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            borderRadius: AppRadius.card,
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Row(
                children: [
                  Icon(icon, color: selected ? AppColors.primary : AppColors.textSecondary),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(child: Text(label, style: AppText.subtitle)),
                  Icon(
                    selected ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded,
                    color: selected ? AppColors.primary : AppColors.textTertiary,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _dateStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _stepHeader(Icons.cake_rounded, 'When was $_partnerFirstName born?',
            'Their birth date decides the Moon sign and nakshatra.'),
        _answerTile(
          icon: Icons.calendar_today_rounded,
          label: 'Date of birth',
          value: _selectedDate != null ? DateFormat('d MMMM yyyy').format(_selectedDate!) : null,
          placeholder: 'Tap to choose a date',
          onTap: () async {
            await _pickDate();
            if (mounted && _selectedDate != null && _errorText != null) setState(() => _errorText = null);
          },
        ),
      ],
    );
  }

  Widget _timeStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _stepHeader(Icons.schedule_rounded, 'What time was $_partnerFirstName born?',
            'An exact time makes the match more accurate. A rough time is fine too.'),
        _answerTile(
          icon: Icons.access_time_rounded,
          label: 'Time of birth',
          value: _dontKnowTime ? null : _selectedTime?.format(context),
          placeholder: 'Tap to choose a time',
          onTap: () async {
            await _pickTime();
            if (mounted && _selectedTime != null && _errorText != null) setState(() => _errorText = null);
          },
        ),
        const SizedBox(height: AppSpacing.sm),
        AppCard(
          color: _dontKnowTime ? AppColors.primarySoft : AppColors.surface,
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs, vertical: 2),
          child: CheckboxListTile(
            value: _dontKnowTime,
            onChanged: (v) => setState(() {
              _dontKnowTime = v ?? false;
              if (_dontKnowTime) _selectedTime = null;
              _errorText = null;
            }),
            activeColor: AppColors.primary,
            controlAffinity: ListTileControlAffinity.leading,
            title: const Text("I don't know the exact time", style: AppText.bodyStrong),
            subtitle: const Text("We'll use 12:00 noon; the Moon nakshatra may be approximate.", style: AppText.caption),
          ),
        ),
      ],
    );
  }

  Widget _placeStep(bool isLoggedIn) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _stepHeader(Icons.place_rounded, 'Where was $_partnerFirstName born?', 'Type the city and pick it from the list.'),
        TextField(
          controller: _placeController,
          onChanged: _onPlaceSearchChanged,
          textInputAction: TextInputAction.search,
          style: AppText.subtitle,
          decoration: InputDecoration(
            labelText: 'Place of birth',
            hintText: 'Search city (e.g. Delhi, Kathmandu)',
            prefixIcon: const Icon(Icons.location_on_outlined),
            suffixIcon: _isSearchingPlace
                ? const Padding(
                    padding: EdgeInsets.all(14),
                    child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                  )
                : (_latitude != null ? const Icon(Icons.check_circle_rounded, color: AppColors.success) : null),
          ),
        ),
        if (_latitude != null && _longitude != null)
          Padding(
            padding: const EdgeInsets.only(top: 6, left: 4),
            child: Row(children: [
              const Icon(Icons.check_rounded, size: 16, color: AppColors.success),
              const SizedBox(width: 4),
              Text('Location found', style: AppText.caption.copyWith(color: AppColors.success)),
            ]),
          ),
        if (_placeSuggestions.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.xs),
          AppCard(
            padding: EdgeInsets.zero,
            shadow: true,
            child: Column(
              children: [
                for (var i = 0; i < _placeSuggestions.length; i++) ...[
                  if (i > 0) const Divider(),
                  ListTile(
                    leading: const Icon(Icons.location_on_outlined, size: 20),
                    title: Text(
                      _placeSuggestions[i].fullDisplayName,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.body.copyWith(color: AppColors.textPrimary),
                    ),
                    onTap: () => _selectSuggestion(_placeSuggestions[i]),
                  ),
                ],
              ],
            ),
          ),
        ],
        if (isLoggedIn && _placeSuggestions.isEmpty) ...[
          const SizedBox(height: AppSpacing.md),
          AppCard(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs, vertical: 2),
            child: CheckboxListTile(
              value: _saveToFamily,
              onChanged: _isSaving ? null : (v) => setState(() => _saveToFamily = v ?? false),
              activeColor: AppColors.primary,
              controlAffinity: ListTileControlAffinity.leading,
              title: const Text('Save to Family Profiles', style: AppText.bodyStrong),
              subtitle: const Text('Gives an exact Moon chart for an accurate match.', style: AppText.caption),
            ),
          ),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final isLoggedIn = Provider.of<BackendService>(context, listen: false).isAuthenticated;
    final reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final isLast = _step == _stepCount - 1;

    final Widget body = switch (_step) {
      0 => _nameStep(),
      1 => _genderStep(),
      2 => _dateStep(),
      3 => _timeStep(),
      _ => _placeStep(isLoggedIn),
    };

    return PopScope(
      // System back steps back through the questions before closing.
      canPop: _step == 0 && !_isSaving,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _back();
      },
      child: SizedBox(
        height: (media.size.height - media.viewInsets.bottom) * 0.85,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header: back / close, progress.
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Row(
                children: [
                  IconButton(
                    tooltip: _step == 0 ? 'Close' : 'Back',
                    icon: Icon(_step == 0 ? Icons.close_rounded : Icons.arrow_back_rounded,
                        color: AppColors.textPrimary),
                    onPressed: _isSaving ? null : _back,
                  ),
                  Expanded(
                    child: Column(
                      children: [
                        Text('Partner details · Step ${_step + 1} of $_stepCount',
                            maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.caption),
                        const SizedBox(height: 6),
                        TweenAnimationBuilder<double>(
                          tween: Tween(end: (_step + 1) / _stepCount),
                          duration: reduceMotion ? Duration.zero : const Duration(milliseconds: 250),
                          builder: (context, v, _) => ClipRRect(
                            borderRadius: BorderRadius.circular(2),
                            child: LinearProgressIndicator(
                              value: v,
                              minHeight: 4,
                              backgroundColor: AppColors.surfaceMuted,
                              color: AppColors.primary,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 48),
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                padding: const EdgeInsets.fromLTRB(AppSpacing.page, 0, AppSpacing.page, AppSpacing.md),
                child: AnimatedSwitcher(
                  duration: reduceMotion ? Duration.zero : const Duration(milliseconds: 220),
                  transitionBuilder: (child, anim) {
                    final incoming = child.key == ValueKey(_step);
                    final dx = incoming == _forward ? 0.08 : -0.08;
                    return FadeTransition(
                      opacity: anim,
                      child: SlideTransition(
                        position: Tween(begin: Offset(dx, 0), end: Offset.zero).animate(anim),
                        child: child,
                      ),
                    );
                  },
                  layoutBuilder: (current, previous) => Stack(
                    alignment: Alignment.topCenter,
                    children: [...previous, if (current != null) current],
                  ),
                  child: KeyedSubtree(key: ValueKey(_step), child: body),
                ),
              ),
            ),
            // Sticky footer: error + next / submit.
            DecoratedBox(
              decoration: const BoxDecoration(
                color: AppColors.surface,
                border: Border(top: BorderSide(color: AppColors.divider)),
              ),
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                    AppSpacing.page, AppSpacing.sm, AppSpacing.page, AppSpacing.sm + media.padding.bottom),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (_errorText != null) ...[
                      Container(
                        padding: const EdgeInsets.all(AppSpacing.sm),
                        decoration: BoxDecoration(
                          color: AppColors.dangerSoft,
                          borderRadius: BorderRadius.circular(AppRadius.md),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(Icons.error_outline_rounded, color: AppColors.danger, size: 18),
                            const SizedBox(width: AppSpacing.xs),
                            Expanded(
                              child: Text(_errorText!, style: AppText.body.copyWith(color: AppColors.danger)),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: AppSpacing.sm),
                    ],
                    AppButton(
                      label: isLast ? 'Save & check match' : 'Next',
                      icon: isLast ? Icons.favorite_rounded : null,
                      loading: _isSaving,
                      onPressed: _isSaving ? null : _next,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
