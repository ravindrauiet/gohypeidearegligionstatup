import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../services/backend_service.dart';

class PanchangScreen extends StatefulWidget {
  const PanchangScreen({super.key});

  @override
  State<PanchangScreen> createState() => _PanchangScreenState();
}

class _PanchangScreenState extends State<PanchangScreen> {
  Map<String, dynamic>? _panchangData;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadPanchangData();
  }

  Future<void> _loadPanchangData() async {
    final backendService = Provider.of<BackendService>(context, listen: false);
    final data = await backendService.fetchPanchangToday();
    if (mounted) {
      setState(() {
        _panchangData = data;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final dateStr = DateFormat('EEEE, d MMMM yyyy').format(DateTime.now());

    final String vaar = _panchangData?['vaar'] ?? 'Sunday';
    final String tithi = _panchangData?['tithi'] ?? 'Shukla Paksha Trayodashi';
    final String nakshatra = _panchangData?['nakshatra'] ?? 'Uttara Bhadrapada';
    final String yoga = _panchangData?['yoga'] ?? 'Saubhagya';
    final String karana = _panchangData?['karana'] ?? 'Taitila';

    final String sunrise = _panchangData?['sunrise'] ?? '06:05 AM';
    final String sunset = _panchangData?['sunset'] ?? '06:42 PM';
    final String moonrise = _panchangData?['moonrise'] ?? '08:15 PM';
    final String moonset = _panchangData?['moonset'] ?? '07:30 AM';

    final String rahuKaal = _panchangData?['rahuKaal'] ?? '04:35 PM - 06:10 PM';
    final String yamaganda = _panchangData?['yamaganda'] ?? '12:15 PM - 01:50 PM';
    final String abhijit = _panchangData?['abhijitMuhurat'] ?? '11:48 AM - 12:36 PM';

    final List choghadiya = _panchangData?['choghadiya'] ?? [
      {'name': 'Shubh (Auspicious)', 'time': '06:05 AM - 07:40 AM', 'status': 'Auspicious'},
      {'name': 'Rog (Sickness)', 'time': '07:40 AM - 09:15 AM', 'status': 'Avoid'},
      {'name': 'Udveg (Anxiety)', 'time': '09:15 AM - 10:50 AM', 'status': 'Avoid'},
      {'name': 'Char (Neutral)', 'time': '10:50 AM - 12:25 PM', 'status': 'Neutral'},
      {'name': 'Labh (Gain)', 'time': '12:25 PM - 02:00 PM', 'status': 'Auspicious'},
      {'name': 'Amrit (Best)', 'time': '02:00 PM - 03:35 PM', 'status': 'Best'},
      {'name': 'Kaal (Loss)', 'time': '03:35 PM - 05:10 PM', 'status': 'Avoid'},
      {'name': 'Shubh (Auspicious)', 'time': '05:10 PM - 06:42 PM', 'status': 'Auspicious'},
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
          'Today\'s Live Panchang & Muhurat',
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
                          children: const [
                            Icon(Icons.location_on_rounded, color: Color(0xFFFFD700), size: 18),
                            SizedBox(width: 6),
                            Text('Delhi, India', style: TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.bold)),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          dateStr,
                          style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w900),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Tithi: $tithi · Vaar: $vaar',
                          style: const TextStyle(color: Color(0xFFFFD700), fontSize: 12, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 20),

                  // 2. Rahu Kaal & Yamaganda Inauspicious Clock
                  const Text(
                    '⚠️ INAUSPICIOUS TIMINGS (CLK)',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w900, color: Colors.grey, letterSpacing: 1.0),
                  ),
                  const SizedBox(height: 10),

                  Row(
                    children: [
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
                            boxShadow: [
                              BoxShadow(color: Colors.red.withValues(alpha: 0.05), blurRadius: 10, offset: const Offset(0, 4)),
                            ],
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: const [
                                  Icon(Icons.access_time_filled_rounded, color: Colors.red, size: 18),
                                  SizedBox(width: 6),
                                  Text('RAHU KAAL', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900, color: Colors.red)),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Text(rahuKaal, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.black)),
                              const SizedBox(height: 2),
                              const Text('Avoid new starts', style: TextStyle(fontSize: 10, color: Colors.grey)),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(color: Colors.orange.withValues(alpha: 0.3)),
                            boxShadow: [
                              BoxShadow(color: Colors.orange.withValues(alpha: 0.05), blurRadius: 10, offset: const Offset(0, 4)),
                            ],
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: const [
                                  Icon(Icons.timer_rounded, color: Colors.orange, size: 18),
                                  SizedBox(width: 6),
                                  Text('YAMAGANDA', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900, color: Colors.orange)),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Text(yamaganda, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.black)),
                              const SizedBox(height: 2),
                              const Text('Avoid travel/deals', style: TextStyle(fontSize: 10, color: Colors.grey)),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 20),

                  // 3. Abhijit Muhurat & Shubh Choghadiya
                  const Text(
                    '✨ AUSPICIOUS MUHURAT & CHOGHADIYA',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w900, color: Colors.grey, letterSpacing: 1.0),
                  ),
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
                              const Text('ABHIJIT MUHURAT (Best Time Today)', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF047857))),
                              const SizedBox(height: 2),
                              Text(abhijit, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: Colors.black)),
                              const SizedBox(height: 2),
                              const Text('Ideal for business launches, signing contracts & important tasks', style: TextStyle(fontSize: 11, color: Colors.black87)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 14),

                  // Choghadiya Table
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
                        const Text('Today\'s Shubh Choghadiya Timings', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.black)),
                        const SizedBox(height: 12),
                        ...choghadiya.map((c) {
                          final String name = c['name'] ?? '';
                          final String time = c['time'] ?? '';
                          final String status = c['status'] ?? 'Neutral';

                          Color badgeColor = Colors.grey;
                          if (status == 'Best' || status == 'Auspicious') {
                            badgeColor = const Color(0xFF059669);
                          } else if (status == 'Avoid') {
                            badgeColor = Colors.red;
                          }

                          return Container(
                            margin: const EdgeInsets.only(bottom: 8),
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFCF7F1),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                                    Text(time, style: const TextStyle(fontSize: 11, color: Colors.grey)),
                                  ],
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: badgeColor.withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    status,
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

                  // 4. Live Celestial Sun & Moon Times
                  const Text(
                    '☀️ CELESTIAL TIMINGS',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w900, color: Colors.grey, letterSpacing: 1.0),
                  ),
                  const SizedBox(height: 10),

                  GridView.count(
                    crossAxisCount: 2,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    childAspectRatio: 2.2,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                    children: [
                      _buildCelestialTile('Sunrise', sunrise, Icons.wb_sunny_rounded, Colors.orange),
                      _buildCelestialTile('Sunset', sunset, Icons.nights_stay_rounded, Colors.indigo),
                      _buildCelestialTile('Moonrise', moonrise, Icons.dark_mode_rounded, Colors.purple),
                      _buildCelestialTile('Moonset', moonset, Icons.wb_twilight_rounded, Colors.teal),
                    ],
                  ),

                  const SizedBox(height: 20),

                  // 5. Panchang 5 Elements Table
                  const Text(
                    '🕉️ PANCHANG 5 ESSENTIAL ELEMENTS',
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
                      children: [
                        _buildPanchangRow('Tithi (Lunar Day)', tithi),
                        const Divider(height: 16),
                        _buildPanchangRow('Vaar (Solar Day)', vaar),
                        const Divider(height: 16),
                        _buildPanchangRow('Nakshatra (Lunar Mansion)', nakshatra),
                        const Divider(height: 16),
                        _buildPanchangRow('Yoga (Solar-Lunar Angle)', yoga),
                        const Divider(height: 16),
                        _buildPanchangRow('Karana (Half Tithi)', karana),
                      ],
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildCelestialTile(String title, String time, IconData icon, Color color) {
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
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(title, style: const TextStyle(fontSize: 11, color: Colors.grey, fontWeight: FontWeight.bold)),
              Text(time, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.black)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPanchangRow(String title, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(title, style: TextStyle(fontSize: 13, color: Colors.grey.shade700, fontWeight: FontWeight.w600)),
        Text(value, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.black)),
      ],
    );
  }
}
