import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/backend_service.dart';
import 'pandit_chat_screen.dart';
import 'pandit_login_screen.dart';

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

bool _toBool(dynamic v, [bool fallback = false]) {
  if (v is bool) return v;
  if (v is String) return v.toLowerCase() == 'true';
  if (v is num) return v != 0;
  return fallback;
}

class PanditDashboardScreen extends StatefulWidget {
  const PanditDashboardScreen({super.key});

  @override
  State<PanditDashboardScreen> createState() => _PanditDashboardScreenState();
}

class _PanditDashboardScreenState extends State<PanditDashboardScreen> {
  static const Duration _pollInterval = Duration(seconds: 10);

  bool _isOnline = true;
  bool _isTogglingStatus = false;
  bool _isLoading = true;
  bool _isActionBusy = false;
  bool _isFetching = false;
  String? _loadError;

  Map<String, dynamic>? _activeSession;
  List<Map<String, dynamic>> _waitingQueue = [];
  Timer? _pollTimer;

  /// Recent payouts credited to this Pandit (null until loaded / on failure).
  List<Map<String, dynamic>>? _payouts;
  bool _payoutsFailed = false;

  @override
  void initState() {
    super.initState();
    final pandit = Provider.of<BackendService>(context, listen: false).currentPandit;
    _isOnline = _toBool(pandit?['is_online'], true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _loadDashboardData();
      _pollTimer = Timer.periodic(_pollInterval, (_) => _loadDashboardData(silent: true));
    });
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  dynamic get _panditId => Provider.of<BackendService>(context, listen: false).currentPandit?['id'];

