import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../services/backend_service.dart';
import '../utils/session_messages.dart';
import 'seeker_session_chat_screen.dart';

double _toDouble(dynamic v, [double fallback = 0]) {
  if (v is num) return v.toDouble();
  if (v is String) return double.tryParse(v) ?? fallback;
  return fallback;
}

int _toInt(dynamic v, [int fallback = 0]) {
  if (v is int) return v;
  if (v is num) return v.toInt();
  if (v is String) return int.tryParse(v) ?? double.tryParse(v)?.toInt() ?? fallback;
  return fallback;
}

class ConsultationLobbyScreen extends StatefulWidget {
  /// Response of `POST /pandit/request` (status 'waiting') merged with the
  /// Pandit's display info (panditName, specialty, avatarUrl, ratePerMin).
  final Map<String, dynamic> initialQueueData;
  const ConsultationLobbyScreen({super.key, required this.initialQueueData});

  @override
  State<ConsultationLobbyScreen> createState() => _ConsultationLobbyScreenState();
}

class _ConsultationLobbyScreenState extends State<ConsultationLobbyScreen> {
  static const Duration _pollInterval = Duration(seconds: 4);
  static const int _maxSilentFailures = 3;

  Timer? _pollingTimer;
  Timer? _countdownTimer;

  late Map<String, dynamic> _lobbyData;
  int _secondsRemaining = 300;
  int _lastQueuePos = -1;
  bool _audioVibrateEnabled = true;
  bool _isPolling = false;
  int _consecutiveFailures = 0;
  bool _hasExited = false;

  @override
  void initState() {
    super.initState();
    _lobbyData = Map<String, dynamic>.from(widget.initialQueueData);
    _resetCountdownIfPositionChanged();
    _startCountdown();
    _pollingTimer = Timer.periodic(_pollInterval, (_) => _pollQueueStatus());
  }

  @override
  void dispose() {
    _stopTimers();
    super.dispose();
  }

  void _stopTimers() {
    _pollingTimer?.cancel();
    _countdownTimer?.cancel();
    _pollingTimer = null;
    _countdownTimer = null;
  }

  int get _queuePos => _toInt(_lobbyData['queuePosition'] ?? _lobbyData['session']?['queue_position'], 1);

  /// Re-estimates the countdown whenever our position in the line changes.
  void _resetCountdownIfPositionChanged() {
    final pos = _queuePos;
    if (pos == _lastQueuePos) return;
    _lastQueuePos = pos;
    final waitMins = _toInt(_lobbyData['estimatedWaitMins'], pos * 5);
    _secondsRemaining = (waitMins * 60).clamp(30, 3600);
  }

