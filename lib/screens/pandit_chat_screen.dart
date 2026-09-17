import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/backend_service.dart';

class PanditChatScreen extends StatefulWidget {
  final Map<String, dynamic> sessionData;
  const PanditChatScreen({super.key, required this.sessionData});

  @override
  State<PanditChatScreen> createState() => _PanditChatScreenState();
}

class _PanditChatScreenState extends State<PanditChatScreen> {
  final TextEditingController _messageController = TextEditingController();
  final List<Map<String, dynamic>> _messages = [];
  Map<String, dynamic>? _seekerKundli;
  bool _isLoadingKundli = true;

  Timer? _timer;
  int _secondsElapsed = 0;

  final List<String> _quickPrompts = [
    '💼 When will my career upgrade?',
    '💍 Check my D9 Navamsha chart',
    '🕉️ Active Dasha & Remedies',
    '❤️ Marriage & Soulmate timing'
  ];

  @override
  void initState() {
    super.initState();
    _loadSeekerKundli();
    _startTimer();

    _messages.add({
      'sender': 'seeker',
      'text': 'Namaste Pandit Ji! Please review my birth chart regarding my career and relationship prospects for 2026.',
      'time': 'Just now',
      'isPrescription': false,
    });
  }

  bool _isBillingPaused = false;

  void _startTimer() {
    _timer = Timer.periodic(const Duration(seconds: 1), (t) async {
      if (!mounted || _isBillingPaused) return;

      setState(() {
        _secondsElapsed++;
      });

      // Trigger minute billing deduction every 60 seconds
      if (_secondsElapsed > 0 && _secondsElapsed % 60 == 0) {
        await _processMinuteDeduction();
      }
    });
  }

  Future<void> _processMinuteDeduction() async {
    final backendService = Provider.of<BackendService>(context, listen: false);
    final panditId = widget.sessionData['pandit_id'] ?? 101;
    final rate = (widget.sessionData['rate_per_min'] ?? 5.0).toDouble();

    final result = await backendService.deductConsultationMinute(panditId: panditId, ratePerMin: rate);

    if (mounted && result != null && result['error'] == 'INSUFFICIENT_BALANCE') {
      setState(() => _isBillingPaused = true);
      _showLowBalanceRechargeModal(rate);
    }
  }

