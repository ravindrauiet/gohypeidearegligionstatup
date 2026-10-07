import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/backend_service.dart';
import '../utils/session_messages.dart';
import '../widgets/session_prescription_card.dart';

double _toDouble(dynamic v, [double fallback = 0]) {
  if (v is num) return v.toDouble();
  if (v is String) return double.tryParse(v) ?? fallback;
  return fallback;
}

/// Decodes values that Postgres JSON columns may return either as already
/// decoded objects or as raw JSON strings.
dynamic _decodeMaybeJson(dynamic v) {
  if (v is String && v.trim().isNotEmpty && (v.trim().startsWith('{') || v.trim().startsWith('['))) {
    try {
      return jsonDecode(v);
    } catch (_) {
      return v;
    }
  }
  return v;
}

String _str(dynamic v, [String fallback = '—']) {
  if (v == null) return fallback;
  final s = v.toString().trim();
  return s.isEmpty ? fallback : s;
}

class PanditChatScreen extends StatefulWidget {
  /// A `consultation_queue` row (id, pandit_id, user_id, user_name, started_at)
  /// optionally enriched with `rate_per_min` by the dashboard.
  final Map<String, dynamic> sessionData;
  const PanditChatScreen({super.key, required this.sessionData});

  @override
  State<PanditChatScreen> createState() => _PanditChatScreenState();
}

class _PanditChatScreenState extends State<PanditChatScreen> {
  static const Duration _pollInterval = Duration(seconds: 3);
  static const int _maxSilentFailures = 3;

  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final List<SessionMessage> _messages = [];

  Map<String, dynamic>? _seekerKundli;
  bool _isLoadingKundli = true;
  String? _kundliError;
  /// Bumped whenever Kundli loading state changes so an open bottom sheet rebuilds.
  final ValueNotifier<int> _kundliTick = ValueNotifier<int>(0);

  /// Null when the session data is incomplete (the screen then shows an error state).
  int? _sessionId;
  int? _seekerId;

  Timer? _clockTimer;
  Timer? _pollTimer;
  bool _isPolling = false;
  bool _initialLoadDone = false;
  int _pollFailures = 0;
  late final DateTime _sessionStart;
  Duration _elapsed = Duration.zero;

  bool _sessionEnded = false;
  bool _isEnding = false;
  bool _isSending = false;
  bool _isSavingPrescription = false;

  static const List<String> _quickReplies = [
    'Namaste! I am reviewing your Kundli now.',
    'Please share your exact time and place of birth.',
    'What specific question would you like guidance on?',
    'Let me check your current Dasha period.',
  ];

  String get _seekerName => _str(widget.sessionData['user_name'], 'Seeker');
  double get _ratePerMin => _toDouble(widget.sessionData['rate_per_min']);
  bool get _hasValidSession => _sessionId != null && _seekerId != null;

