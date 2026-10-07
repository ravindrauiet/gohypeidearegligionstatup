import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../services/backend_service.dart';
import '../../services/city_autocomplete_service.dart';

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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final s = Provider.of<BackendService>(context, listen: false);
      if (s.isAuthenticated && s.familyMembers.isEmpty) s.fetchFamilyKundlis();
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

    return Scaffold(
      backgroundColor: const Color(0xFFFCF7F1),
      appBar: AppBar(
        backgroundColor: const Color(0xFFFCF7F1),
        elevation: 0,
        automaticallyImplyLeading: false,
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                'Ashtakoot 36-Guna Milan',
                style: TextStyle(
                  color: Colors.black,
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            Text(
              'Vedic Moon-chart compatibility',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: Color(0xFFE83D66),
                fontSize: 11,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        actions: [
          Container(
            margin: const EdgeInsets.only(right: 16),
            decoration: BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.grey.shade300),
            ),
            child: IconButton(
              tooltip: 'About Guna Milan',
              icon: const Icon(Icons.info_outline_rounded, color: Colors.black, size: 20),
              onPressed: () => _showInfoDialog(context),
            ),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildDailyLoveTransitBanner(),
            const SizedBox(height: 16),

            if (kundli == null || userMoon == null) ...[
              _buildMissingBirthDetailsCard(),
              const SizedBox(height: 16),
            ],

            if (familyMembers.isNotEmpty) ...[
              _buildSavedFamilyProfilesSelector(familyMembers),
              const SizedBox(height: 16),
            ],

            // Interactive Synastry Partner Card (Connecting Orbits)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 10),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: Colors.black.withValues(alpha: 0.06)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.04),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: LayoutBuilder(builder: (context, constraints) {
                final bubbleWidth = ((constraints.maxWidth - 64) / 2).clamp(96.0, 130.0);
                return SizedBox(
                  height: 220,
                  width: double.infinity,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      CustomPaint(
                        size: Size(constraints.maxWidth, 180),
                        painter: DashedOrbitalArcPainter(),
                      ),
                      Positioned(
                        left: 4,
                        top: 4,
                        child: _buildProfileBubble(
                          width: bubbleWidth,
                          title: 'Person 1 (Self)',
                          name: userName,
                          sign: userMoon != null ? '$userMoon Moon' : 'Add birth details',
                          hasProfile: true,
                          onTap: userMoon == null ? () => Navigator.pushNamed(context, '/birth-details') : null,
                        ),
                      ),
                      Positioned(
                        right: 4,
                        bottom: 4,
                        child: _buildProfileBubble(
                          width: bubbleWidth,
                          title: 'Person 2 (Partner)',
                          name: partner?.name ?? 'Add Partner',
                          sign: partner != null
                              ? (partner.kundli?['moonSign'] != null
                                  ? '${partner.kundli!['moonSign']} Moon'
                                  : DateFormat('dd MMM yyyy').format(_parseDate(partner.dob) ?? DateTime.now()))
                              : 'Tap to add',
                          hasProfile: partner != null,
                          onTap: _showAddPartnerDialog,
                        ),
                      ),
                      Container(
                        width: 48,
                        height: 48,
                        decoration: const BoxDecoration(
                          color: Color(0xFFE83D66),
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: Color(0x66E83D66),
                              blurRadius: 16,
                              offset: Offset(0, 4),
                            ),
                          ],
                        ),
                        child: const Icon(Icons.favorite_rounded, color: Colors.white, size: 26),
                      ),
                    ],
                  ),
                );
              }),
            ),

            const SizedBox(height: 20),

            // Match Calculation Button
            SizedBox(
              height: 56,
              child: ElevatedButton(
                onPressed: _isMatching ? null : _calculateSynastryMatch,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.black,
                  disabledBackgroundColor: Colors.black54,
                  elevation: 4,
                  shadowColor: Colors.black38,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                ),
                child: _isMatching
                    ? const SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5),
                      )
                    : Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.auto_awesome_rounded, color: Color(0xFFFFD700), size: 22),
                          const SizedBox(width: 10),
                          Flexible(
                            child: Text(
                              partner == null ? 'Add Partner to Match' : 'Calculate 36-Guna Milan',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
              ),
            ),

            if (_matchNeedsBirthDetails && !_isMatching) ...[
              const SizedBox(height: 16),
              _buildMissingBirthDetailsCard(),
            ] else if (_matchError != null && !_isMatching) ...[
              const SizedBox(height: 16),
              _buildErrorCard(_matchError!),
            ],

            // Dynamic Results Section
            if (_synastryData != null) ..._buildResults(userName, partner?.name ?? 'Partner'),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildResults(String userName, String partnerName) {
    final data = _synastryData!;
    return [
      const SizedBox(height: 24),
      if (!_isExactCalculation) ...[
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFFFFF8E1),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFFFFB74D)),
          ),
          child: const Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.info_outline_rounded, color: Color(0xFFD97706), size: 18),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'AI estimate: the partner\'s exact Moon chart is not available. Save the partner to Family Profiles '
                  '(or select a saved profile) for an exact Ashtakoot calculation.',
                  style: TextStyle(fontSize: 12, color: Color(0xFF8D5A00), height: 1.35),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
      ],
      _buildScoreHero(data),
      const SizedBox(height: 20),
      _buildPlanetarySynastryGrid(data['planetarySynastry']),
      const SizedBox(height: 20),
      _buildAshtakootTableWidget(data['ashtakoot']),
      const SizedBox(height: 20),
      _buildManglikCheckCard(data['manglikCheck']),
      const SizedBox(height: 20),
      _buildNadiBhakootCard(data['nadiBhakootAnalysis']),
      const SizedBox(height: 20),
      _buildRelationshipReportCards((data['relationshipReport'] ?? data['summary'] ?? '').toString()),
      const SizedBox(height: 20),
      _buildShareButton(userName, partnerName),
      const SizedBox(height: 16),
      _buildAskAstrologerButton(userName, partnerName),
    ];
  }

  Widget _buildMissingBirthDetailsCard() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE83D66).withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          const Icon(Icons.edit_calendar_rounded, color: Color(0xFFE83D66)),
          const SizedBox(width: 10),
          const Expanded(
            child: Text(
              'Add your birth details to get an exact Guna Milan based on your Moon chart.',
              style: TextStyle(fontSize: 12, color: Colors.black87),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pushNamed(context, '/birth-details'),
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorCard(String message) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFFEBEE),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline_rounded, color: Colors.redAccent),
          const SizedBox(width: 10),
          Expanded(child: Text(message, style: const TextStyle(fontSize: 13, color: Color(0xFFB71C1C)))),
          TextButton(onPressed: _calculateSynastryMatch, child: const Text('Retry')),
        ],
      ),
    );
  }

  Widget _buildScoreHero(Map<String, dynamic> data) {
    final score = data['score'] ?? 0;
    final gunaTotal = data['gunaTotal'];
    final gunasText = data['gunas']?.toString() ?? (gunaTotal != null ? '${_fmtScore(gunaTotal)} / 36 Gunas' : '');
    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF1E1A38), Color(0xFF2E2452)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      padding: const EdgeInsets.all(18),
      child: Row(
        children: [
          Container(
            width: 76,
            height: 76,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: const Color(0xFFFFD700).withValues(alpha: 0.15),
              border: Border.all(color: const Color(0xFFFFD700), width: 2.5),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                FittedBox(
                  child: Text(
                    '$score%',
                    style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: Color(0xFFFFD700)),
                  ),
                ),
                const Text(
                  'MATCH',
                  style: TextStyle(fontSize: 9, fontWeight: FontWeight.w800, color: Colors.white70, letterSpacing: 0.8),
                ),
              ],
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    'ASHTAKOOT: $gunasText',
                    style: const TextStyle(
                        fontSize: 11, fontWeight: FontWeight.w800, color: Color(0xFFFFD700), letterSpacing: 0.6),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  data['verdict']?.toString() ?? '',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white, height: 1.2),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // Daily Love Transit Banner Widget
  Widget _buildDailyLoveTransitBanner() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFFFF0F3), Color(0xFFFDE8ED)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE83D66).withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: const BoxDecoration(color: Color(0xFFE83D66), shape: BoxShape.circle),
            child: const Icon(Icons.wb_twilight_rounded, color: Colors.white, size: 20),
          ),
          const SizedBox(width: 14),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Kundli Milan in 3 steps',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFFB02246)),
                ),
                SizedBox(height: 2),
                Text(
                  'Pick a saved profile or add partner birth details, then calculate all 8 Kootas out of 36.',
                  style: TextStyle(fontSize: 11, color: Colors.black87),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // Saved Family Profiles Carousel Widget
  Widget _buildSavedFamilyProfilesSelector(List<Map<String, dynamic>> familyMembers) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Row(
          children: [
            Expanded(
              child: Text(
                'Select Person 2 from Saved Profiles:',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.black87),
              ),
            ),
            Icon(Icons.swipe_left_rounded, size: 16, color: Colors.grey),
          ],
        ),
        const SizedBox(height: 8),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: familyMembers.map((member) {
              final name = (member['fullName'] ?? member['name'] ?? 'Family').toString();
              final rel = (member['relationship'] ?? 'Member').toString();
              final id = member['id']?.toString();
              final isSelected = _partner != null && id != null && _partner!.familyId == id;

              return Padding(
                padding: const EdgeInsets.only(right: 8.0),
                child: ChoiceChip(
                  avatar: CircleAvatar(
                    backgroundColor: isSelected ? Colors.white : const Color(0xFFE83D66).withValues(alpha: 0.12),
                    child: Text(
                      name.isNotEmpty ? name[0].toUpperCase() : '?',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: isSelected ? const Color(0xFFE83D66) : Colors.black,
                      ),
                    ),
                  ),
                  label: Text('$name ($rel)'),
                  selected: isSelected,
                  showCheckmark: false,
                  selectedColor: const Color(0xFFE83D66),
                  backgroundColor: Colors.white,
                  labelStyle: TextStyle(
                    color: isSelected ? Colors.white : Colors.black,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                    side: BorderSide(color: isSelected ? const Color(0xFFE83D66) : Colors.grey.shade300),
                  ),
                  onSelected: _isMatching
                      ? null
                      : (_) {
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
                        },
                ),
              );
            }).toList(),
          ),
        ),
      ],
    );
  }

  Widget _sectionTitle(IconData icon, Color color, String title) {
    return Row(
      children: [
        Icon(icon, color: color, size: 22),
        const SizedBox(width: 10),
        Expanded(
          child: Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.black)),
        ),
      ],
    );
  }

  // Side-by-Side Planetary Synastry Grid Widget
  Widget _buildPlanetarySynastryGrid(dynamic synastryList) {
    final List list = synastryList is List ? synastryList : const [];
    if (list.isEmpty) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle(Icons.stars_rounded, const Color(0xFFFF9800), 'Planetary Synastry Grid'),
          const SizedBox(height: 4),
          Text(
            'Sign-to-sign alignment of Sun, Moon, Venus & Mars:',
            style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
          ),
          const SizedBox(height: 16),
          ...list.whereType<Map>().map((item) {
            final planet = item['planet']?.toString() ?? 'Planet';
            final p1 = item['p1Sign']?.toString() ?? '—';
            final p2 = item['p2Sign']?.toString() ?? '—';
            final align = item['alignment']?.toString() ?? '';
            final verdict = item['verdict']?.toString() ?? '';

            return Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFFCF7F1),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    alignment: WrapAlignment.spaceBetween,
                    spacing: 8,
                    runSpacing: 4,
                    children: [
                      Text(planet,
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.black)),
                      if (align.isNotEmpty)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFF9800).withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(align,
                              style:
                                  const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFFD97706))),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: Text('Person 1: $p1',
                            style:
                                TextStyle(fontSize: 12, color: Colors.grey.shade800, fontWeight: FontWeight.w600)),
                      ),
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 4),
                        child: Icon(Icons.compare_arrows_rounded, size: 16, color: Colors.grey),
                      ),
                      Expanded(
                        child: Text('Person 2: $p2',
                            textAlign: TextAlign.end,
                            style:
                                TextStyle(fontSize: 12, color: Colors.grey.shade800, fontWeight: FontWeight.w600)),
                      ),
                    ],
                  ),
                  if (verdict.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      verdict,
                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF059669)),
                    ),
                  ],
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  // Ashtakoot 8-Guna Breakdown Table Widget
  Widget _buildAshtakootTableWidget(dynamic ashtakootData) {
    final List list = ashtakootData is List ? ashtakootData : const [];
    if (list.isEmpty) return const SizedBox.shrink();

    double total = 0;
    for (final item in list.whereType<Map>()) {
      total += double.tryParse(item['score']?.toString() ?? '') ?? 0;
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle(Icons.table_chart_rounded, const Color(0xFF6C63FF), 'Ashtakoot 8-Guna Breakdown'),
          const SizedBox(height: 4),
          Text(
            'Total: ${_fmtScore(total)} of 36 points',
            style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
          ),
          const SizedBox(height: 16),
          ...list.whereType<Map>().map((item) {
            final String name = item['name']?.toString() ?? 'Guna';
            final double score = double.tryParse(item['score']?.toString() ?? '') ?? 0;
            final double max = double.tryParse(item['max']?.toString() ?? '') ?? 1;
            final String meaning = item['meaning']?.toString() ?? '';
            final String verdict = item['verdict']?.toString() ?? '';
            final double pct = max <= 0 ? 0 : (score / max).clamp(0.0, 1.0);
            final Color barColor = pct >= 0.75
                ? const Color(0xFF059669)
                : (pct >= 0.4 ? const Color(0xFF6C63FF) : const Color(0xFFE53935));

            return Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFFCF7F1),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text.rich(
                          TextSpan(children: [
                            TextSpan(
                              text: name,
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.black),
                            ),
                            if (meaning.isNotEmpty)
                              TextSpan(
                                text: '  ($meaning)',
                                style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                              ),
                          ]),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(color: barColor, borderRadius: BorderRadius.circular(8)),
                        child: Text(
                          '${_fmtScore(score)} / ${_fmtScore(max)}',
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: LinearProgressIndicator(
                      value: pct,
                      backgroundColor: Colors.grey.shade300,
                      color: barColor,
                      minHeight: 6,
                    ),
                  ),
                  if (verdict.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(
                      verdict,
                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFFD95D39)),
                    ),
                  ],
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  // Manglik Dosha Check Card Widget
  Widget _buildManglikCheckCard(dynamic manglikData) {
    if (manglikData is! Map) return const SizedBox.shrink();
    final m = manglikData;

    Widget statusBox(String label, String value) {
      return Expanded(
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: const Color(0xFFFFF0F3), borderRadius: BorderRadius.circular(12)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: const TextStyle(fontSize: 11, color: Colors.grey, fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              Text(value, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.black)),
            ],
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE83D66).withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle(Icons.shield_outlined, const Color(0xFFE83D66), 'Manglik Dosha Check'),
          const SizedBox(height: 14),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              statusBox('Person 1', m['person1Status']?.toString() ?? 'Unknown'),
              const SizedBox(width: 10),
              statusBox('Person 2', m['person2Status']?.toString() ?? 'Unknown'),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFE83D66).withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.check_circle_outline_rounded, color: Color(0xFFE83D66), size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    m['manglikVerdict']?.toString() ?? '',
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFFB02246)),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // Nadi & Bhakoot Compatibility Card Widget
  Widget _buildNadiBhakootCard(dynamic nbData) {
    if (nbData is! Map) return const SizedBox.shrink();
    final nb = nbData;

    Widget block(Color color, String title, String body) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withValues(alpha: 0.2)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.verified_rounded, color: color, size: 16),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(title, style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: color)),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(body, style: const TextStyle(fontSize: 13, color: Colors.black87, height: 1.4)),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle(Icons.favorite_outline_rounded, const Color(0xFF9C27B0), 'Nadi & Bhakoot Analysis'),
          const SizedBox(height: 14),
          block(const Color(0xFF9C27B0), 'NADI COMPATIBILITY (8 PTS)', nb['nadiVerdict']?.toString() ?? ''),
          const SizedBox(height: 10),
          block(const Color(0xFF317BEA), 'BHAKOOT COMPATIBILITY (7 PTS)', nb['bhakootVerdict']?.toString() ?? ''),
        ],
      ),
    );
  }

  // Relationship Guidance Report Cards
  Widget _buildRelationshipReportCards(String reportText) {
    if (reportText.trim().isEmpty) return const SizedBox.shrink();
    final List<String> blocks = reportText.split('###').where((b) => b.trim().isNotEmpty).toList();

    if (blocks.length <= 1 && !reportText.contains('###')) {
      return Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.grey.shade200),
        ),
        child: SelectableText.rich(TextSpan(children: _parseFormattedSpans(reportText.trim()))),
      );
    }

    return Column(
      children: blocks.map((block) {
        final lines = block.trim().split('\n');
        final titleLine = lines.first.trim();
        final bodyText = lines.sublist(1).join('\n').trim();

        Color cardColor = const Color(0xFFE83D66);
        IconData icon = Icons.favorite_rounded;
        if (titleLine.contains('Marriage') || titleLine.contains('Longevity')) {
          cardColor = const Color(0xFF9C27B0);
          icon = Icons.workspace_premium_rounded;
        } else if (titleLine.contains('Remed') || titleLine.contains('Guidance')) {
          cardColor = const Color(0xFFD95D39);
          icon = Icons.spa_rounded;
        }

        return Container(
          margin: const EdgeInsets.only(bottom: 16),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: cardColor.withValues(alpha: 0.25)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(color: cardColor.withValues(alpha: 0.12), shape: BoxShape.circle),
                    child: Icon(icon, color: cardColor, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      titleLine,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.black.withValues(alpha: 0.85),
                      ),
                    ),
                  ),
                ],
              ),
              if (bodyText.isNotEmpty) ...[
                const SizedBox(height: 12),
                const Divider(height: 1),
                const SizedBox(height: 12),
                SelectableText.rich(TextSpan(children: _parseFormattedSpans(bodyText))),
              ],
            ],
          ),
        );
      }).toList(),
    );
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

  // Share Guna Milan summary
  Widget _buildShareButton(String p1, String p2) {
    return SizedBox(
      height: 52,
      child: OutlinedButton.icon(
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
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Match summary copied to clipboard')),
          );
        },
        icon: const Icon(Icons.share_rounded, color: Color(0xFF6C63FF)),
        label: const Text(
          'Share Guna Milan Result',
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Color(0xFF6C63FF)),
        ),
        style: OutlinedButton.styleFrom(
          side: const BorderSide(color: Color(0xFF6C63FF), width: 1.5),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
      ),
    );
  }

  // 1-Tap "Ask Relationship Astrologer About This Match" Button Widget
  Widget _buildAskAstrologerButton(String p1, String p2) {
    return SizedBox(
      height: 56,
      child: ElevatedButton.icon(
        onPressed: () {
          final d = _synastryData ?? const {};
          final partner = _partner;
          final kootas = (d['ashtakoot'] is List)
              ? (d['ashtakoot'] as List).whereType<Map>().map((k) => '${k['name']} ${k['score']}/${k['max']}').join(', ')
              : '';
          Navigator.pushNamed(context, '/chatbot', arguments: {
            'name': 'Vedic Love Specialist',
            'specialty': 'Guna Milan & Synastry',
            'field': 'Marriage Consultation',
            'initialMessage': 'Please give relationship guidance for $p1 and $p2'
                '${partner != null ? ' (partner born ${partner.dob} at ${partner.tob}, ${partner.pob})' : ''}. '
                'Our Ashtakoot Guna Milan is ${d['gunas'] ?? ''}${kootas.isNotEmpty ? ' ($kootas)' : ''}. '
                'What are the strengths, challenges and remedies?',
          });
        },
        icon: const Icon(Icons.chat_bubble_outline_rounded, color: Colors.white),
        label: const FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            'Ask Love Astrologer About This Match',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white),
          ),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.black,
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        ),
      ),
    );
  }

  List<TextSpan> _parseFormattedSpans(String text) {
    final List<TextSpan> spans = [];
    final RegExp exp = RegExp(r'\*\*(.*?)\*\*');
    int start = 0;

    for (final Match match in exp.allMatches(text)) {
      if (match.start > start) {
        spans.add(TextSpan(
          text: text.substring(start, match.start),
          style: const TextStyle(color: Color(0xFF2D3748), fontSize: 14, height: 1.6),
        ));
      }
      spans.add(TextSpan(
        text: match.group(1),
        style: const TextStyle(color: Colors.black, fontWeight: FontWeight.w900, fontSize: 14, height: 1.6),
      ));
      start = match.end;
    }

    if (start < text.length) {
      spans.add(TextSpan(
        text: text.substring(start),
        style: const TextStyle(color: Color(0xFF2D3748), fontSize: 14, height: 1.6),
      ));
    }
    return spans;
  }

  Widget _buildProfileBubble({
    required double width,
    required String title,
    required String name,
    required String sign,
    required bool hasProfile,
    VoidCallback? onTap,
  }) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(20),
      elevation: 2,
      shadowColor: Colors.black12,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Container(
          width: width,
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.black.withValues(alpha: 0.08)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey.shade600),
              ),
              const SizedBox(height: 8),
              Container(
                width: 44,
                height: 44,
                decoration: const BoxDecoration(color: Color(0xFFFFF0F3), shape: BoxShape.circle),
                child: Center(
                  child: hasProfile
                      ? Text(name.isNotEmpty ? name[0].toUpperCase() : 'P',
                          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Color(0xFFE83D66)))
                      : const Icon(Icons.add, color: Color(0xFFE83D66), size: 24),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                name,
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.black),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 2),
              Text(
                sign,
                style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showAddPartnerDialog() async {
    if (_isMatching) return;
    final result = await showModalBottomSheet<PartnerInfo>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
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
        backgroundColor: const Color(0xFFFCF7F1),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('What is Ashtakoot 36 Guna Milan?'),
        content: const SingleChildScrollView(
          child: Text(
            'Ashtakoot Guna Milan compares the Moon sign and Moon nakshatra of both partners across 8 kootas: '
            'Varna (1), Vashya (2), Tara (3), Yoni (4), Graha Maitri (5), Gana (6), Bhakoot (7) and Nadi (8) — 36 points in total.\n\n'
            '18+ Gunas is traditionally considered acceptable, 25+ very good and 33+ excellent. '
            'Select a saved family profile (or save the partner as one) so both Moon charts are calculated exactly.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Got It', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }
}

class DashedOrbitalArcPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFFE83D66).withValues(alpha: 0.3)
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;

    final path = Path()
      ..moveTo(40, size.height * 0.3)
      ..cubicTo(
        size.width * 0.3,
        size.height * 0.1,
        size.width * 0.7,
        size.height * 0.9,
        size.width - 40,
        size.height * 0.7,
      );

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

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

  InputDecoration _decoration(String hint, {Widget? prefixIcon, Widget? suffixIcon}) => InputDecoration(
        hintText: hint,
        filled: true,
        fillColor: Colors.white,
        counterText: '',
        prefixIcon: prefixIcon,
        suffixIcon: suffixIcon,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
      );

  Widget _label(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(text, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
      );

  Widget _pickerTile({required String text, required IconData icon, required bool enabled, required VoidCallback onTap}) {
    return Material(
      color: enabled ? Colors.white : Colors.grey.shade100,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  text,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                    color: enabled ? Colors.black : Colors.grey,
                  ),
                ),
              ),
              Icon(icon, color: enabled ? const Color(0xFFE83D66) : Colors.grey, size: 20),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final isLoggedIn = Provider.of<BackendService>(context, listen: false).isAuthenticated;

    return Padding(
      padding: EdgeInsets.only(bottom: media.viewInsets.bottom),
      child: Container(
        height: (media.size.height - media.viewInsets.bottom) * 0.9,
        padding: EdgeInsets.fromLTRB(20, 12, 20, 16 + media.padding.bottom),
        decoration: const BoxDecoration(
          color: Color(0xFFFCF7F1),
          borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Partner Birth Details',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.black),
                  ),
                ),
                IconButton(
                  tooltip: 'Close',
                  icon: const Icon(Icons.close, color: Colors.black54),
                  onPressed: _isSaving ? null : () => Navigator.pop(context),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Expanded(
              child: SingleChildScrollView(
                keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _label('Full Name'),
                    TextField(
                      controller: _nameController,
                      textCapitalization: TextCapitalization.words,
                      maxLength: 60,
                      onChanged: (_) {
                        if (_errorText != null) setState(() => _errorText = null);
                      },
                      decoration: _decoration('Enter partner\'s full name'),
                    ),
                    const SizedBox(height: 16),
                    _label('Gender'),
                    Wrap(
                      spacing: 10,
                      children: ['Female', 'Male', 'Other'].map((g) {
                        final isSelected = _gender == g;
                        return ChoiceChip(
                          label: Text(g),
                          selected: isSelected,
                          showCheckmark: false,
                          selectedColor: const Color(0xFFE83D66),
                          backgroundColor: Colors.white,
                          labelStyle: TextStyle(
                            color: isSelected ? Colors.white : Colors.black,
                            fontWeight: FontWeight.bold,
                          ),
                          onSelected: (_) => setState(() => _gender = g),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _label('Date of Birth'),
                              _pickerTile(
                                text: _selectedDate != null
                                    ? DateFormat('dd MMM yyyy').format(_selectedDate!)
                                    : 'Select date',
                                icon: Icons.calendar_today_rounded,
                                enabled: true,
                                onTap: _pickDate,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _label('Time of Birth'),
                              _pickerTile(
                                text: _dontKnowTime
                                    ? 'Unknown'
                                    : (_selectedTime != null ? _selectedTime!.format(context) : 'Select time'),
                                icon: Icons.access_time_rounded,
                                enabled: !_dontKnowTime,
                                onTap: _pickTime,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    CheckboxListTile(
                      value: _dontKnowTime,
                      onChanged: (v) => setState(() {
                        _dontKnowTime = v ?? false;
                        _errorText = null;
                      }),
                      activeColor: const Color(0xFFE83D66),
                      contentPadding: EdgeInsets.zero,
                      controlAffinity: ListTileControlAffinity.leading,
                      title: const Text("I don't know the exact time of birth", style: TextStyle(fontSize: 13)),
                      subtitle: _dontKnowTime
                          ? const Text('12:00 noon will be used; Moon nakshatra may be approximate.',
                              style: TextStyle(fontSize: 11))
                          : null,
                    ),
                    const SizedBox(height: 8),
                    _label('Place of Birth'),
                    TextField(
                      controller: _placeController,
                      onChanged: _onPlaceSearchChanged,
                      textInputAction: TextInputAction.search,
                      decoration: _decoration(
                        'Search city or pincode',
                        prefixIcon: const Icon(Icons.search, color: Colors.grey),
                        suffixIcon: _isSearchingPlace
                            ? const Padding(
                                padding: EdgeInsets.all(12),
                                child: SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFFE83D66)),
                                ),
                              )
                            : (_latitude != null
                                ? const Icon(Icons.check_circle_rounded, color: Color(0xFF059669))
                                : null),
                      ),
                    ),
                    if (_latitude != null && _longitude != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(
                          'Coordinates: ${_latitude!.toStringAsFixed(4)}, ${_longitude!.toStringAsFixed(4)}',
                          style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                        ),
                      ),
                    if (_placeSuggestions.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Container(
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: Colors.black.withValues(alpha: 0.1)),
                        ),
                        child: ListView.separated(
                          shrinkWrap: true,
                          padding: EdgeInsets.zero,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: _placeSuggestions.length,
                          separatorBuilder: (context, index) => const Divider(height: 1),
                          itemBuilder: (context, index) {
                            final suggestion = _placeSuggestions[index];
                            return Material(
                              color: Colors.transparent,
                              child: ListTile(
                                leading: const Icon(Icons.location_on_outlined, size: 20, color: Colors.black),
                                title: Text(suggestion.fullDisplayName,
                                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                                onTap: () => _selectSuggestion(suggestion),
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                    const SizedBox(height: 12),
                    if (isLoggedIn)
                      CheckboxListTile(
                        value: _saveToFamily,
                        onChanged: _isSaving ? null : (v) => setState(() => _saveToFamily = v ?? false),
                        activeColor: const Color(0xFFE83D66),
                        contentPadding: EdgeInsets.zero,
                        controlAffinity: ListTileControlAffinity.leading,
                        title: const Text('Save to Family Profiles', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                        subtitle: const Text('Calculates the partner\'s exact Moon chart for an accurate Guna Milan.',
                            style: TextStyle(fontSize: 11)),
                      ),
                  ],
                ),
              ),
            ),
            if (_errorText != null)
              Container(
                width: double.infinity,
                margin: const EdgeInsets.only(top: 8),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: const Color(0xFFFFEBEE), borderRadius: BorderRadius.circular(12)),
                child: Text(_errorText!, style: const TextStyle(color: Color(0xFFB71C1C), fontSize: 13)),
              ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              height: 54,
              child: ElevatedButton(
                onPressed: _isSaving ? null : _submitForm,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFE83D66),
                  disabledBackgroundColor: const Color(0x99E83D66),
                  elevation: 0,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                ),
                child: _isSaving
                    ? const SizedBox(
                        width: 22, height: 22, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : const FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          'Save & Calculate 36-Guna Match',
                          style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