  void _showLowBalanceRechargeModal(double rate) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFFFCF7F1),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Column(
          children: const [
            Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 40),
            SizedBox(height: 6),
            Text('Low Wallet Balance Alert', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Your wallet balance is below ₹${rate.toStringAsFixed(0)}. Consultation is paused. Recharge your wallet to continue live chat with Pandit.',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 13, color: Colors.black87),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () async {
                final backendService = Provider.of<BackendService>(context, listen: false);
                await backendService.rechargeWallet(500);
                if (mounted) {
                  Navigator.pop(ctx);
                  setState(() => _isBillingPaused = false);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('🎉 Wallet recharged with ₹500 (+₹50 Bonus)! Consultation resumed.')),
                  );
                }
              },
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFE83D66)),
              child: const Text('Recharge ₹500 (+10% Bonus)', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ),
            const SizedBox(height: 6),
            TextButton(
              onPressed: () async {
                final backendService = Provider.of<BackendService>(context, listen: false);
                await backendService.rechargeWallet(100);
                if (mounted) {
                  Navigator.pop(ctx);
                  setState(() => _isBillingPaused = false);
                }
              },
              child: const Text('Quick Top-up ₹100', style: TextStyle(color: Colors.black)),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    _messageController.dispose();
    super.dispose();
  }

  String _formatDuration(int sec) {
    final m = sec ~/ 60;
    final s = sec % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  Future<void> _loadSeekerKundli() async {
    final backendService = Provider.of<BackendService>(context, listen: false);
    final userId = widget.sessionData['user_id'] ?? 1;
    final kundli = await backendService.fetchUserKundliForPandit(userId);

    if (mounted) {
      setState(() {
        _seekerKundli = kundli;
        _isLoadingKundli = false;
      });
    }
  }

  void _sendMessage({String? customText}) {
    final text = customText ?? _messageController.text.trim();
    if (text.isEmpty) return;

    if (customText == null) _messageController.clear();

    setState(() {
      _messages.add({
        'sender': 'pandit',
        'text': text,
        'time': 'Just now',
        'isPrescription': false,
      });
    });
  }

  void _showPrescriptionDialog() {
    final gemstoneCtrl = TextEditingController(text: 'Yellow Sapphire (Pukhraj) 5.25 Ratti in Gold Ring');
    final mantraCtrl = TextEditingController(text: 'Om Gram Greem Groum Sah Gurave Namah (108x Thursday mornings)');
    final remedyCtrl = TextEditingController(text: 'Offer Yellow Flowers and Chana Dal to Lord Vishnu on Thursdays');

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFFFCF7F1),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Row(
          children: const [
            Icon(Icons.auto_awesome_rounded, color: Color(0xFFFFD700)),
            SizedBox(width: 8),
            Text('Send Vedic Remedy Card', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Prescribe Astrological Gemstone:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
              const SizedBox(height: 4),
              TextField(
                controller: gemstoneCtrl,
                decoration: InputDecoration(
                  filled: true,
                  fillColor: Colors.white,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                ),
              ),
              const SizedBox(height: 12),
              const Text('Recommended Vedic Mantra:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
              const SizedBox(height: 4),
              TextField(
                controller: mantraCtrl,
                decoration: InputDecoration(
                  filled: true,
                  fillColor: Colors.white,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                ),
              ),
              const SizedBox(height: 12),
              const Text('Planetary Puja / Remedy Ritual:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
              const SizedBox(height: 4),
              TextField(
                controller: remedyCtrl,
                maxLines: 2,
                decoration: InputDecoration(
                  filled: true,
                  fillColor: Colors.white,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton.icon(
            onPressed: () {
              Navigator.pop(ctx);
              setState(() {
                _messages.add({
                  'sender': 'pandit',
                  'text': 'Vedic Prescription',
                  'time': 'Just now',
                  'isPrescription': true,
                  'gemstone': gemstoneCtrl.text.trim(),
                  'mantra': mantraCtrl.text.trim(),
                  'remedy': remedyCtrl.text.trim(),
                });
              });
            },
            icon: const Icon(Icons.send_rounded, size: 16, color: Colors.white),
            label: const Text('Send Prescription', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFD95D39)),
          ),
        ],
      ),
    );
  }

  void _showSeekerKundliDrawer() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final String name = _seekerKundli?['seekerName'] ?? widget.sessionData['user_name'] ?? 'Seeker';
        final String asc = _seekerKundli?['ascendant'] ?? 'Virgo';
        final String moon = _seekerKundli?['moonSign'] ?? 'Gemini';
        final String sun = _seekerKundli?['sunSign'] ?? 'Capricorn';
        final String nakshatra = _seekerKundli?['nakshatra'] ?? 'Mrigashira';
        final int pada = _seekerKundli?['nakshatraPada'] ?? 2;

        final birth = _seekerKundli?['birthDetails'] ?? {};
        final dasha = _seekerKundli?['dashaInfo'] ?? {};
        final List planets = _seekerKundli?['planetaryPositions'] ?? [];

        return Container(
          height: MediaQuery.of(context).size.height * 0.85,
          padding: const EdgeInsets.all(20),
          decoration: const BoxDecoration(
            color: Color(0xFFFCF7F1),
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
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
              const SizedBox(height: 14),

              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.stars_rounded, color: Color(0xFFFFD700), size: 24),
                      const SizedBox(width: 8),
                      Text(
                        '$name\'s Authentic Kundli Chart',
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.black),
                      ),
                    ],
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),

              const SizedBox(height: 14),

              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Summary Card
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFF1E1A38), Color(0xFF2E2452)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(18),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Lagna: $asc | Moon Sign: $moon',
                              style: const TextStyle(color: Color(0xFFFFD700), fontSize: 16, fontWeight: FontWeight.w900),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Sun Sign: $sun · Nakshatra: $nakshatra (Pada $pada)',
                              style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'DOB: ${birth['dateOfBirth'] ?? '2000-01-18'} at ${birth['timeOfBirth'] ?? '16:15'} (${birth['placeOfBirth'] ?? 'Delhi, India'})',
                              style: const TextStyle(color: Colors.white70, fontSize: 11),
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 16),

                      // Dasha Period Card
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: const Color(0xFF9C27B0).withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: const Color(0xFF9C27B0).withValues(alpha: 0.2)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('ACTIVE DASHA PERIOD', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF9C27B0))),
                            const SizedBox(height: 4),
                            Text(
                              'Mahadasha: ${dasha['currentMahadasha'] ?? 'Jupiter'} · Antardasha: ${dasha['antardasha'] ?? 'Venus'}',
                              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.black),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Period valid until: ${dasha['dashaEndDate'] ?? '2030-05-15'}',
                              style: const TextStyle(fontSize: 11, color: Colors.grey),
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 16),

                      const Text('Planetary Positions Table', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                      const SizedBox(height: 8),

                      Container(
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: Colors.grey.shade200),
                        ),
                        child: ListView.separated(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: planets.length,
                          separatorBuilder: (ctx, i) => const Divider(height: 1),
                          itemBuilder: (ctx, i) {
                            final p = planets[i];
                            return Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    p['planet'] ?? 'Planet',
                                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                                  ),
                                  Text(
                                    '${p['sign']} (${p['degree']}°)',
                                    style: const TextStyle(fontSize: 13, color: Colors.black87),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: Colors.grey.shade100,
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(
                                      'House ${p['house']}',
                                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.grey),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _endConsultation() async {
    final backendService = Provider.of<BackendService>(context, listen: false);
    final panditId = widget.sessionData['pandit_id'] ?? 101;

    double ratingVal = 5.0;
    final reviewTextCtrl = TextEditingController(text: 'Accurate Janam Kundli insights & very helpful remedy guidance!');

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) => AlertDialog(
          backgroundColor: const Color(0xFFFCF7F1),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          title: Column(
            children: const [
              Icon(Icons.star_rounded, color: Color(0xFFFFC107), size: 36),
              SizedBox(height: 6),
              Text('Rate Consultation Experience', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('How was your astrological session with Pandit?', style: TextStyle(fontSize: 12, color: Colors.grey)),
              const SizedBox(height: 12),

              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(5, (i) {
                  final starNum = i + 1;
                  return IconButton(
                    icon: Icon(
                      starNum <= ratingVal ? Icons.star_rounded : Icons.star_outline_rounded,
                      color: const Color(0xFFFFC107),
                      size: 32,
                    ),
                    onPressed: () => setModalState(() => ratingVal = starNum.toDouble()),
                  );
                }),
              ),

              const SizedBox(height: 10),

              TextField(
                controller: reviewTextCtrl,
                maxLines: 2,
                decoration: InputDecoration(
                  hintText: 'Write feedback or review for Pandit...',
                  filled: true,
                  fillColor: Colors.white,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Skip Review', style: TextStyle(color: Colors.grey)),
            ),
            ElevatedButton(
              onPressed: () async {
                await backendService.submitPanditReview(
                  panditId: panditId,
                  rating: ratingVal,
                  reviewText: reviewTextCtrl.text.trim(),
                );
                Navigator.pop(ctx);
              },
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFE83D66)),
              child: const Text('Submit Rating', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );

    await backendService.nextConsultation(panditId);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Consultation completed & review recorded in Neon DB!')),
      );
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final seekerName = widget.sessionData['user_name'] ?? 'Seeker Profile';
    final double totalBill = ((_secondsElapsed / 60) * 21.0);

    return Scaffold(
      backgroundColor: const Color(0xFFFCF7F1),
      appBar: AppBar(
        backgroundColor: const Color(0xFFFCF7F1),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.black),
          onPressed: () => Navigator.pop(context),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Chat with $seekerName',
              style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 16),
            ),
            Row(
              children: [
                const Icon(Icons.timer_rounded, color: Color(0xFF059669), size: 12),
                const SizedBox(width: 4),
                Text(
                  '${_formatDuration(_secondsElapsed)} · ₹${totalBill.toStringAsFixed(1)}',
                  style: const TextStyle(color: Color(0xFF059669), fontSize: 11, fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.auto_awesome_rounded, color: Color(0xFFD95D39)),
            tooltip: 'Send Remedy Prescription',
            onPressed: _showPrescriptionDialog,
          ),
          IconButton(
            icon: const Icon(Icons.menu_book_rounded, color: Color(0xFFE83D66)),
            tooltip: 'Inspect Seeker Kundli',
            onPressed: _showSeekerKundliDrawer,
          ),
          TextButton(
            onPressed: _endConsultation,
            child: const Text('End Chat', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
      body: Column(
        children: [
          // Banner for Inspect Kundli Drawer & Remedy Prescriber CTA
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            color: const Color(0xFFFFD700).withValues(alpha: 0.15),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                GestureDetector(
                  onTap: _showSeekerKundliDrawer,
                  child: Row(
                    children: const [
                      Icon(Icons.stars_rounded, color: Color(0xFFD97706), size: 18),
                      SizedBox(width: 6),
                      Text('Inspect Kundli Chart', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFFB45309))),
                    ],
                  ),
                ),
                GestureDetector(
                  onTap: _showPrescriptionDialog,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFFD95D39),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      children: const [
                        Icon(Icons.auto_awesome_rounded, color: Colors.white, size: 12),
                        SizedBox(width: 4),
                        Text('Prescribe Remedy', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white)),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),

          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _messages.length,
              itemBuilder: (context, index) {
                final msg = _messages[index];
                final isPandit = msg['sender'] == 'pandit';
                final isPrescription = msg['isPrescription'] == true;

                if (isPrescription) {
                  return Container(
                    margin: const EdgeInsets.only(bottom: 14),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF1E1A38), Color(0xFF2E2452)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: const Color(0xFFFFD700)),
                      boxShadow: [
                        BoxShadow(color: const Color(0xFFFFD700).withValues(alpha: 0.15), blurRadius: 10),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: const [
                            Icon(Icons.auto_awesome_rounded, color: Color(0xFFFFD700), size: 18),
                            SizedBox(width: 8),
                            Text('OFFICIAL VEDIC ASTROLOGICAL PRESCRIPTION', style: TextStyle(color: Color(0xFFFFD700), fontSize: 11, fontWeight: FontWeight.w900, letterSpacing: 0.8)),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Text('💎 Gemstone: ${msg['gemstone']}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                        const SizedBox(height: 4),
                        Text('🕉️ Mantra: ${msg['mantra']}', style: const TextStyle(color: Colors.white70, fontSize: 12)),
                        const SizedBox(height: 4),
                        Text('🌿 Remedy: ${msg['remedy']}', style: const TextStyle(color: Colors.white70, fontSize: 12)),
                      ],
                    ),
                  );
                }

                return Align(
                  alignment: isPandit ? Alignment.centerRight : Alignment.centerLeft,
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.all(14),
                    constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
                    decoration: BoxDecoration(
                      color: isPandit ? Colors.black : Colors.white,
                      borderRadius: BorderRadius.circular(18),
                      border: isPandit ? null : Border.all(color: Colors.grey.shade200),
                    ),
                    child: Column(
                      crossAxisAlignment: isPandit ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                      children: [
                        Text(
                          msg['text'] ?? '',
                          style: TextStyle(
                            color: isPandit ? Colors.white : Colors.black,
                            fontSize: 14,
                            height: 1.4,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          msg['time'] ?? '',
                          style: TextStyle(
                            color: isPandit ? Colors.white60 : Colors.grey,
                            fontSize: 10,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),

          // Quick Question Chips Bar
          Container(
            height: 38,
            color: Colors.white,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              itemCount: _quickPrompts.length,
              itemBuilder: (context, index) {
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ActionChip(
                    backgroundColor: const Color(0xFFFCF7F1),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    label: Text(_quickPrompts[index], style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.black87)),
                    onPressed: () => _sendMessage(customText: _quickPrompts[index]),
                  ),
                );
              },
            ),
          ),

          // Message Input Field
          Container(
            padding: const EdgeInsets.all(12),
            color: Colors.white,
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _messageController,
                    decoration: InputDecoration(
                      hintText: 'Type astrological guidance...',
                      filled: true,
                      fillColor: const Color(0xFFFCF7F1),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.send_rounded, color: Color(0xFFE83D66)),
                  onPressed: () => _sendMessage(),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
