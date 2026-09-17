import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/backend_service.dart';
import 'pandit_chat_screen.dart';
import 'pandit_login_screen.dart';

class PanditDashboardScreen extends StatefulWidget {
  const PanditDashboardScreen({super.key});

  @override
  State<PanditDashboardScreen> createState() => _PanditDashboardScreenState();
}

class _PanditDashboardScreenState extends State<PanditDashboardScreen> {
  bool _isOnline = true;
  bool _isLoading = true;

  Map<String, dynamic>? _activeSession;
  List _waitingQueue = [];

  @override
  void initState() {
    super.initState();
    _loadDashboardData();
  }

  Future<void> _loadDashboardData() async {
    final backendService = Provider.of<BackendService>(context, listen: false);
    final panditId = backendService.currentPandit?['id'] ?? 101;
    final data = await backendService.fetchQueueStatus(panditId: panditId);

    if (mounted) {
      setState(() {
        if (data != null) {
          _activeSession = data['activeSession'];
          _waitingQueue = data['waitingQueue'] ?? [];
        } else {
          // Default mock session for immediate interactive testing
          _activeSession = {
            'id': 1,
            'pandit_id': panditId,
            'user_id': 18,
            'user_name': 'Ananya Sharma',
            'started_at': DateTime.now().subtract(const Duration(minutes: 4, seconds: 32)).toIso8601String(),
          };
          _waitingQueue = [
            {
              'id': 2,
              'user_id': 24,
              'user_name': 'Rahul Verma',
              'queue_position': 1,
              'created_at': DateTime.now().subtract(const Duration(minutes: 8)).toIso8601String(),
            },
            {
              'id': 3,
              'user_id': 31,
              'user_name': 'Priya Patel',
              'queue_position': 2,
              'created_at': DateTime.now().subtract(const Duration(minutes: 15)).toIso8601String(),
            },
          ];
        }
        _isLoading = false;
      });
    }
  }

  Future<void> _toggleOnlineStatus(bool val) async {
    setState(() => _isOnline = val);
    final backendService = Provider.of<BackendService>(context, listen: false);
    await backendService.togglePanditStatus(isOnline: val);
  }

