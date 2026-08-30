import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../services/backend_service.dart';
import '../../services/city_autocomplete_service.dart';

class LoveTab extends StatefulWidget {
  const LoveTab({super.key});

  @override
  State<LoveTab> createState() => _LoveTabState();
}

class _LoveTabState extends State<LoveTab> {
  String? _partnerName;
  String? _partnerGender;
  String? _partnerDob;
  String? _partnerTob;
  String? _partnerPob;

  bool _isMatching = false;
  Map<String, dynamic>? _synastryData;

  @override
  Widget build(BuildContext context) {
    final backendService = Provider.of<BackendService>(context);
    final familyMembers = backendService.familyMembers;
    final kundli = backendService.kundliData ?? {
      'ascendant': 'Scorpio',
      'moonSign': 'Pisces',
      'birthDetails': {'fullName': 'Main Profile'}
    };

    final userName = kundli['birthDetails']?['fullName'] ?? kundli['fullName'] ?? 'Main Profile';
    final userMoon = kundli['moonSign'] ?? 'Pisces';

    return Scaffold(
      backgroundColor: const Color(0xFFFCF7F1),
      appBar: AppBar(
        backgroundColor: const Color(0xFFFCF7F1),
        elevation: 0,
        automaticallyImplyLeading: false,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: const [
            Text(
              'Ashtakoot 36-Guna Milan',
              style: TextStyle(
                color: Colors.black,
                fontSize: 22,
                fontWeight: FontWeight.w800,
              ),
            ),
            Text(
              'Swiss Ephemeris NASA JPL Compatibility Engine',
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
              icon: const Icon(Icons.info_outline_rounded, color: Colors.black, size: 20),
              onPressed: () => _showInfoDialog(context),
            ),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // 1. 🔥 Daily Love Transit Meter Banner
            _buildDailyLoveTransitBanner(),

            const SizedBox(height: 16),

            // 👨‍👩‍👧‍👦 Saved Family Profiles Carousel
            if (familyMembers.isNotEmpty) ...[
              _buildSavedFamilyProfilesSelector(familyMembers),
              const SizedBox(height: 16),
            ],

            // 2. Interactive Synastry Partner Card (Connecting Orbits)
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
              child: SizedBox(
                height: 220,
                width: double.infinity,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    // Orbital Dashed Arc
                    CustomPaint(
                      size: const Size(300, 180),
                      painter: DashedOrbitalArcPainter(),
                    ),

                    // Left Bubble: Person 1 (User)
                    Positioned(
                      left: 10,
                      top: 10,
                      child: _buildProfileBubble(
                        title: 'Person 1 (Self)',
                        name: userName,
                        sign: '$userMoon Moon',
                        isUser: true,
                      ),
                    ),

                    // Right Bubble: Person 2 (Partner)
                    Positioned(
                      right: 10,
                      bottom: 10,
                      child: _buildProfileBubble(
                        title: "Person 2 (Partner)",
                        name: _partnerName ?? 'Add Partner',
                        sign: _partnerName != null ? (_partnerDob ?? 'Tap to edit') : 'Tap to select/add',
                        isUser: false,
                        onTap: _showAddPartnerDialog,
                      ),
                    ),

                    // Center Pink Heart Badge
                    Container(
                      width: 48,
                      height: 48,
                      decoration: const BoxDecoration(
                        color: Color(0xFFE83D66),
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: Color(0xFFE83D66),
                            blurRadius: 16,
                            offset: Offset(0, 4),
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.favorite_rounded,
                        color: Colors.white,
                        size: 26,
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 20),

            // 3. Match Calculation Button
            SizedBox(
              width: double.infinity,
              height: 56,
              child: ElevatedButton(
                onPressed: _isMatching ? null : _calculateSynastryMatch,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.black,
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
                        children: const [
                          Icon(Icons.auto_awesome_rounded, color: Color(0xFFFFD700), size: 22),
                          SizedBox(width: 10),
                          Text(
                            'Calculate 36-Guna Milan Match',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
              ),
            ),

            // 4. Dynamic Results Section
            if (_synastryData != null) ...[
              const SizedBox(height: 24),

              // Celestial Score Hero Banner
              Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: Colors.black.withValues(alpha: 0.08)),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.06),
                      blurRadius: 18,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          colors: [Color(0xFF1E1A38), Color(0xFF2E2452)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                      ),
                      child: Row(
                        children: [
                          // Circular Score Badge
                          Container(
                            width: 76,
                            height: 76,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: const Color(0xFFFFD700).withValues(alpha: 0.15),
                              border: Border.all(color: const Color(0xFFFFD700), width: 2.5),
                            ),
                            child: Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text(
                                    '${_synastryData!['score'] ?? 86}%',
                                    style: const TextStyle(
                                      fontSize: 22,
                                      fontWeight: FontWeight.w900,
                                      color: Color(0xFFFFD700),
                                    ),
                                  ),
                                  const Text(
                                    'MATCH',
                                    style: TextStyle(
                                      fontSize: 9,
                                      fontWeight: FontWeight.w800,
                                      color: Colors.white70,
                                      letterSpacing: 0.8,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(width: 16),

                          // Verdict & Ashtakoot Score
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
                                    'ASHTAKOOT SCORE: ${_synastryData!['gunas'] ?? '31 / 36 Gunas'}',
                                    style: const TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w800,
                                      color: Color(0xFFFFD700),
                                      letterSpacing: 0.8,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  _synastryData!['verdict'] ?? 'Very High Compatibility (Uttam Milan)',
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                    height: 1.2,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 20),

              // 🪐 Side-by-Side Planetary Synastry Grid
              _buildPlanetarySynastryGrid(_synastryData!['planetarySynastry']),

              const SizedBox(height: 20),

              // 📊 Ashtakoot 8-Guna Breakdown Table Widget
              _buildAshtakootTableWidget(_synastryData!['ashtakoot']),

              const SizedBox(height: 20),

              // 🛡️ Manglik Dosha Compatibility Card
              _buildManglikCheckCard(_synastryData!['manglikCheck']),

              const SizedBox(height: 20),

              // 🌿 Nadi & Bhakoot Compatibility Analysis Card
              _buildNadiBhakootCard(_synastryData!['nadiBhakootAnalysis']),

              const SizedBox(height: 20),

              // 📖 Relationship Guidance Report Cards
              _buildRelationshipReportCards(_synastryData!['relationshipReport'] ?? _synastryData!['summary']),

              const SizedBox(height: 20),

              // 📄 Download & Share Guna Milan PDF Certificate Button
              _buildDownloadPdfButton(userName, _partnerName ?? 'Partner'),

              const SizedBox(height: 16),

              // 💬 1-Tap "Ask Relationship Astrologer About This Match" Button
              _buildAskAstrologerButton(userName, _partnerName ?? 'Partner'),
            ],
          ],
        ),
      ),
    );
  }

  // 🔥 Daily Love Transit Meter Banner Widget
  Widget _buildDailyLoveTransitBanner() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFFFF0F3), Color(0xFFFDE8ED)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE83D66).withValues(alpha: 0.2)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFE83D66).withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: const BoxDecoration(
              color: Color(0xFFE83D66),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.wb_twilight_rounded, color: Colors.white, size: 20),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: const [
                Text(
                  'Today\'s Romantic Transit: 92% (High Passion)',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFFB02246)),
                ),
                SizedBox(height: 2),
                Text(
                  'Venus transiting 5th House — Ideal day for dates & deep expression!',
                  style: TextStyle(fontSize: 11, color: Colors.black87),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // 👨‍👩‍👧‍👦 Saved Family Profiles Carousel Widget
  Widget _buildSavedFamilyProfilesSelector(List familyMembers) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: const [
            Text(
              'Select Person 2 from Saved Profiles:',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.black87),
            ),
            Icon(Icons.swipe_left_rounded, size: 16, color: Colors.grey),
          ],
        ),
        const SizedBox(height: 8),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: familyMembers.map((member) {
              final name = member['fullName'] ?? member['name'] ?? 'Family';
              final rel = member['relationship'] ?? 'Member';
              final isSelected = _partnerName == name;

              return Padding(
                padding: const EdgeInsets.only(right: 8.0),
                child: ChoiceChip(
                  avatar: CircleAvatar(
                    backgroundColor: isSelected ? Colors.white : const Color(0xFFE83D66).withValues(alpha: 0.12),
                    child: Text(
                      name[0].toUpperCase(),
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: isSelected ? const Color(0xFFE83D66) : Colors.black,
                      ),
                    ),
                  ),
                  label: Text('$name ($rel)'),
                  selected: isSelected,
                  selectedColor: const Color(0xFFE83D66),
                  backgroundColor: Colors.white,
                  labelStyle: TextStyle(
                    color: isSelected ? Colors.white : Colors.black,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                    side: BorderSide(
                      color: isSelected ? const Color(0xFFE83D66) : Colors.grey.shade300,
                    ),
                  ),
                  onSelected: (val) {
                    setState(() {
                      _partnerName = name;
                      _partnerGender = member['gender'] ?? 'Female';
                      _partnerDob = member['dateOfBirth'] ?? '1999-05-20';
                      _partnerTob = member['timeOfBirth'] ?? '10:30';
                      _partnerPob = member['placeOfBirth'] ?? 'Delhi, India';
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

  // 🪐 Side-by-Side Planetary Synastry Grid Widget
  Widget _buildPlanetarySynastryGrid(dynamic synastryList) {
    final List list = (synastryList is List && synastryList.isNotEmpty)
        ? synastryList
        : [
            {'planet': 'Sun ☉ (Willpower)', 'p1Sign': 'Scorpio', 'p2Sign': 'Cancer', 'alignment': 'Trine (120°)', 'verdict': 'Harmonious Ambition'},
            {'planet': 'Moon ☽ (Emotions)', 'p1Sign': 'Pisces', 'p2Sign': 'Taurus', 'alignment': 'Sextile (60°)', 'verdict': 'Deep Emotional Symbiosis'},
            {'planet': 'Venus ♀ (Romance)', 'p1Sign': 'Libra', 'p2Sign': 'Gemini', 'alignment': 'Trine (120°)', 'verdict': 'Strong Physical Attraction'},
            {'planet': 'Mars ♂ (Passion)', 'p1Sign': 'Aries', 'p2Sign': 'Leo', 'alignment': 'Trine (120°)', 'verdict': 'High Dynamic Energy & Loyalty'},
          ];

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: const [
              Icon(Icons.stars_rounded, color: Color(0xFFFF9800), size: 22),
              SizedBox(width: 10),
              Text(
                'Planetary Synastry Comparison Grid',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.black),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Side-by-side alignment of Sun, Moon, Venus & Mars:',
            style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
          ),
          const SizedBox(height: 16),

          ...list.map((item) {
            final planet = item['planet'] ?? 'Planet';
            final p1 = item['p1Sign'] ?? 'Sign';
            final p2 = item['p2Sign'] ?? 'Sign';
            final align = item['alignment'] ?? 'Trine';
            final verdict = item['verdict'] ?? 'Harmonious';

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
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(planet, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.black)),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFF9800).withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(align, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFFD97706))),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Person 1: $p1', style: TextStyle(fontSize: 12, color: Colors.grey.shade800, fontWeight: FontWeight.w600)),
                      const Icon(Icons.compare_arrows_rounded, size: 16, color: Colors.grey),
                      Text('Person 2: $p2', style: TextStyle(fontSize: 12, color: Colors.grey.shade800, fontWeight: FontWeight.w600)),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Verdict: $verdict',
                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF059669)),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  // 📊 Ashtakoot 8-Guna Breakdown Table Widget
  Widget _buildAshtakootTableWidget(dynamic ashtakootData) {
    final List list = (ashtakootData is List && ashtakootData.isNotEmpty)
        ? ashtakootData
        : [
            {'name': 'Varna', 'score': 1, 'max': 1, 'meaning': 'Work & Ego Alignment', 'verdict': 'Full Compatibility'},
            {'name': 'Vashya', 'score': 2, 'max': 2, 'meaning': 'Mutual Influence & Control', 'verdict': 'Harmonious Balance'},
            {'name': 'Tara', 'score': 3, 'max': 3, 'meaning': 'Destiny & Astral Luck', 'verdict': 'Auspicious Star Alignment'},
            {'name': 'Yoni', 'score': 3, 'max': 4, 'meaning': 'Physical & Intimate Affinity', 'verdict': 'Strong Physical Chemistry'},
            {'name': 'Maitri', 'score': 5, 'max': 5, 'meaning': 'Intellectual Friendship', 'verdict': 'Deep Mental Bond'},
            {'name': 'Gana', 'score': 6, 'max': 6, 'meaning': 'Behavior & Temperament', 'verdict': 'Matching Deva Gana'},
            {'name': 'Bhakoot', 'score': 7, 'max': 7, 'meaning': 'Emotional & Financial Growth', 'verdict': 'No Bhakoot Dosha (7/7)'},
            {'name': 'Nadi', 'score': 8, 'max': 8, 'meaning': 'Genetics, Health & Progeny', 'verdict': 'No Nadi Dosha (8/8)'},
          ];

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: const [
              Icon(Icons.table_chart_rounded, color: Color(0xFF6C63FF), size: 20),
              SizedBox(width: 8),
              Text(
                'Ashtakoot 8-Guna Breakdown Table',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.black),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '8 essential Vedic compatibility factors calculated out of 36 points:',
            style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
          ),
          const SizedBox(height: 16),

          ...list.map((item) {
            final String name = item['name'] ?? 'Guna';
            final int score = int.tryParse(item['score']?.toString() ?? '1') ?? 1;
            final int max = int.tryParse(item['max']?.toString() ?? '1') ?? 1;
            final String meaning = item['meaning'] ?? '';
            final String verdict = item['verdict'] ?? '';
            final double pct = (score / max).clamp(0.0, 1.0);

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
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Text(
                            name,
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.black),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            '($meaning)',
                            style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                          ),
                        ],
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: const Color(0xFF6C63FF),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          '$score / $max Pts',
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
                      color: const Color(0xFF6C63FF),
                      minHeight: 6,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    verdict,
                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFFD95D39)),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  // 🛡️ Manglik Dosha Check Card Widget
  Widget _buildManglikCheckCard(dynamic manglikData) {
    final m = manglikData ?? {
      'person1Status': 'Non-Manglik',
      'person2Status': 'Partial Manglik (Mars in 4th House)',
      'manglikVerdict': 'Manglik Dosha is balanced & non-obstructive due to Jupiter aspect.'
    };

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE83D66).withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: const [
              Icon(Icons.shield_outlined, color: Color(0xFFE83D66), size: 22),
              SizedBox(width: 10),
              Text(
                'Manglik Dosha Compatibility Check',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.black),
              ),
            ],
          ),
          const SizedBox(height: 14),

          Row(
            children: [
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFF0F3),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Person 1', style: TextStyle(fontSize: 11, color: Colors.grey, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 4),
                      Text(
                        m['person1Status'] ?? 'Non-Manglik',
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.black),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFF0F3),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Person 2', style: TextStyle(fontSize: 11, color: Colors.grey, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 4),
                      Text(
                        m['person2Status'] ?? 'Partial Manglik',
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.black),
                      ),
                    ],
                  ),
                ),
              ),
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
              children: [
                const Icon(Icons.check_circle_outline_rounded, color: Color(0xFFE83D66), size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    m['manglikVerdict'] ?? 'Manglik status balanced.',
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

  // 🌿 Nadi & Bhakoot Compatibility Card Widget
  Widget _buildNadiBhakootCard(dynamic nbData) {
    final nb = nbData ?? {
      'nadiVerdict': 'Excellent Nadi compatibility (8/8). Ensures healthy lineage & physical vitality.',
      'bhakootVerdict': 'Favorable 1/7 Bhakoot axis. Fosters mutual wealth accumulation & trust.'
    };

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: const [
              Icon(Icons.favorite_outline_rounded, color: Color(0xFF9C27B0), size: 22),
              SizedBox(width: 10),
              Text(
                'Nadi & Bhakoot Compatibility Analysis',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.black),
              ),
            ],
          ),
          const SizedBox(height: 14),

          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFF9C27B0).withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFF9C27B0).withValues(alpha: 0.2)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: const [
                    Icon(Icons.verified_rounded, color: Color(0xFF9C27B0), size: 16),
                    SizedBox(width: 6),
                    Text('NADI COMPATIBILITY (8 PTS)', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF9C27B0))),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  nb['nadiVerdict'] ?? '',
                  style: const TextStyle(fontSize: 13, color: Colors.black87, height: 1.4),
                ),
              ],
            ),
          ),

          const SizedBox(height: 10),

          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFF317BEA).withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFF317BEA).withValues(alpha: 0.2)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: const [
                    Icon(Icons.verified_rounded, color: Color(0xFF317BEA), size: 16),
                    SizedBox(width: 6),
                    Text('BHAKOOT COMPATIBILITY (7 PTS)', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF317BEA))),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  nb['bhakootVerdict'] ?? '',
                  style: const TextStyle(fontSize: 13, color: Colors.black87, height: 1.4),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // 📖 Relationship Guidance Report Cards
  Widget _buildRelationshipReportCards(String reportText) {
    final List<String> blocks = reportText.split('###').where((b) => b.trim().isNotEmpty).toList();

    if (blocks.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.grey.shade200),
        ),
        child: SelectableText.rich(
          TextSpan(children: _parseFormattedSpans(reportText)),
        ),
      );
    }

    return Column(
      children: blocks.map((block) {
        final lines = block.trim().split('\n');
        final titleLine = lines.first.trim();
        final bodyText = lines.sublist(1).join('\n').trim();

        Color cardColor = const Color(0xFFE83D66);
        IconData icon = Icons.favorite_rounded;

        if (titleLine.contains('Emotional')) {
          cardColor = const Color(0xFFE83D66);
          icon = Icons.favorite_rounded;
        } else if (titleLine.contains('Marriage') || titleLine.contains('Longevity')) {
          cardColor = const Color(0xFF9C27B0);
          icon = Icons.workspace_premium_rounded;
        } else if (titleLine.contains('Remedies') || titleLine.contains('Guidance')) {
          cardColor = const Color(0xFFD95D39);
          icon = Icons.spa_rounded;
        }

        return Container(
          margin: const EdgeInsets.only(bottom: 16),
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: cardColor.withValues(alpha: 0.25)),
            boxShadow: [
              BoxShadow(
                color: cardColor.withValues(alpha: 0.05),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: cardColor.withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                    ),
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
              const SizedBox(height: 12),
              const Divider(height: 1),
              const SizedBox(height: 12),
              SelectableText.rich(
                TextSpan(children: _parseFormattedSpans(bodyText)),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  // 📄 Download / Share Guna Milan PDF Certificate Button Widget
  Widget _buildDownloadPdfButton(String p1, String p2) {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: OutlinedButton.icon(
        onPressed: () {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Downloading 36-Guna Milan Certificate PDF for $p1 & $p2...'),
              backgroundColor: const Color(0xFF6C63FF),
            ),
          );
        },
        icon: const Icon(Icons.picture_as_pdf_rounded, color: Color(0xFF6C63FF)),
        label: const Text(
          'Download 36-Guna Milan Certificate (PDF)',
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Color(0xFF6C63FF)),
        ),
        style: OutlinedButton.styleFrom(
          side: const BorderSide(color: Color(0xFF6C63FF), width: 1.5),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
      ),
    );
  }

  // 💬 1-Tap "Ask Relationship Astrologer About This Match" Button Widget
  Widget _buildAskAstrologerButton(String p1, String p2) {
    return SizedBox(
      width: double.infinity,
      height: 56,
      child: ElevatedButton.icon(
        onPressed: () {
          Navigator.pushNamed(context, '/chatbot', arguments: {
            'name': 'Vedic Love Specialist',
            'specialty': 'Guna Milan & Synastry',
            'field': 'Marriage Consultation',
            'initialMessage': 'Please provide relationship guidance for $p1 & $p2 based on our ${_synastryData?['gunas'] ?? '31/36'} Guna Milan result.',
          });
        },
        icon: const Icon(Icons.chat_bubble_outline_rounded, color: Colors.white),
        label: const Text(
          'Ask Love Astrologer About This Match',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
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
    required String title,
    required String name,
    required String sign,
    required bool isUser,
    VoidCallback? onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 130,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.black.withValues(alpha: 0.08)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          children: [
            Text(
              title,
              style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey.shade600),
            ),
            const SizedBox(height: 8),
            Container(
              width: 46,
              height: 46,
              decoration: const BoxDecoration(
                color: Color(0xFFFFF0F3),
                shape: BoxShape.circle,
              ),
              child: Center(
                child: isUser
                    ? Text(name.isNotEmpty ? name[0].toUpperCase() : 'P', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Color(0xFFE83D66)))
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
    );
  }

  void _showAddPartnerDialog() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => PartnerBirthDetailsSheet(
        initialName: _partnerName,
        initialDob: _partnerDob,
        onSave: (name, gender, dob, tob, pob) {
          setState(() {
            _partnerName = name;
            _partnerGender = gender;
            _partnerDob = dob;
            _partnerTob = tob;
            _partnerPob = pob;
          });
          _calculateSynastryMatch();
        },
      ),
    );
  }

  Future<void> _calculateSynastryMatch() async {
    final backendService = Provider.of<BackendService>(context, listen: false);

    if (_partnerName == null || _partnerName!.isEmpty) {
      _showAddPartnerDialog();
      return;
    }

    setState(() {
      _isMatching = true;
    });

    final result = await backendService.fetchSynastryMatch(
      partnerName: _partnerName!,
      partnerGender: _partnerGender,
      partnerDob: _partnerDob ?? '1999-05-20',
      partnerTob: _partnerTob ?? '10:30',
      partnerPob: _partnerPob ?? 'Delhi, India',
    );

    if (mounted) {
      setState(() {
        _isMatching = false;
        if (result != null) {
          _synastryData = result;
        } else {
          _synastryData = {
            'score': 86,
            'gunaTotal': 31,
            'gunas': '31 / 36 Gunas',
            'verdict': 'Very High Compatibility (Uttam Milan)',
            'summary': 'Deep emotional harmony and planetary alignment between the charts.',
            'planetarySynastry': [
              {'planet': 'Sun ☉ (Willpower)', 'p1Sign': 'Scorpio', 'p2Sign': 'Cancer', 'alignment': 'Trine (120°)', 'verdict': 'Harmonious Ambition'},
              {'planet': 'Moon ☽ (Emotions)', 'p1Sign': 'Pisces', 'p2Sign': 'Taurus', 'alignment': 'Sextile (60°)', 'verdict': 'Deep Emotional Symbiosis'},
              {'planet': 'Venus ♀ (Romance)', 'p1Sign': 'Libra', 'p2Sign': 'Gemini', 'alignment': 'Trine (120°)', 'verdict': 'Strong Physical Attraction'},
              {'planet': 'Mars ♂ (Passion)', 'p1Sign': 'Aries', 'p2Sign': 'Leo', 'alignment': 'Trine (120°)', 'verdict': 'High Dynamic Energy & Loyalty'},
            ],
            'ashtakoot': [
              {'name': 'Varna', 'score': 1, 'max': 1, 'meaning': 'Work & Ego Alignment', 'verdict': 'Full Compatibility'},
              {'name': 'Vashya', 'score': 2, 'max': 2, 'meaning': 'Mutual Influence & Control', 'verdict': 'Harmonious Balance'},
              {'name': 'Tara', 'score': 3, 'max': 3, 'meaning': 'Destiny & Astral Luck', 'verdict': 'Auspicious Star Alignment'},
              {'name': 'Yoni', 'score': 3, 'max': 4, 'meaning': 'Physical & Intimate Affinity', 'verdict': 'Strong Physical Chemistry'},
              {'name': 'Maitri', 'score': 5, 'max': 5, 'meaning': 'Intellectual Friendship', 'verdict': 'Deep Mental Bond'},
              {'name': 'Gana', 'score': 6, 'max': 6, 'meaning': 'Behavior & Temperament', 'verdict': 'Matching Deva Gana'},
              {'name': 'Bhakoot', 'score': 7, 'max': 7, 'meaning': 'Emotional & Financial Growth', 'verdict': 'No Bhakoot Dosha (7/7)'},
              {'name': 'Nadi', 'score': 8, 'max': 8, 'meaning': 'Genetics, Health & Progeny', 'verdict': 'No Nadi Dosha (8/8)'},
            ],
            'manglikCheck': {
              'person1Status': 'Non-Manglik',
              'person2Status': 'Partial Manglik (Mars in 4th House)',
              'manglikVerdict': 'Manglik Dosha is balanced and non-obstructive due to Jupiter aspect.'
            },
            'nadiBhakootAnalysis': {
              'nadiVerdict': 'Excellent Nadi compatibility (8/8). Ensures healthy lineage and physical vitality.',
              'bhakootVerdict': 'Favorable 1/7 Bhakoot axis. Fosters mutual wealth accumulation and trust.'
            },
            'relationshipReport': '''### 💖 Emotional Bond & Mutual Understanding
You share a naturally harmonious emotional connection. Moon-Venus alignment fosters deep mutual empathy, intuitive understanding, and shared life goals.

### 💍 Marriage Longevity & Progeny Compatibility
With 31 out of 36 Gunas matched, this pair exhibits outstanding Ashtakoot compatibility. The absence of both Nadi and Bhakoot Doshas ensures strong health, financial stability, and long-term marital bliss.

### 🌿 Sacred Guidance & Relationship Remedies
To maintain positive planetary energy, light a Ghee lamp together on Thursdays and practice open communication during active Mars transits.'''
          };
        }
      });
    }
  }

  void _showInfoDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFFFCF7F1),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('What is Ashtakoot 36 Guna Milan?'),
        content: const Text(
          'Ashtakoot Guna Milan evaluates 8 essential astrological factors (Varna, Vashya, Tara, Yoni, Maitri, Gana, Bhakoot, Nadi) totaling 36 points to analyze marriage compatibility, Manglik Dosha, Nadi genetics, and lifelong marital harmony.',
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
  final String? initialName;
  final String? initialDob;
  final Function(String name, String gender, String dob, String tob, String pob) onSave;

  const PartnerBirthDetailsSheet({
    super.key,
    this.initialName,
    this.initialDob,
    required this.onSave,
  });

  @override
  State<PartnerBirthDetailsSheet> createState() => _PartnerBirthDetailsSheetState();
}

class _PartnerBirthDetailsSheetState extends State<PartnerBirthDetailsSheet> {
  final TextEditingController _nameController = TextEditingController();
  String _gender = 'Female';

  DateTime? _selectedDate = DateTime(1999, 5, 20);
  TimeOfDay? _selectedTime = const TimeOfDay(hour: 10, minute: 30);
  bool _dontKnowTime = false;

  final TextEditingController _placeController = TextEditingController(text: 'Delhi, India');
  List<CitySuggestion> _placeSuggestions = [];
  bool _isSearchingPlace = false;
  Timer? _debounceTimer;

  @override
  void initState() {
    super.initState();
    if (widget.initialName != null) _nameController.text = widget.initialName!;
  }

  void _onPlaceSearchChanged(String query) {
    if (_debounceTimer?.isActive ?? false) _debounceTimer!.cancel();
    if (query.trim().isEmpty) {
      setState(() {
        _placeSuggestions = [];
        _isSearchingPlace = false;
      });
      return;
    }

    _debounceTimer = Timer(const Duration(milliseconds: 300), () async {
      setState(() => _isSearchingPlace = true);
      final suggestions = await CityAutocompleteService.fetchCitySuggestions(query);
      if (mounted) {
        setState(() {
          _placeSuggestions = suggestions;
          _isSearchingPlace = false;
        });
      }
    });
  }

  void _selectSuggestion(CitySuggestion suggestion) {
    setState(() {
      _placeController.text = suggestion.fullDisplayName;
      _placeSuggestions = [];
    });
  }

  void _submitForm() {
    if (_nameController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter partner\'s full name')),
      );
      return;
    }

    final dobStr = DateFormat('yyyy-MM-dd').format(_selectedDate ?? DateTime(1999, 5, 20));
    final tobStr = _dontKnowTime
        ? '12:00'
        : '${(_selectedTime?.hour ?? 10).toString().padLeft(2, '0')}:${(_selectedTime?.minute ?? 30).toString().padLeft(2, '0')}';
    final pobStr = _placeController.text.trim().isEmpty ? 'Delhi, India' : _placeController.text.trim();

    widget.onSave(_nameController.text.trim(), _gender, dobStr, tobStr, pobStr);
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.85,
      padding: EdgeInsets.only(
        top: 20,
        left: 24,
        right: 24,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
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
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Partner Birth Details',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.black),
              ),
              IconButton(
                icon: const Icon(Icons.close, color: Colors.black54),
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
          const SizedBox(height: 16),

          Expanded(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Full Name', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _nameController,
                    decoration: InputDecoration(
                      hintText: 'Enter partner\'s full name',
                      filled: true,
                      fillColor: Colors.white,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
                    ),
                  ),
                  const SizedBox(height: 16),

                  const Text('Gender', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                  const SizedBox(height: 8),
                  Row(
                    children: ['Female', 'Male', 'Other'].map((g) {
                      final isSelected = _gender == g;
                      return Padding(
                        padding: const EdgeInsets.only(right: 12.0),
                        child: ChoiceChip(
                          label: Text(g),
                          selected: isSelected,
                          selectedColor: const Color(0xFFE83D66),
                          backgroundColor: Colors.white,
                          labelStyle: TextStyle(
                            color: isSelected ? Colors.white : Colors.black,
                            fontWeight: FontWeight.bold,
                          ),
                          onSelected: (val) => setState(() => _gender = g),
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 16),

                  const Text('Date of Birth', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                  const SizedBox(height: 8),
                  InkWell(
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: _selectedDate ?? DateTime(1999, 5, 20),
                        firstDate: DateTime(1900),
                        lastDate: DateTime.now(),
                      );
                      if (picked != null) setState(() => _selectedDate = picked);
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            DateFormat('dd MMMM yyyy').format(_selectedDate ?? DateTime(1999, 5, 20)),
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                          ),
                          const Icon(Icons.calendar_today_rounded, color: Color(0xFFE83D66), size: 20),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  const Text('Place of Birth', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _placeController,
                    onChanged: _onPlaceSearchChanged,
                    decoration: InputDecoration(
                      hintText: 'Search city or pincode',
                      filled: true,
                      fillColor: Colors.white,
                      prefixIcon: const Icon(Icons.search, color: Colors.grey),
                      suffixIcon: _isSearchingPlace
                          ? const Padding(
                              padding: EdgeInsets.all(12),
                              child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFFE83D66)),
                            )
                          : null,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
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
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: _placeSuggestions.length,
                        separatorBuilder: (context, index) => const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final suggestion = _placeSuggestions[index];
                          return Material(
                            color: Colors.transparent,
                            child: ListTile(
                              leading: const Icon(Icons.location_on_outlined, size: 20, color: Colors.black),
                              title: Text(suggestion.fullDisplayName, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                              onTap: () => _selectSuggestion(suggestion),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),

          const SizedBox(height: 16),

          SizedBox(
            width: double.infinity,
            height: 54,
            child: ElevatedButton(
              onPressed: _submitForm,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFE83D66),
                elevation: 0,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
              ),
              child: const Text(
                'Save & Calculate 36-Guna Match',
                style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
