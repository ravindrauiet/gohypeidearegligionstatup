import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/backend_service.dart';

class GemstoneRemedyScreen extends StatefulWidget {
  const GemstoneRemedyScreen({super.key});

  @override
  State<GemstoneRemedyScreen> createState() => _GemstoneRemedyScreenState();
}

class _GemstoneRemedyScreenState extends State<GemstoneRemedyScreen> {
  bool _isLoading = true;
  Map<String, dynamic>? _remedyData;

  @override
  void initState() {
    super.initState();
    _loadRecommendations();
  }

  Future<void> _loadRecommendations() async {
    final backendService = Provider.of<BackendService>(context, listen: false);
    final data = await backendService.fetchGemstoneRecommendations();

    if (mounted) {
      setState(() {
        _remedyData = data;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final backendService = Provider.of<BackendService>(context);
    final userKundli = backendService.kundliData;
    final ascendant = userKundli?['ascendant'] ?? 'Virgo';
    final moonSign = userKundli?['moonSign'] ?? 'Gemini';

    final primary = _remedyData?['primaryGemstone'] ?? {
      'name': 'Yellow Sapphire (Pukhraj)',
      'planet': 'Jupiter (Brihaspati)',
      'ratti': '5.25 - 6.5 Ratti',
      'metal': '22k Yellow Gold or Panchdhatu Ring',
      'finger': 'Index Finger of Right Hand',
      'day': 'Thursday Morning (Shukla Paksha)',
      'benefits': 'Strengthens 9th house of fortune, higher wisdom, business growth, and spiritual protection.'
    };

    final secondary = _remedyData?['secondaryGemstone'] ?? {
      'name': 'Emerald (Panna)',
      'planet': 'Mercury (Budh)',
      'ratti': '4.5 - 5.5 Ratti',
      'metal': 'Silver or Gold Ring',
      'finger': 'Little Finger of Right Hand',
      'day': 'Wednesday Morning',
      'benefits': 'Enhances communication clarity, intellect, analytical power, and commerce.'
    };

    final List mantras = _remedyData?['vedicMantras'] ?? [
      {
        'planet': 'Jupiter (Guru) Mantra',
        'mantra': 'Om Gram Greem Groum Sah Gurave Namah',
        'recitations': '108 times daily on Thursday mornings'
      },
      {
        'planet': 'Gayatri Mantra',
        'mantra': 'Om Bhur Bhuva Swaha Tat Savitur Varenyam Bhargo Devasya Dheemahi Dhiyo Yo Nah Prachodayat',
        'recitations': '21 times daily at sunrise'
      }
    ];

    final List dailyRemedies = _remedyData?['dailyRemedies'] ?? [
      'Offer yellow flowers and chana dal to Lord Vishnu or Peepal tree on Thursday mornings.',
      'Donate food to cows on Wednesdays for Mercury strength.',
      'Water the Surya Dev at sunrise using a copper pot.'
    ];

    return Scaffold(
      backgroundColor: const Color(0xFFFCF7F1),
      appBar: AppBar(
        backgroundColor: const Color(0xFFFCF7F1),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.black),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'AI Gemstone & Remedy Finder',
          style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 18),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFFE83D66)))
          : SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Chart Header Banner
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF1E1A38), Color(0xFF2E2452)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(22),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('ANALYZED FROM YOUR KUNDLI CHART', style: TextStyle(color: Color(0xFFFFD700), fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 0.8)),
                        const SizedBox(height: 4),
                        Text(
                          'Lagna: $ascendant · Moon Sign: $moonSign',
                          style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 2),
                        const Text('Optimal planetary gemstones & mantras for your current Dasha period.', style: TextStyle(color: Colors.white70, fontSize: 12)),
                      ],
                    ),
                  ),

                  const SizedBox(height: 24),

                  // 1. Primary Gemstone Recommendation
                  const Text(
                    '💎 YOUR PRIMARY LUCKY GEMSTONE',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w900, color: Colors.grey, letterSpacing: 1.0),
                  ),
                  const SizedBox(height: 10),

                  Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(color: const Color(0xFFFFD700), width: 1.5),
                      boxShadow: [
                        BoxShadow(color: const Color(0xFFFFD700).withValues(alpha: 0.1), blurRadius: 12, offset: const Offset(0, 4)),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: const BoxDecoration(color: Color(0xFFFFF8E1), shape: BoxShape.circle),
                              child: const Icon(Icons.diamond_rounded, color: Color(0xFFD97706), size: 28),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    primary['name'] ?? 'Yellow Sapphire',
                                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: Colors.black),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    'Ruling Planet: ${primary['planet']}',
                                    style: const TextStyle(fontSize: 13, color: Color(0xFFD95D39), fontWeight: FontWeight.bold),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),

                        const SizedBox(height: 14),
                        const Divider(height: 1),
                        const SizedBox(height: 12),

                        _buildDetailRow('Recommended Weight:', primary['ratti'] ?? '5.25 Ratti'),
                        const SizedBox(height: 6),
                        _buildDetailRow('Ideal Ring Metal:', primary['metal'] ?? 'Gold'),
                        const SizedBox(height: 6),
                        _buildDetailRow('Wearing Finger:', primary['finger'] ?? 'Index Finger'),
                        const SizedBox(height: 6),
                        _buildDetailRow('Auspicious Time:', primary['day'] ?? 'Thursday Morning'),

                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFCF7F1),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Text(
                            '✨ ${primary['benefits']}',
                            style: const TextStyle(fontSize: 12, color: Colors.black87, height: 1.35),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 24),

                  // 2. Secondary Gemstone
                  const Text(
                    '💚 SECONDARY COMPLEMENTARY GEMSTONE',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w900, color: Colors.grey, letterSpacing: 1.0),
                  ),
                  const SizedBox(height: 10),

                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.grey.shade200),
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: const BoxDecoration(color: Color(0xFFE8F5E9), shape: BoxShape.circle),
                          child: const Icon(Icons.diamond_outlined, color: Color(0xFF059669), size: 24),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(secondary['name'] ?? 'Emerald (Panna)', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                              const SizedBox(height: 2),
                              Text('Planet: ${secondary['planet']} · ${secondary['ratti']}', style: const TextStyle(fontSize: 12, color: Colors.grey)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 24),

                  // 3. Vedic Mantras Section
                  const Text(
                    '🕉️ RECOMMENDED VEDIC MANTRAS',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w900, color: Colors.grey, letterSpacing: 1.0),
                  ),
                  const SizedBox(height: 10),

                  ...mantras.map((m) {
                    return Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: Colors.grey.shade200),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(m['planet'] ?? 'Vedic Mantra', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF9C27B0))),
                          const SizedBox(height: 6),
                          Text(
                            '"${m['mantra']}"',
                            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: Colors.black, height: 1.3),
                          ),
                          const SizedBox(height: 4),
                          Text('Recite: ${m['recitations']}', style: const TextStyle(fontSize: 11, color: Colors.grey)),
                        ],
                      ),
                    );
                  }),

                  const SizedBox(height: 24),

                  // 4. Actionable Daily Remedies Checklist
                  const Text(
                    '🌿 DAILY ACTIONABLE KUNDLI REMEDIES',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w900, color: Colors.grey, letterSpacing: 1.0),
                  ),
                  const SizedBox(height: 10),

                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.grey.shade200),
                    ),
                    child: Column(
                      children: dailyRemedies.map((r) {
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: Row(
                            children: [
                              const Icon(Icons.check_circle_rounded, color: Color(0xFF059669), size: 18),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(r.toString(), style: const TextStyle(fontSize: 13, color: Colors.black87)),
                              ),
                            ],
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildDetailRow(String label, String val) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey, fontWeight: FontWeight.w600)),
        Text(val, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.black)),
      ],
    );
  }
}