  Future<void> _callNextSeeker() async {
    final backendService = Provider.of<BackendService>(context, listen: false);
    final panditId = backendService.currentPandit?['id'] ?? 101;

    setState(() => _isLoading = true);
    final res = await backendService.nextConsultation(panditId);

    if (mounted) {
      await _loadDashboardData();
      if (res != null && res['activeSession'] != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Connected to Next Seeker: ${res['activeSession']['user_name']}')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final backendService = Provider.of<BackendService>(context);
    final bool isLoggedIn = backendService.isPanditLoggedIn;
    final pandit = backendService.currentPandit ?? backendService.panditProfile ?? {
      'full_name': 'Pt. Rishiraj Sharma',
      'specialty': 'Vedic Kundli & Guna Milan',
      'rate_per_min': 21.00
    };

    if (!isLoggedIn) {
      return Scaffold(
        backgroundColor: const Color(0xFFFCF7F1),
        appBar: AppBar(
          backgroundColor: const Color(0xFFFCF7F1),
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.black),
            onPressed: () => Navigator.pop(context),
          ),
          title: const Text('Pandit Partner Access', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 18)),
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: const BoxDecoration(color: Color(0xFF1E1A38), shape: BoxShape.circle),
                  child: const Icon(Icons.lock_person_rounded, color: Color(0xFFFFD700), size: 48),
                ),
                const SizedBox(height: 20),
                const Text('Pandit Login Required', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.black)),
                const SizedBox(height: 8),
                const Text(
                  'This workspace is restricted strictly to verified Astrologer Partners. Please login with your Pandit Account to manage live consultations.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey, fontSize: 13),
                ),
                const SizedBox(height: 24),
                ElevatedButton.icon(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (context) => const PanditLoginScreen()),
                    );
                  },
                  icon: const Icon(Icons.login_rounded, color: Colors.white),
                  label: const Text('Login to Pandit Account', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFE83D66),
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

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
          'Pandit Dashboard',
          style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 20),
        ),
        actions: [
          Row(
            children: [
              Text(
                _isOnline ? 'ONLINE' : 'OFFLINE',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: _isOnline ? const Color(0xFF059669) : Colors.grey,
                ),
              ),
              Switch(
                value: _isOnline,
                activeColor: const Color(0xFF059669),
                onChanged: _toggleOnlineStatus,
              ),
              IconButton(
                icon: const Icon(Icons.logout_rounded, color: Colors.red),
                tooltip: 'Logout Pandit Account',
                onPressed: () {
                  backendService.logoutPandit();
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Logged out of Pandit Account.')),
                  );
                },
              ),
            ],
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFFE83D66)))
          : RefreshIndicator(
              onRefresh: _loadDashboardData,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Pandit Identity & Earnings Card
                    Container(
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
                        children: [
                          Row(
                            children: [
                              const CircleAvatar(
                                radius: 28,
                                backgroundColor: Color(0xFFFFD700),
                                child: Icon(Icons.person, color: Colors.black, size: 32),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      pandit['full_name'] ?? 'Pt. Rishiraj Sharma',
                                      style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      pandit['specialty'] ?? 'Vedic Kundli Expert',
                                      style: const TextStyle(color: Color(0xFFFFD700), fontSize: 12, fontWeight: FontWeight.bold),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      'Consultation Rate: ₹${pandit['rate_per_min'] ?? 5}/min',
                                      style: const TextStyle(color: Colors.white70, fontSize: 11),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 14),
                          const Divider(color: Colors.white24, height: 1),
                          const SizedBox(height: 12),

                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text('ACCUMULATED EARNINGS', style: TextStyle(color: Color(0xFFFFD700), fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 0.8)),
                                  const SizedBox(height: 2),
                                  Text(
                                    '₹${(pandit['earnings_balance'] ?? 245.00).toString()}',
                                    style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w900),
                                  ),
                                ],
                              ),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  const Text('TOTAL CONSULTED', style: TextStyle(color: Colors.white60, fontSize: 10, fontWeight: FontWeight.bold)),
                                  const SizedBox(height: 2),
                                  Text(
                                    '${pandit['total_minutes_consulted'] ?? 49} Mins',
                                    style: const TextStyle(color: Color(0xFF059669), fontSize: 16, fontWeight: FontWeight.bold),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 24),

                    // Active Consultation Section
                    const Text(
                      '🔴 ACTIVE CONSULTATION SESSION',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w900, color: Colors.grey, letterSpacing: 1.0),
                    ),
                    const SizedBox(height: 10),

                    if (_activeSession != null)
                      Container(
                        padding: const EdgeInsets.all(18),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: const Color(0xFF059669).withValues(alpha: 0.3)),
                          boxShadow: [
                            BoxShadow(color: const Color(0xFF059669).withValues(alpha: 0.05), blurRadius: 10, offset: const Offset(0, 4)),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Container(
                                  width: 10,
                                  height: 10,
                                  decoration: const BoxDecoration(color: Color(0xFF059669), shape: BoxShape.circle),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  'In Live Chat: ${_activeSession!['user_name'] ?? 'Seeker'}',
                                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.black),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'Live 1-on-1 session active · Seeker Kundli ready to inspect',
                              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                            ),
                            const SizedBox(height: 14),

                            SizedBox(
                              width: double.infinity,
                              height: 48,
                              child: ElevatedButton.icon(
                                onPressed: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(builder: (context) => PanditChatScreen(sessionData: _activeSession!)),
                                  );
                                },
                                icon: const Icon(Icons.chat_rounded, color: Colors.white),
                                label: const Text('Open Chat & Inspect Kundli', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF059669),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                                ),
                              ),
                            ),
                          ],
                        ),
                      )
                    else
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: Colors.grey.shade200),
                        ),
                        child: Column(
                          children: const [
                            Icon(Icons.mark_chat_read_rounded, color: Colors.grey, size: 36),
                            SizedBox(height: 8),
                            Text('No Active Session', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                            SizedBox(height: 2),
                            Text('You are currently available for new consultation requests.', style: TextStyle(fontSize: 11, color: Colors.grey)),
                          ],
                        ),
                      ),

                    const SizedBox(height: 24),

                    // Waiting Queue Section
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          '⏳ SEEKERS WAITING QUEUE (${_waitingQueue.length})',
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w900, color: Colors.grey, letterSpacing: 1.0),
                        ),
                        TextButton.icon(
                          onPressed: _waitingQueue.isNotEmpty ? _callNextSeeker : null,
                          icon: const Icon(Icons.skip_next_rounded, size: 18),
                          label: const Text('Call Next Seeker', style: TextStyle(fontWeight: FontWeight.bold)),
                        ),
                      ],
                    ),

                    const SizedBox(height: 8),

                    if (_waitingQueue.isEmpty)
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: Colors.grey.shade200),
                        ),
                        child: const Center(
                          child: Text('No users waiting in queue right now.', style: TextStyle(color: Colors.grey, fontSize: 13)),
                        ),
                      )
                    else
                      ListView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: _waitingQueue.length,
                        itemBuilder: (context, index) {
                          final seeker = _waitingQueue[index];
                          final int pos = seeker['queue_position'] ?? (index + 1);

                          return Container(
                            margin: const EdgeInsets.only(bottom: 10),
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: Colors.grey.shade200),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFE83D66).withValues(alpha: 0.12),
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                      child: Text(
                                        '#$pos',
                                        style: const TextStyle(fontWeight: FontWeight.w900, color: Color(0xFFE83D66), fontSize: 13),
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          seeker['user_name'] ?? 'Seeker Profile',
                                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                                        ),
                                        Text(
                                          'Waiting in line · Est. ${pos * 5} mins',
                                          style: const TextStyle(fontSize: 11, color: Colors.grey),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                                ElevatedButton(
                                  onPressed: _callNextSeeker,
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.black,
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                  ),
                                  child: const Text('Connect', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                  ],
                ),
              ),
            ),
    );
  }
}