  @override
  void initState() {
    super.initState();
    _sessionId = parseId(widget.sessionData['id']);
    _seekerId = parseId(widget.sessionData['user_id']);

    final started = DateTime.tryParse(widget.sessionData['started_at']?.toString() ?? '');
    final now = DateTime.now();
    _sessionStart = (started != null && started.toLocal().isBefore(now)) ? started.toLocal() : now;
    _elapsed = now.difference(_sessionStart);

    if (!_hasValidSession) return;

    _messages.add(SessionMessage.system(
      'Live session with $_seekerName started at ${formatSessionClock(_sessionStart)}.',
    ));

    _clockTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted || _sessionEnded) return;
      setState(() => _elapsed = DateTime.now().difference(_sessionStart));
    });
    _pollTimer = Timer.periodic(_pollInterval, (_) => _pollMessages());

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _pollMessages();
      _loadSeekerKundli();
    });
  }

  @override
  void dispose() {
    _stopTimers();
    _messageController.dispose();
    _scrollController.dispose();
    _kundliTick.dispose();
    super.dispose();
  }

  void _stopTimers() {
    _clockTimer?.cancel();
    _pollTimer?.cancel();
    _clockTimer = null;
    _pollTimer = null;
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    });
  }

  /// Fetches messages newer than the last one we have. Never overlaps itself;
  /// also detects that the session was ended by the seeker (or elsewhere).
  Future<void> _pollMessages() async {
    final sessionId = _sessionId;
    if (sessionId == null || _isPolling || _sessionEnded || !mounted) return;
    _isPolling = true;
    Map<String, dynamic>? data;
    try {
      data = await Provider.of<BackendService>(context, listen: false)
          .fetchSessionMessages(sessionId, afterId: lastSessionMessageId(_messages), asPandit: true);
    } catch (_) {
      data = null;
    } finally {
      _isPolling = false;
    }
    if (!mounted || _sessionEnded) return;

    if (data == null) {
      setState(() {
        _pollFailures++;
        _initialLoadDone = true;
      });
      return;
    }

    final raw = data['messages'];
    final incoming = raw is List ? raw.map(SessionMessage.fromJson).whereType<SessionMessage>() : const <SessionMessage>[];
    final added = mergeSessionMessages(_messages, incoming);
    setState(() {
      _pollFailures = 0;
      _initialLoadDone = true;
    });
    if (added) _scrollToBottom();

    final status = data['sessionStatus']?.toString();
    if (status != null && status != 'active') {
      _markSessionEnded('This consultation has ended.');
    }
  }

  void _markSessionEnded(String reason) {
    if (_sessionEnded || !mounted) return;
    _stopTimers();
    setState(() {
      _sessionEnded = true;
      _messages.add(SessionMessage.system(reason));
    });
    _scrollToBottom();
  }

  Future<void> _loadSeekerKundli() async {
    final userId = _seekerId;
    if (userId == null) {
      setState(() {
        _isLoadingKundli = false;
        _kundliError = 'This seeker has not shared a Kundli.';
      });
      return;
    }

    setState(() {
      _isLoadingKundli = true;
      _kundliError = null;
    });
    _kundliTick.value++;

    final backendService = Provider.of<BackendService>(context, listen: false);
    Map<String, dynamic>? kundli;
    try {
      kundli = await backendService.fetchUserKundliForPandit(userId);
    } catch (_) {
      kundli = null;
    }

    if (!mounted) return;
    setState(() {
      _seekerKundli = kundli;
      _isLoadingKundli = false;
      _kundliError = kundli == null ? (backendService.lastError ?? 'Could not load the seeker\'s Kundli.') : null;
    });
    _kundliTick.value++;
  }

  Future<void> _sendMessage({String? customText}) async {
    final sessionId = _sessionId;
    if (_sessionEnded || _isSending || sessionId == null) return;
    final text = (customText ?? _messageController.text).trim();
    if (text.isEmpty) return;

    if (customText == null) _messageController.clear();
    setState(() => _isSending = true);

    final backendService = Provider.of<BackendService>(context, listen: false);
    Map<String, dynamic>? saved;
    try {
      saved = await backendService.sendSessionMessage(sessionId, text, asPandit: true);
    } catch (_) {
      saved = null;
    }
    if (!mounted) return;
    setState(() => _isSending = false);

    final msg = SessionMessage.fromJson(saved);
    if (msg == null) {
      // Give the text back so the Pandit does not have to retype it.
      if (customText == null && _messageController.text.isEmpty) _messageController.text = text;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(backendService.lastError ?? 'Message not sent. Please try again.'),
          backgroundColor: Colors.red,
        ),
      );
      // A 409 means the seeker already ended the session; the poll will notice.
      _pollMessages();
      return;
    }
    setState(() => mergeSessionMessages(_messages, [msg]));
    _scrollToBottom();
  }

  Future<void> _showPrescriptionDialog() async {
    final sessionId = _sessionId;
    if (_sessionEnded || _isSavingPrescription || sessionId == null) return;
    final gemstoneCtrl = TextEditingController();
    final mantraCtrl = TextEditingController();
    final remedyCtrl = TextEditingController();
    String? error;

    final sent = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          InputDecoration deco(String hint) => InputDecoration(
                hintText: hint,
                hintStyle: const TextStyle(fontSize: 12),
                filled: true,
                fillColor: Colors.white,
                isDense: true,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
              );
          return AlertDialog(
            backgroundColor: const Color(0xFFFCF7F1),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
            title: const Row(
              children: [
                Icon(Icons.auto_awesome_rounded, color: Color(0xFFD97706)),
                SizedBox(width: 8),
                Expanded(child: Text('Send Vedic Remedy Card', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16))),
              ],
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Gemstone', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                  const SizedBox(height: 4),
                  TextField(controller: gemstoneCtrl, decoration: deco('e.g. Yellow Sapphire 5.25 Ratti in Gold')),
                  const SizedBox(height: 12),
                  const Text('Vedic Mantra', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                  const SizedBox(height: 4),
                  TextField(controller: mantraCtrl, decoration: deco('e.g. Om Gram Greem Groum Sah Gurave Namah (108x)')),
                  const SizedBox(height: 12),
                  const Text('Puja / Remedy Ritual', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                  const SizedBox(height: 4),
                  TextField(controller: remedyCtrl, maxLines: 2, decoration: deco('e.g. Offer yellow flowers on Thursdays')),
                  if (error != null) ...[
                    const SizedBox(height: 8),
                    Text(error!, style: const TextStyle(color: Colors.red, fontSize: 12)),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
              ),
              ElevatedButton.icon(
                onPressed: () {
                  if (gemstoneCtrl.text.trim().isEmpty && mantraCtrl.text.trim().isEmpty && remedyCtrl.text.trim().isEmpty) {
                    setDialogState(() => error = 'Fill in at least one remedy.');
                    return;
                  }
                  Navigator.pop(ctx, true);
                },
                icon: const Icon(Icons.send_rounded, size: 16, color: Colors.white),
                label: const Text('Send', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFD95D39)),
              ),
            ],
          );
        },
      ),
    );

    final gemstone = gemstoneCtrl.text.trim();
    final mantra = mantraCtrl.text.trim();
    final remedy = remedyCtrl.text.trim();
    // Dispose after the dialog's exit animation has finished.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      gemstoneCtrl.dispose();
      mantraCtrl.dispose();
      remedyCtrl.dispose();
    });

    if (sent != true || !mounted) return;
    setState(() => _isSavingPrescription = true);
    final backendService = Provider.of<BackendService>(context, listen: false);
    Map<String, dynamic>? saved;
    try {
      saved = await backendService.submitPrescription(
        sessionId: sessionId,
        gemstone: gemstone.isEmpty ? null : gemstone,
        mantra: mantra.isEmpty ? null : mantra,
        remedy: remedy.isEmpty ? null : remedy,
      );
    } catch (_) {
      saved = null;
    }
    if (!mounted) return;
    setState(() => _isSavingPrescription = false);

    if (saved == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(backendService.lastError ?? 'Could not save the prescription. Please try again.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Remedy card sent to the seeker.'), backgroundColor: Color(0xFF059669)),
    );
    // The backend posts the prescription into the session chat; fetch it now.
    _pollMessages();
  }

  Widget _kundliSheetBody(ScrollController controller) {
    if (_isLoadingKundli) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: Color(0xFFE83D66)),
            SizedBox(height: 12),
            Text('Loading seeker Kundli...', style: TextStyle(color: Colors.grey)),
          ],
        ),
      );
    }
    if (_seekerKundli == null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off_rounded, color: Colors.grey, size: 40),
            const SizedBox(height: 8),
            Text(_kundliError ?? 'Kundli unavailable.', textAlign: TextAlign.center, style: const TextStyle(color: Colors.grey)),
            const SizedBox(height: 12),
            ElevatedButton.icon(
              onPressed: _loadSeekerKundli,
              icon: const Icon(Icons.refresh_rounded, color: Colors.white),
              label: const Text('Retry', style: TextStyle(color: Colors.white)),
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFE83D66)),
            ),
          ],
        ),
      );
    }

    final k = _seekerKundli!;
    final birthRaw = _decodeMaybeJson(k['birthDetails']);
    final dashaRaw = _decodeMaybeJson(k['dashaInfo']);
    final planetsRaw = _decodeMaybeJson(k['planetaryPositions']);
    final Map birth = birthRaw is Map ? birthRaw : const {};
    final Map dasha = dashaRaw is Map ? dashaRaw : const {};
    final List planets = planetsRaw is List
        ? planetsRaw
        : planetsRaw is Map
            ? planetsRaw.entries.map((e) => e.value is Map ? {'planet': e.key, ...e.value as Map} : {'planet': e.key}).toList()
            : const [];

    String dob = _str(birth['dateOfBirth']);
    if (dob.length > 10 && dob.contains('T')) dob = dob.substring(0, 10);

    return ListView(
      controller: controller,
      children: [
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
                'Lagna: ${_str(k['ascendant'])} | Moon: ${_str(k['moonSign'])}',
                style: const TextStyle(color: Color(0xFFFFD700), fontSize: 16, fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 4),
              Text(
                'Sun Sign: ${_str(k['sunSign'])} · Nakshatra: ${_str(k['nakshatra'])}'
                '${k['nakshatraPada'] != null ? ' (Pada ${k['nakshatraPada']})' : ''}',
                style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 6),
              Text(
                'DOB: $dob at ${_str(birth['timeOfBirth'])} (${_str(birth['placeOfBirth'])})',
                style: const TextStyle(color: Colors.white70, fontSize: 11),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
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
                'Mahadasha: ${_str(dasha['currentMahadasha'])} · Antardasha: ${_str(dasha['antardasha'])}',
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.black),
              ),
              const SizedBox(height: 2),
              Text('Period valid until: ${_str(dasha['dashaEndDate'])}', style: const TextStyle(fontSize: 11, color: Colors.grey)),
            ],
          ),
        ),
        const SizedBox(height: 16),
        const Text('Planetary Positions', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
        const SizedBox(height: 8),
        if (planets.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Text('Planetary positions are not available for this seeker.', style: TextStyle(color: Colors.grey, fontSize: 12)),
          )
        else
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.grey.shade200),
            ),
            child: Column(
              children: [
                for (int i = 0; i < planets.length; i++) ...[
                  if (i > 0) const Divider(height: 1),
                  Builder(builder: (_) {
                    final p = planets[i] is Map ? planets[i] as Map : const {};
                    final degree = p['degree'];
                    final degreeText = degree is num
                        ? '${degree.toStringAsFixed(1)}°'
                        : (double.tryParse('${degree ?? ''}') != null ? '${double.parse('$degree').toStringAsFixed(1)}°' : '');
                    return Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      child: Row(
                        children: [
                          Expanded(
                            flex: 3,
                            child: Text(
                              _str(p['planet'] ?? p['name'], 'Planet'),
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                            ),
                          ),
                          Expanded(
                            flex: 4,
                            child: Text(
                              '${_str(p['sign'])}${degreeText.isNotEmpty ? ' ($degreeText)' : ''}',
                              style: const TextStyle(fontSize: 13, color: Colors.black87),
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.grey.shade100,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              'House ${_str(p['house'], '-')}',
                              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.grey),
                            ),
                          ),
                        ],
                      ),
                    );
                  }),
                ],
              ],
            ),
          ),
        const SizedBox(height: 12),
      ],
    );
  }

  void _showSeekerKundliDrawer() {
    final name = _str(_seekerKundli?['seekerName'], _seekerName);
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return DraggableScrollableSheet(
          initialChildSize: 0.85,
          minChildSize: 0.4,
          maxChildSize: 0.95,
          expand: false,
          builder: (ctx, controller) => Container(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
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
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Icon(Icons.stars_rounded, color: Color(0xFFD97706), size: 24),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        "$name's Kundli Chart",
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.black),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      tooltip: 'Close',
                      onPressed: () => Navigator.pop(ctx),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: ValueListenableBuilder<int>(
                    valueListenable: _kundliTick,
                    builder: (_, __, ___) => _kundliSheetBody(controller),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _endConsultation() async {
    if (_isEnding) return;
    final sessionId = _sessionId;
    if (_sessionEnded || sessionId == null) {
      Navigator.pop(context, true);
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('End consultation?'),
        content: Text(
          'Your session with $_seekerName (${formatSessionDuration(_elapsed)}) will be marked as completed '
          'and billed. You can connect the next waiting seeker from your dashboard.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Keep Chatting')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('End Session', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _isEnding = true);
    final backendService = Provider.of<BackendService>(context, listen: false);
    Map<String, dynamic>? res;
    try {
      res = await backendService.endConsultationSession(sessionId, asPandit: true);
    } catch (_) {
      res = null;
    }
    if (!mounted) return;
    setState(() => _isEnding = false);

    if (res == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(backendService.lastError ?? 'Could not end the session. Please check your connection.'),
          backgroundColor: Colors.red,
          action: SnackBarAction(label: 'Retry', textColor: Colors.white, onPressed: _endConsultation),
        ),
      );
      // The seeker may already have ended it; the poll will confirm.
      _pollMessages();
      return;
    }

    _stopTimers();
    unawaited(backendService.refreshPanditProfile());
    final billing = res['billing'];
    final minutes = billing is Map ? billing['minutesCharged'] : null;
    final amount = billing is Map ? _toDouble(billing['amount']) : 0.0;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Consultation with $_seekerName completed'
          '${minutes is num ? ' · $minutes min · ₹${amount.toStringAsFixed(2)} earned' : '.'}',
        ),
        backgroundColor: const Color(0xFF059669),
      ),
    );
    Navigator.pop(context, true);
  }

  Widget _buildKundliBanner() {
    Widget leading;
    if (_isLoadingKundli) {
      leading = const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFFD97706))),
          SizedBox(width: 8),
          Flexible(
            child: Text('Loading Kundli...',
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFFB45309))),
          ),
        ],
      );
    } else if (_seekerKundli == null) {
      leading = InkWell(
        onTap: _loadSeekerKundli,
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.refresh_rounded, color: Colors.red, size: 18),
            SizedBox(width: 6),
            Flexible(
              child: Text('Kundli failed · Retry',
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.red)),
            ),
          ],
        ),
      );
    } else {
      leading = InkWell(
        onTap: _showSeekerKundliDrawer,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.stars_rounded, color: Color(0xFFD97706), size: 18),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                'Kundli · ${_str(_seekerKundli!['ascendant'], '?')} Lagna',
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFFB45309)),
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      color: const Color(0xFFFFD700).withValues(alpha: 0.15),
      child: Row(
        children: [
          Expanded(child: Align(alignment: Alignment.centerLeft, child: leading)),
          const SizedBox(width: 8),
          Material(
            color: (_sessionEnded || _isSavingPrescription) ? Colors.grey : const Color(0xFFD95D39),
            borderRadius: BorderRadius.circular(10),
            child: InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: (_sessionEnded || _isSavingPrescription) ? null : _showPrescriptionDialog,
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.auto_awesome_rounded, color: Colors.white, size: 12),
                    SizedBox(width: 4),
                    Text('Prescribe Remedy', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white)),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMessage(SessionMessage msg) {
    final time = formatSessionClock(msg.time);

    if (msg.isSystem) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(color: Colors.grey.shade200, borderRadius: BorderRadius.circular(12)),
            child: Text(
              msg.content,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 11, color: Colors.black54),
            ),
          ),
        ),
      );
    }

    if (msg.isPrescription) return SessionPrescriptionCard(message: msg);

    final isPandit = msg.senderRole == 'pandit';
    return Align(
      alignment: isPandit ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.78),
        decoration: BoxDecoration(
          color: isPandit ? Colors.black : Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: isPandit ? null : Border.all(color: Colors.grey.shade200),
        ),
        child: Column(
          crossAxisAlignment: isPandit ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            Text(
              msg.content,
              style: TextStyle(color: isPandit ? Colors.white : Colors.black, fontSize: 14, height: 1.4),
            ),
            const SizedBox(height: 4),
            Text(time, style: TextStyle(color: isPandit ? Colors.white60 : Colors.grey, fontSize: 10)),
          ],
        ),
      ),
    );
  }

  Widget _buildInvalidSession() {
    return Scaffold(
      backgroundColor: const Color(0xFFFCF7F1),
      appBar: AppBar(
        backgroundColor: const Color(0xFFFCF7F1),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.black),
          tooltip: 'Back to dashboard',
          onPressed: () => Navigator.maybePop(context),
        ),
        title: const Text('Consultation', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 18)),
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline_rounded, size: 56, color: Colors.grey),
              const SizedBox(height: 12),
              const Text(
                'This consultation could not be opened because its session details are incomplete. '
                'Please go back and refresh your dashboard.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.black54),
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () => Navigator.maybePop(context),
                child: const Text('Back to Dashboard'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_hasValidSession) return _buildInvalidSession();
    final double earned = _ratePerMin * (_elapsed.inSeconds / 60.0);

    return Scaffold(
      backgroundColor: const Color(0xFFFCF7F1),
      appBar: AppBar(
        backgroundColor: const Color(0xFFFCF7F1),
        elevation: 0,
        titleSpacing: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.black),
          tooltip: 'Back to dashboard',
          onPressed: () => Navigator.maybePop(context),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _seekerName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 16),
            ),
            Row(
              children: [
                Icon(Icons.timer_rounded, color: _sessionEnded ? Colors.grey : const Color(0xFF059669), size: 12),
                const SizedBox(width: 4),
                Flexible(
                  child: Text(
                    _sessionEnded
                        ? 'Session ended · ${formatSessionDuration(_elapsed)}'
                        : '${formatSessionDuration(_elapsed)}${_ratePerMin > 0 ? ' · ₹${earned.toStringAsFixed(1)} earned' : ''}',
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: _sessionEnded ? Colors.grey : const Color(0xFF059669),
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.menu_book_rounded, color: Color(0xFFE83D66)),
            tooltip: 'Inspect Seeker Kundli',
            onPressed: _showSeekerKundliDrawer,
          ),
          TextButton(
            onPressed: _isEnding ? null : _endConsultation,
            child: _isEnding
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.red))
                : Text(
                    _sessionEnded ? 'Close' : 'End',
                    style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
                  ),
          ),
        ],
      ),
      body: Column(
        children: [
          _buildKundliBanner(),
          if (_pollFailures >= _maxSilentFailures && !_sessionEnded)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              color: Colors.orange.withValues(alpha: 0.12),
              child: const Text(
                'Connection issue – reconnecting to the chat...',
                style: TextStyle(fontSize: 12, color: Colors.black87),
              ),
            ),
          Expanded(
            child: !_initialLoadDone
                ? const Center(child: CircularProgressIndicator(color: Color(0xFFE83D66)))
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.all(16),
                    itemCount: _messages.length,
                    itemBuilder: (context, index) => _buildMessage(_messages[index]),
                  ),
          ),
          if (!_sessionEnded)
            Container(
              height: 44,
              color: Colors.white,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                itemCount: _quickReplies.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (context, index) {
                  return ActionChip(
                    backgroundColor: const Color(0xFFFCF7F1),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    label: Text(
                      _quickReplies[index],
                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.black87),
                    ),
                    onPressed: _isSending ? null : () => _sendMessage(customText: _quickReplies[index]),
                  );
                },
              ),
            ),
          SafeArea(
            top: false,
            child: Container(
              padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
              color: Colors.white,
              child: _sessionEnded
                  ? const Padding(
                      padding: EdgeInsets.symmetric(vertical: 8),
                      child: Center(
                        child: Text('This consultation has ended.', style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold)),
                      ),
                    )
                  : Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _messageController,
                            minLines: 1,
                            maxLines: 4,
                            textCapitalization: TextCapitalization.sentences,
                            textInputAction: TextInputAction.send,
                            onSubmitted: (_) => _sendMessage(),
                            decoration: InputDecoration(
                              hintText: 'Type astrological guidance...',
                              isDense: true,
                              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                              filled: true,
                              fillColor: const Color(0xFFFCF7F1),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none),
                            ),
                          ),
                        ),
                        const SizedBox(width: 4),
                        IconButton(
                          icon: _isSending
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFFE83D66)),
                                )
                              : const Icon(Icons.send_rounded, color: Color(0xFFE83D66)),
                          tooltip: 'Send',
                          onPressed: _isSending ? null : () => _sendMessage(),
                        ),
                      ],
                    ),
            ),
          ),
        ],
      ),
    );
  }
}
