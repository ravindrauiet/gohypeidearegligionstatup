import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/backend_service.dart';

class ConsultationLobbyScreen extends StatefulWidget {
  final Map<String, dynamic> initialQueueData;
  const ConsultationLobbyScreen({super.key, required this.initialQueueData});

  @override
  State<ConsultationLobbyScreen> createState() => _ConsultationLobbyScreenState();
}

class _ConsultationLobbyScreenState extends State<ConsultationLobbyScreen> {
  Timer? _pollingTimer;
  Timer? _countdownTimer;

  late Map<String, dynamic> _lobbyData;
  int _secondsRemaining = 300; // 5 mins initial countdown
  bool _audioVibrateEnabled = true;

  @override
  void initState() {
    super.initState();
    _lobbyData = widget.initialQueueData;

    final int waitMins = _lobbyData['estimatedWaitMins'] ?? 5;
    _secondsRemaining = (waitMins * 60).clamp(30, 1800);

    _startCountdown();
    _startQueuePolling();
  }

  void _startCountdown() {
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (mounted && _secondsRemaining > 0) {
        setState(() {
          _secondsRemaining--;
        });
      }
    });
  }

  void _startQueuePolling() {
    _pollingTimer = Timer.periodic(const Duration(seconds: 3), (t) async {
      final backendService = Provider.of<BackendService>(context, listen: false);
      final statusData = await backendService.fetchQueueStatus();

      if (mounted && statusData != null) {
        setState(() {
          _lobbyData = statusData;
        });

        // Auto-redirect to live chat when position becomes active!
        if (statusData['status'] == 'active' || (statusData['queuePosition'] ?? 1) == 0) {
          _pollingTimer?.cancel();
          _countdownTimer?.cancel();

          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('🎉 Pandit ${statusData['panditName'] ?? ''} is ready! Entering consultation now...'),
              backgroundColor: const Color(0xFF059669),
            ),
          );

          final astroData = {
            'id': statusData['session']?['pandit_id'] ?? 101,
            'name': statusData['panditName'] ?? 'Pt. Rishiraj Sharma',
            'specialty': statusData['specialty'] ?? 'Vedic Kundli Advisor',
            'imageUrl': statusData['avatarUrl'] ?? '',
            'ratePerMin': statusData['ratePerMin'] ?? 21.0,
          };

          Navigator.pushReplacementNamed(context, '/chatbot', arguments: astroData);
        }
      }
    });
  }

  @override
  void dispose() {
    _pollingTimer?.cancel();
    _countdownTimer?.cancel();
    super.dispose();
  }

  String _formatTimer(int totalSec) {
    final m = totalSec ~/ 60;
    final s = totalSec % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final backendService = Provider.of<BackendService>(context);
    final userKundli = backendService.kundliData;
    final selectedFamily = backendService.selectedFamilyMember;

    final String panditName = _lobbyData['panditName'] ?? 'Pt. Rishiraj Sharma';
    final String specialty = _lobbyData['specialty'] ?? 'Vedic Kundli & Guna Milan';
    final String avatarUrl = _lobbyData['avatarUrl'] ?? 'https://images.unsplash.com/photo-1507003211169-0a1dd7228f2d?auto=format&fit=crop&w=300&q=80';
    final double ratePerMin = (_lobbyData['ratePerMin'] ?? 21.0).toDouble();
    final int queuePos = _lobbyData['queuePosition'] ?? 1;
    final int totalWaiting = _lobbyData['totalWaiting'] ?? 1;

    final String seekerDisplayName = selectedFamily != null
        ? '${selectedFamily['fullName']} (${selectedFamily['relationship']})'
        : (userKundli?['birthDetails']?['fullName'] ?? 'Primary Self');

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
          'Live Consultation Lobby',
          style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 18),
        ),
        actions: [
          IconButton(
            icon: Icon(
              _audioVibrateEnabled ? Icons.notifications_active_rounded : Icons.notifications_off_rounded,
              color: _audioVibrateEnabled ? const Color(0xFFE83D66) : Colors.grey,
            ),
            onPressed: () {
              setState(() => _audioVibrateEnabled = !_audioVibrateEnabled);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(_audioVibrateEnabled ? 'Notification Alert Enabled for your turn!' : 'Alerts Muted'),
                  duration: const Duration(seconds: 1),
                ),
              );
            },
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            // 1. Live Countdown Clock Widget
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF1E1A38), Color(0xFF2E2452)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(28),
                boxShadow: [
                  BoxShadow(color: const Color(0xFF1E1A38).withValues(alpha: 0.2), blurRadius: 14, offset: const Offset(0, 6)),
                ],
              ),
              child: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFD700).withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: const Color(0xFFFFD700)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.confirmation_number_rounded, color: Color(0xFFFFD700), size: 16),
                        const SizedBox(width: 6),
                        Text(
                          'QUEUE TOKEN #$queuePos',
                          style: const TextStyle(color: Color(0xFFFFD700), fontSize: 12, fontWeight: FontWeight.w900, letterSpacing: 1.0),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 18),

                  Text(
                    _formatTimer(_secondsRemaining),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 48,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 2.0,
                    ),
                  ),

                  const SizedBox(height: 4),

                  Text(
                    queuePos == 1
                        ? '🔥 You are next in line! Pandit is finishing the current session.'
                        : 'Est. Wait Time · $queuePos Users in line ($totalWaiting total waiting)',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            // 2. Pandit Profile & Activity Card
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: Colors.grey.shade200),
                boxShadow: [
                  BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 10, offset: const Offset(0, 4)),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      CircleAvatar(
                        radius: 26,
                        backgroundImage: NetworkImage(avatarUrl),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(panditName, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.black)),
                            const SizedBox(height: 2),
                            Text(specialty, style: const TextStyle(fontSize: 12, color: Color(0xFFD95D39), fontWeight: FontWeight.bold)),
                            const SizedBox(height: 4),
                            Text('Rate: ₹$ratePerMin/min · 1-on-1 Consultation', style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
                          ],
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 14),
                  const Divider(height: 1),
                  const SizedBox(height: 12),

                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(6),
                        decoration: const BoxDecoration(color: Color(0xFF059669), shape: BoxShape.circle),
                        child: const Icon(Icons.bolt_rounded, color: Colors.white, size: 14),
                      ),
                      const SizedBox(width: 10),
                      const Expanded(
                        child: Text(
                          'Pandit is in Session #1 · Live chart sync enabled',
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF047857)),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            // 3. Pre-Consultation Seeker Kundli Card
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: const [
                      Text('SHARED KUNDLI CHART FOR SESSION', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900, color: Colors.grey, letterSpacing: 0.8)),
                      Icon(Icons.check_circle_rounded, color: Color(0xFF059669), size: 18),
                    ],
                  ),
                  const SizedBox(height: 10),

                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFCF7F1),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.grey.shade300),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.account_box_rounded, color: Color(0xFF7C77E6), size: 24),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(seekerDisplayName, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.black)),
                              const SizedBox(height: 2),
                              Text(
                                'Lagna: ${userKundli?['ascendant'] ?? 'Virgo'} · Moon: ${userKundli?['moonSign'] ?? 'Gemini'}',
                                style: const TextStyle(fontSize: 11, color: Colors.grey),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text('Pandit will inspect this authentic chart as soon as chat opens.', style: TextStyle(fontSize: 10, color: Colors.grey)),
                ],
              ),
            ),

            const SizedBox(height: 28),

            // Leave Queue Button
            OutlinedButton.icon(
              onPressed: () {
                showDialog(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text('Cancel Queue Token?'),
                    content: const Text('Are you sure you want to step out of the waiting queue? You will lose your current spot (#1 token).'),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Keep Spot')),
                      ElevatedButton(
                        onPressed: () {
                          Navigator.pop(ctx);
                          Navigator.pop(context);
                        },
                        style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                        child: const Text('Leave Queue', style: TextStyle(color: Colors.white)),
                      ),
                    ],
                  ),
                );
              },
              icon: const Icon(Icons.exit_to_app_rounded, color: Colors.red, size: 18),
              label: const Text('Leave Queue / Cancel Token', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: Colors.red),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