  /// Loads the active session & waiting queue for the logged-in Pandit.
  /// [silent] is used by background polling: failures keep the last good data.
  Future<void> _loadDashboardData({bool silent = false}) async {
    if (_isFetching) return;
    final backendService = Provider.of<BackendService>(context, listen: false);
    if (!backendService.isPanditLoggedIn) return;

    final panditId = _panditId;
    if (panditId == null) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _loadError = 'Your Pandit profile could not be found. Please log in again.';
        });
      }
      return;
    }

    _isFetching = true;
    Map<String, dynamic>? data;
    try {
      data = await backendService.fetchQueueStatus(panditId: panditId);
      // Fresh earnings / minutes on explicit loads (not every background poll).
      if (!silent) {
        await backendService.refreshPanditProfile();
        unawaited(_loadPayouts());
      }
    } catch (_) {
      data = null;
    } finally {
      _isFetching = false;
    }

    if (!mounted) return;

    if (data == null) {
      if (silent) return;
      final hadData = !_isLoading && _loadError == null;
      setState(() {
        _isLoading = false;
        if (!hadData) {
          _loadError = 'Could not load your consultation queue. Check your connection and try again.';
        }
      });
      if (hadData) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not refresh the queue. Showing last known data.')),
        );
      }
      return;
    }

    final active = data['activeSession'];
    final waiting = data['waitingQueue'];
    setState(() {
      _activeSession = active is Map ? Map<String, dynamic>.from(active) : null;
      _waitingQueue = waiting is List
          ? waiting.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList()
          : <Map<String, dynamic>>[];
      _isLoading = false;
      _loadError = null;
    });
  }

  Future<void> _loadPayouts() async {
    final backendService = Provider.of<BackendService>(context, listen: false);
    List<Map<String, dynamic>>? list;
    try {
      list = await backendService.fetchWalletTransactions(asPandit: true);
    } catch (_) {
      list = null;
    }
    if (!mounted) return;
    setState(() {
      _payoutsFailed = list == null;
      if (list != null) {
        _payouts = list.where((t) => t['direction'] == 'credit' && t['type'] != 'recharge').take(5).toList();
      }
    });
  }

  Widget _buildPayouts() {
    final payouts = _payouts;
    Widget body;
    if (payouts == null) {
      body = _payoutsFailed
          ? Row(
              children: [
                const Expanded(
                  child: Text('Could not load recent payouts.', style: TextStyle(fontSize: 12, color: Colors.grey)),
                ),
                TextButton(onPressed: _loadPayouts, child: const Text('Retry')),
              ],
            )
          : const Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)));
    } else if (payouts.isEmpty) {
      body = const Text('No payouts yet. Completed consultations are credited here.',
          style: TextStyle(fontSize: 12, color: Colors.grey));
    } else {
      body = Column(
        children: [
          for (final t in payouts)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                children: [
                  const Icon(Icons.south_west_rounded, size: 16, color: Color(0xFF059669)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      (t['description'] ?? 'Consultation payout').toString(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12, color: Colors.black87),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '+₹${_toDouble(t['amount']).toStringAsFixed(2)}',
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF059669)),
                  ),
                ],
              ),
            ),
        ],
      );
    }
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: body,
    );
  }

  Future<void> _toggleOnlineStatus(bool val) async {
    if (_isTogglingStatus) return;
    final previous = _isOnline;
    setState(() {
      _isOnline = val;
      _isTogglingStatus = true;
    });
    final backendService = Provider.of<BackendService>(context, listen: false);
    bool ok;
    try {
      ok = await backendService.togglePanditStatus(isOnline: val);
    } catch (_) {
      ok = false;
    }
    if (!mounted) return;
    setState(() {
      _isTogglingStatus = false;
      if (!ok) _isOnline = previous;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(ok
            ? (val ? 'You are now ONLINE and visible to seekers.' : 'You are now OFFLINE.')
            : (backendService.lastError ?? 'Could not update your status. Please try again.')),
        backgroundColor: ok ? null : Colors.red,
      ),
    );
  }

  Future<bool> _confirm({required String title, required String message, required String confirmLabel}) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFE83D66)),
            child: Text(confirmLabel, style: const TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    return result == true;
  }

  /// Completes the current active session (if any) and connects the next
  /// waiting seeker. The backend always takes seekers in queue order.
  Future<void> _advanceQueue({required bool endingOnly}) async {
    if (_isActionBusy) return;
    final panditId = _panditId;
    if (panditId == null) return;

    final activeName = (_activeSession?['user_name'] ?? 'the current seeker').toString();
    if (_activeSession != null) {
      final confirmed = await _confirm(
        title: endingOnly ? 'End consultation?' : 'Connect next seeker?',
        message: endingOnly
            ? 'This will mark your session with $activeName as completed.'
                '${_waitingQueue.isNotEmpty ? ' The next seeker in line will be connected automatically.' : ''}'
            : 'This will end your current session with $activeName and connect the next seeker in line.',
        confirmLabel: endingOnly ? 'End Session' : 'Connect Next',
      );
      if (!confirmed || !mounted) return;
    }

    setState(() => _isActionBusy = true);
    final backendService = Provider.of<BackendService>(context, listen: false);
    Map<String, dynamic>? res;
    try {
      res = await backendService.nextConsultation(panditId);
    } catch (_) {
      res = null;
    }
    if (!mounted) return;

    if (res == null) {
      setState(() => _isActionBusy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Action failed. Please check your connection and try again.'), backgroundColor: Colors.red),
      );
      return;
    }

    await _loadDashboardData();
    if (!mounted) return;
    setState(() => _isActionBusy = false);

    final next = res['activeSession'];
    if (next is Map) {
      final nextSession = Map<String, dynamic>.from(next);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Connected to ${nextSession['user_name'] ?? 'next seeker'}'),
          backgroundColor: const Color(0xFF059669),
          action: SnackBarAction(
            label: 'OPEN CHAT',
            textColor: Colors.white,
            onPressed: () => _openChat(_activeSession ?? nextSession),
          ),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Session completed. You are now available for new seekers.')),
      );
    }
  }

  Future<void> _openChat(Map<String, dynamic> session) async {
    final backendService = Provider.of<BackendService>(context, listen: false);
    final pandit = backendService.currentPandit;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => PanditChatScreen(
          sessionData: {
            ...session,
            if (pandit?['rate_per_min'] != null) 'rate_per_min': pandit!['rate_per_min'],
          },
        ),
      ),
    );
    // Not silent: also refreshes earnings after a session ended in the chat.
    if (mounted) _loadDashboardData();
  }

  Future<void> _logout() async {
    final confirmed = await _confirm(
      title: 'Log out?',
      message: 'You will stop receiving consultation requests on this device until you log in again.',
      confirmLabel: 'Log out',
    );
    if (!confirmed || !mounted) return;
    _pollTimer?.cancel();
    final backendService = Provider.of<BackendService>(context, listen: false);
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    await backendService.logoutPandit();
    messenger.showSnackBar(const SnackBar(content: Text('Logged out of Pandit Account.')));
    if (navigator.canPop()) navigator.pop();
  }

  String _waitedLabel(dynamic createdAt) {
    final dt = DateTime.tryParse(createdAt?.toString() ?? '');
    if (dt == null) return 'Waiting in line';
    final mins = DateTime.now().difference(dt.toLocal()).inMinutes;
    if (mins < 1) return 'Joined just now';
    if (mins < 60) return 'Waiting $mins min';
    return 'Waiting ${mins ~/ 60}h ${mins % 60}m';
  }

  Widget _sectionHeader(IconData icon, String text, {Color color = Colors.grey}) {
    return Row(
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            text,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w900, color: Colors.grey, letterSpacing: 1.0),
          ),
        ),
      ],
    );
  }

  Widget _buildLoginRequired(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFCF7F1),
      appBar: AppBar(
        backgroundColor: const Color(0xFFFCF7F1),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.black),
          tooltip: 'Back',
          onPressed: () => Navigator.maybePop(context),
        ),
        title: const Text('Pandit Partner Access', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 18)),
      ),
      body: Center(
        child: SingleChildScrollView(
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
                'This workspace is restricted to verified Astrologer Partners. Please login with your Pandit Account to manage live consultations.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey, fontSize: 13),
              ),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: () {
                  Navigator.pushReplacement(
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

  Widget _buildError() {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off_rounded, size: 56, color: Colors.grey),
            const SizedBox(height: 12),
            Text(_loadError ?? 'Something went wrong.', textAlign: TextAlign.center, style: const TextStyle(color: Colors.black54)),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: () {
                setState(() {
                  _isLoading = true;
                  _loadError = null;
                });
                _loadDashboardData();
              },
              icon: const Icon(Icons.refresh_rounded, color: Colors.white),
              label: const Text('Retry', style: TextStyle(color: Colors.white)),
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFE83D66)),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final backendService = Provider.of<BackendService>(context);
    if (!backendService.isPanditLoggedIn) {
      return _buildLoginRequired(context);
    }

    final Map<String, dynamic> pandit = backendService.currentPandit ?? const {};
    final String name = (pandit['full_name'] ?? 'Pandit Ji').toString();
    final String specialty = (pandit['specialty'] ?? 'Vedic Astrology').toString();
    final double rate = _toDouble(pandit['rate_per_min']);
    final double earnings = _toDouble(pandit['earnings_balance']);
    final int minutes = _toInt(pandit['total_minutes_consulted']);
    final String avatarUrl = (pandit['avatar_url'] ?? '').toString();

    return Scaffold(
      backgroundColor: const Color(0xFFFCF7F1),
      appBar: AppBar(
        backgroundColor: const Color(0xFFFCF7F1),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.black),
          tooltip: 'Back',
          onPressed: () => Navigator.maybePop(context),
        ),
        title: const Text(
          'Pandit Dashboard',
          overflow: TextOverflow.ellipsis,
          style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 20),
        ),
        actions: [
          Tooltip(
            message: _isOnline ? 'Online – tap to go offline' : 'Offline – tap to go online',
            child: Switch(
              value: _isOnline,
              activeThumbColor: const Color(0xFF059669),
              onChanged: _isTogglingStatus ? null : _toggleOnlineStatus,
            ),
          ),
          IconButton(
            icon: const Icon(Icons.logout_rounded, color: Colors.red),
            tooltip: 'Logout Pandit Account',
            onPressed: _logout,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFFE83D66)))
          : _loadError != null
              ? _buildError()
              : RefreshIndicator(
                  color: const Color(0xFFE83D66),
                  onRefresh: () => _loadDashboardData(),
                  child: ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(16),
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
                                CircleAvatar(
                                  radius: 28,
                                  backgroundColor: const Color(0xFFFFD700),
                                  foregroundImage: avatarUrl.startsWith('http') ? NetworkImage(avatarUrl) : null,
                                  onForegroundImageError: avatarUrl.startsWith('http') ? (_, __) {} : null,
                                  child: Text(
                                    name.isNotEmpty ? name[0].toUpperCase() : 'P',
                                    style: const TextStyle(color: Colors.black, fontSize: 22, fontWeight: FontWeight.bold),
                                  ),
                                ),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        name,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        specialty,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(color: Color(0xFFFFD700), fontSize: 12, fontWeight: FontWeight.bold),
                                      ),
                                      const SizedBox(height: 4),
                                      Row(
                                        children: [
                                          Container(
                                            width: 8,
                                            height: 8,
                                            decoration: BoxDecoration(
                                              color: _isOnline ? const Color(0xFF34D399) : Colors.grey,
                                              shape: BoxShape.circle,
                                            ),
                                          ),
                                          const SizedBox(width: 6),
                                          Flexible(
                                            child: Text(
                                              '${_isOnline ? 'Online' : 'Offline'} · ₹${rate.toStringAsFixed(rate % 1 == 0 ? 0 : 2)}/min',
                                              overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(color: Colors.white70, fontSize: 11),
                                            ),
                                          ),
                                        ],
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
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      const Text('EARNINGS',
                                          style: TextStyle(color: Color(0xFFFFD700), fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 0.8)),
                                      const SizedBox(height: 2),
                                      FittedBox(
                                        fit: BoxFit.scaleDown,
                                        alignment: Alignment.centerLeft,
                                        child: Text(
                                          '₹${earnings.toStringAsFixed(2)}',
                                          style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w900),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    children: [
                                      const Text('TOTAL CONSULTED',
                                          style: TextStyle(color: Colors.white60, fontSize: 10, fontWeight: FontWeight.bold)),
                                      const SizedBox(height: 2),
                                      Text(
                                        '$minutes Mins',
                                        style: const TextStyle(color: Color(0xFF34D399), fontSize: 16, fontWeight: FontWeight.bold),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 24),

                      _sectionHeader(Icons.circle, 'ACTIVE CONSULTATION', color: const Color(0xFFE53935)),
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
                                  Expanded(
                                    child: Text(
                                      'In Live Chat: ${_activeSession!['user_name'] ?? 'Seeker'}',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.black),
                                    ),
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
                                  onPressed: _isActionBusy ? null : () => _openChat(_activeSession!),
                                  icon: const Icon(Icons.chat_rounded, color: Colors.white),
                                  label: const FittedBox(
                                    fit: BoxFit.scaleDown,
                                    child: Text('Open Chat & Inspect Kundli', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                                  ),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFF059669),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 8),
                              SizedBox(
                                width: double.infinity,
                                child: OutlinedButton.icon(
                                  onPressed: _isActionBusy ? null : () => _advanceQueue(endingOnly: true),
                                  icon: _isActionBusy
                                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                                      : const Icon(Icons.call_end_rounded, color: Colors.red, size: 18),
                                  label: const Text('End Session', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
                                  style: OutlinedButton.styleFrom(
                                    side: BorderSide(color: Colors.red.withValues(alpha: 0.4)),
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
                            children: [
                              const Icon(Icons.mark_chat_read_rounded, color: Colors.grey, size: 36),
                              const SizedBox(height: 8),
                              const Text('No Active Session', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                              const SizedBox(height: 2),
                              Text(
                                _isOnline
                                    ? 'You are available for new consultation requests.'
                                    : 'You are offline. Go online to receive consultation requests.',
                                textAlign: TextAlign.center,
                                style: const TextStyle(fontSize: 11, color: Colors.grey),
                              ),
                            ],
                          ),
                        ),

                      const SizedBox(height: 24),

                      Row(
                        children: [
                          Expanded(
                            child: _sectionHeader(Icons.hourglass_top_rounded, 'WAITING QUEUE (${_waitingQueue.length})'),
                          ),
                          TextButton.icon(
                            onPressed: _waitingQueue.isNotEmpty && !_isActionBusy ? () => _advanceQueue(endingOnly: false) : null,
                            icon: const Icon(Icons.skip_next_rounded, size: 18),
                            label: const Text('Call Next', style: TextStyle(fontWeight: FontWeight.bold)),
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
                          child: const Text(
                            'No seekers waiting right now. This list refreshes automatically.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Colors.grey, fontSize: 13),
                          ),
                        )
                      else
                        ..._waitingQueue.asMap().entries.map((entry) {
                          final index = entry.key;
                          final seeker = entry.value;
                          final int pos = _toInt(seeker['queue_position'], index + 1);
                          final bool isFirst = index == 0;

                          return Container(
                            margin: const EdgeInsets.only(bottom: 10),
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: isFirst ? const Color(0xFFE83D66).withValues(alpha: 0.4) : Colors.grey.shade200),
                            ),
                            child: Row(
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
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        (seeker['user_name'] ?? 'Seeker').toString(),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                                      ),
                                      Text(
                                        _waitedLabel(seeker['created_at']),
                                        style: const TextStyle(fontSize: 11, color: Colors.grey),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 8),
                                if (isFirst)
                                  ElevatedButton(
                                    onPressed: _isActionBusy ? null : () => _advanceQueue(endingOnly: false),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.black,
                                      padding: const EdgeInsets.symmetric(horizontal: 14),
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                    ),
                                    child: const Text('Connect', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                                  )
                                else
                                  const Text('In line', style: TextStyle(fontSize: 11, color: Colors.grey, fontWeight: FontWeight.bold)),
                              ],
                            ),
                          );
                        }),

                      const SizedBox(height: 24),
                      _sectionHeader(Icons.payments_rounded, 'RECENT PAYOUTS', color: const Color(0xFF059669)),
                      const SizedBox(height: 8),
                      _buildPayouts(),
                    ],
                  ),
                ),
    );
  }
}