  void _startCountdown() {
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      if (_secondsRemaining > 0) {
        setState(() => _secondsRemaining--);
      }
    });
  }

  Future<void> _pollQueueStatus() async {
    if (_isPolling || _hasExited || !mounted) return;
    _isPolling = true;
    Map<String, dynamic>? statusData;
    try {
      statusData = await Provider.of<BackendService>(context, listen: false).fetchQueueStatus();
    } catch (_) {
      statusData = null;
    } finally {
      _isPolling = false;
    }
    if (!mounted || _hasExited) return;

    if (statusData == null) {
      setState(() => _consecutiveFailures++);
      return;
    }

    final status = statusData['status']?.toString();

    if (status == 'idle') {
      // Our queue token no longer exists (cancelled or closed by the Pandit).
      _exitWithMessage(
        title: 'Queue token closed',
        message: 'Your place in the queue is no longer active. Please request a new consultation.',
      );
      return;
    }

    setState(() {
      _consecutiveFailures = 0;
      // Keep display fields from the initial request if the poll lacks them.
      _lobbyData = {..._lobbyData, ...statusData!};
      _resetCountdownIfPositionChanged();
    });

    if (status == 'active' || (status == 'waiting' && _queuePos <= 0)) {
      _enterConsultation(statusData);
    }
  }

  Future<void> _alertUser() async {
    if (!_audioVibrateEnabled) return;
    try {
      await HapticFeedback.heavyImpact();
      await SystemSound.play(SystemSoundType.alert);
    } catch (_) {
      // Haptics/sound are best-effort only.
    }
  }

  void _enterConsultation(Map<String, dynamic> statusData) {
    if (_hasExited) return;
    _hasExited = true;
    _stopTimers();
    _alertUser();

    final session = statusData['session'];
    final panditName = (statusData['panditName'] ?? _lobbyData['panditName'] ?? 'Pandit').toString();

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$panditName is ready! Entering consultation now...'),
        backgroundColor: const Color(0xFF059669),
      ),
    );

    final sessionMap = session is Map
        ? Map<String, dynamic>.from(session)
        : (_lobbyData['session'] is Map ? Map<String, dynamic>.from(_lobbyData['session'] as Map) : <String, dynamic>{});

    // Enter the real Pandit <-> seeker session chat (not the AI chatbot).
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => SeekerSessionChatScreen(
          session: sessionMap,
          panditName: panditName,
          specialty: (statusData['specialty'] ?? _lobbyData['specialty'] ?? 'Vedic Astrology').toString(),
          avatarUrl: (statusData['avatarUrl'] ?? _lobbyData['avatarUrl'] ?? '').toString(),
          ratePerMin: _toDouble(statusData['ratePerMin'] ?? _lobbyData['ratePerMin']),
        ),
      ),
    );
  }

  int? get _sessionId => parseId(_lobbyData['session'] is Map ? (_lobbyData['session'] as Map)['id'] : null);

  Future<void> _exitWithMessage({required String title, required String message}) async {
    if (_hasExited) return;
    _hasExited = true;
    _stopTimers();
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          ElevatedButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK')),
        ],
      ),
    );
    if (mounted) Navigator.pop(context);
  }

  Future<void> _confirmLeaveQueue() async {
    final pos = _queuePos;
    final leave = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Leave the queue?'),
        content: Text('Are you sure you want to step out of the waiting queue? You will lose your current spot (#$pos).'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Keep Spot')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Leave Queue', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (leave != true || !mounted || _hasExited) return;
    _hasExited = true;
    _stopTimers();
    final backendService = Provider.of<BackendService>(context, listen: false);
    Navigator.pop(context);
    // Free our spot on the server. Best effort: the screen is already closed, and
    // a stale entry is reused (not duplicated) if the seeker requests again.
    unawaited(backendService.cancelConsultation(sessionId: _sessionId));
  }

  String _formatTimer(int totalSec) {
    final m = totalSec ~/ 60;
    final s = totalSec % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  String _activeSessionLabel() {
    final info = _lobbyData['activeSessionInfo'];
    if (info is Map) {
      final started = DateTime.tryParse(info['startedAt']?.toString() ?? '');
      if (started != null) {
        final mins = DateTime.now().difference(started.toLocal()).inMinutes;
        return 'Pandit is consulting another seeker · ${mins < 1 ? 'just started' : '$mins min in'}';
      }
      return 'Pandit is consulting another seeker right now';
    }
    return 'Pandit will connect with you as soon as possible';
  }

  @override
  Widget build(BuildContext context) {
    final backendService = Provider.of<BackendService>(context);
    final userKundli = backendService.kundliData;
    final selectedFamily = backendService.selectedFamilyMember;

    final String panditName = (_lobbyData['panditName'] ?? 'Pandit').toString();
    final String specialty = (_lobbyData['specialty'] ?? 'Vedic Astrology').toString();
    final String avatarUrl = (_lobbyData['avatarUrl'] ?? '').toString();
    final double ratePerMin = _toDouble(_lobbyData['ratePerMin'], 21);
    final int queuePos = _queuePos;
    final int totalWaiting = _toInt(_lobbyData['totalWaiting'], queuePos);
    final bool overdue = _secondsRemaining <= 0;

    final String seekerDisplayName = selectedFamily != null
        ? '${selectedFamily['fullName'] ?? 'Family member'} (${selectedFamily['relationship'] ?? 'Family'})'
        : (userKundli?['birthDetails']?['fullName'] ?? backendService.user?['fullName'] ?? 'You').toString();
    final bool hasKundli = userKundli != null && userKundli['ascendant'] != null;

    return PopScope(
      canPop: _hasExited,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _confirmLeaveQueue();
      },
      child: Scaffold(
        backgroundColor: const Color(0xFFFCF7F1),
        appBar: AppBar(
          backgroundColor: const Color(0xFFFCF7F1),
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.black),
            tooltip: 'Leave queue',
            onPressed: _confirmLeaveQueue,
          ),
          title: const Text(
            'Consultation Lobby',
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 18),
          ),
          actions: [
            IconButton(
              tooltip: _audioVibrateEnabled ? 'Mute turn alert' : 'Enable turn alert',
              icon: Icon(
                _audioVibrateEnabled ? Icons.notifications_active_rounded : Icons.notifications_off_rounded,
                color: _audioVibrateEnabled ? const Color(0xFFE83D66) : Colors.grey,
              ),
              onPressed: () {
                setState(() => _audioVibrateEnabled = !_audioVibrateEnabled);
                ScaffoldMessenger.of(context).hideCurrentSnackBar();
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(_audioVibrateEnabled
                        ? 'We will vibrate and play a sound when it is your turn.'
                        : 'Turn alert muted.'),
                    duration: const Duration(seconds: 2),
                  ),
                );
              },
            ),
          ],
        ),
        body: SafeArea(
          top: false,
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                if (_consecutiveFailures >= _maxSilentFailures)
                  Container(
                    width: double.infinity,
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.orange.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Row(
                      children: [
                        SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.orange)),
                        SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Connection issue – reconnecting to the queue. Your spot is safe.',
                            style: TextStyle(fontSize: 12, color: Colors.black87),
                          ),
                        ),
                      ],
                    ),
                  ),

                // 1. Live Countdown Clock
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
                              'QUEUE POSITION #$queuePos',
                              style: const TextStyle(color: Color(0xFFFFD700), fontSize: 12, fontWeight: FontWeight.w900, letterSpacing: 1.0),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 18),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          overdue ? 'Any moment' : _formatTimer(_secondsRemaining),
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: overdue ? 34 : 48,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 2.0,
                          ),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        overdue
                            ? 'Taking a little longer than estimated. Please stay on this screen – we will connect you automatically.'
                            : queuePos <= 1
                                ? 'You are next in line! The Pandit is finishing the current session.'
                                : 'Estimated wait · ${queuePos - 1} seeker${queuePos - 1 == 1 ? '' : 's'} ahead of you ($totalWaiting waiting)',
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.white70, fontSize: 12, height: 1.4),
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
                            backgroundColor: const Color(0xFFFFF7ED),
                            foregroundImage: avatarUrl.startsWith('http') ? NetworkImage(avatarUrl) : null,
                            onForegroundImageError: avatarUrl.startsWith('http') ? (_, __) {} : null,
                            child: const Icon(Icons.person_rounded, color: Color(0xFFFB9548)),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(panditName,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.black)),
                                const SizedBox(height: 2),
                                Text(specialty,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontSize: 12, color: Color(0xFFD95D39), fontWeight: FontWeight.bold)),
                                const SizedBox(height: 4),
                                Text(
                                  'Rate: ₹${ratePerMin.toStringAsFixed(ratePerMin % 1 == 0 ? 0 : 2)}/min · 1-on-1 Consultation',
                                  style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                                ),
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
                          Expanded(
                            child: Text(
                              _activeSessionLabel(),
                              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF047857)),
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
                        children: [
                          const Expanded(
                            child: Text('KUNDLI SHARED FOR THIS SESSION',
                                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900, color: Colors.grey, letterSpacing: 0.8)),
                          ),
                          Icon(
                            hasKundli ? Icons.check_circle_rounded : Icons.info_outline_rounded,
                            color: hasKundli ? const Color(0xFF059669) : Colors.orange,
                            size: 18,
                          ),
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
                                  Text(seekerDisplayName,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.black)),
                                  const SizedBox(height: 2),
                                  Text(
                                    hasKundli
                                        ? 'Lagna: ${userKundli['ascendant']} · Moon: ${userKundli['moonSign'] ?? '—'}'
                                        : 'Birth chart not generated yet',
                                    style: const TextStyle(fontSize: 11, color: Colors.grey),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        hasKundli
                            ? 'The Pandit will review this chart as soon as your chat opens.'
                            : 'Tip: share your date, time and place of birth in the chat for an accurate reading.',
                        style: const TextStyle(fontSize: 11, color: Colors.grey),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 28),

                OutlinedButton.icon(
                  onPressed: _confirmLeaveQueue,
                  icon: const Icon(Icons.exit_to_app_rounded, color: Colors.red, size: 18),
                  label: const Text('Leave Queue', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Colors.red),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
