import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/backend_service.dart';
import '../utils/session_messages.dart';
import '../widgets/session_prescription_card.dart';
import '../widgets/ui/app_ui.dart';

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
    final incoming =
        raw is List ? raw.map(SessionMessage.fromJson).whereType<SessionMessage>() : const <SessionMessage>[];
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
      showAppSnack(context, backendService.lastError ?? 'Message not sent. Please try again.', error: true);
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
          Widget field(String label, String hint, TextEditingController c, IconData icon, {int maxLines = 1}) =>
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                child: TextField(
                  controller: c,
                  maxLines: maxLines,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: InputDecoration(
                    labelText: label,
                    hintText: hint,
                    hintStyle: const TextStyle(fontSize: 12, color: AppColors.textTertiary),
                    floatingLabelBehavior: FloatingLabelBehavior.always,
                    prefixIcon: Icon(icon, size: 20),
                    isDense: true,
                  ),
                ),
              );
          return AlertDialog(
            titlePadding: const EdgeInsets.fromLTRB(AppSpacing.xl, AppSpacing.xl, AppSpacing.xl, AppSpacing.xs),
            contentPadding: const EdgeInsets.fromLTRB(AppSpacing.xl, AppSpacing.sm, AppSpacing.xl, 0),
            title: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Send remedy card'),
                SizedBox(height: 4),
                Text('Fill in any of the fields below. The seeker receives it in the chat.', style: AppText.caption),
              ],
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: AppSpacing.xs),
                  field('Gemstone', 'e.g. Yellow Sapphire 5.25 Ratti in Gold', gemstoneCtrl, Icons.diamond_outlined),
                  field('Vedic mantra', 'e.g. Om Gram Greem Groum Sah Gurave Namah (108x)', mantraCtrl,
                      Icons.self_improvement_rounded),
                  field(
                      'Puja / remedy ritual', 'e.g. Offer yellow flowers on Thursdays', remedyCtrl, Icons.spa_outlined,
                      maxLines: 2),
                  if (error != null) Text(error!, style: AppText.caption.copyWith(color: AppColors.danger)),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                style: TextButton.styleFrom(foregroundColor: AppColors.textSecondary),
                child: const Text('Cancel'),
              ),
              FilledButton.icon(
                onPressed: () {
                  if (gemstoneCtrl.text.trim().isEmpty &&
                      mantraCtrl.text.trim().isEmpty &&
                      remedyCtrl.text.trim().isEmpty) {
                    setDialogState(() => error = 'Fill in at least one remedy.');
                    return;
                  }
                  Navigator.pop(ctx, true);
                },
                style: FilledButton.styleFrom(minimumSize: const Size(64, 44)),
                icon: const Icon(Icons.send_rounded, size: 18),
                label: const Text('Send'),
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
      showAppSnack(context, backendService.lastError ?? 'Could not save the prescription. Please try again.',
          error: true);
      return;
    }
    showAppSnack(context, 'Remedy card sent to the seeker.');
    // The backend posts the prescription into the session chat; fetch it now.
    _pollMessages();
  }

  Widget _kundliSheetBody(ScrollController controller) {
    if (_isLoadingKundli) {
      return ListView(
        controller: controller,
        padding: const EdgeInsets.fromLTRB(AppSpacing.page, 0, AppSpacing.page, AppSpacing.xl),
        children: const [
          SkeletonBox(height: 104, radius: AppRadius.lg),
          SizedBox(height: AppSpacing.md),
          SkeletonBox(height: 72, radius: AppRadius.lg),
          SizedBox(height: AppSpacing.md),
          SkeletonBox(height: 220, radius: AppRadius.lg),
        ],
      );
    }
    if (_seekerKundli == null) {
      return ListView(
        controller: controller,
        children: [
          AppStateView.error(
            title: 'Kundli unavailable',
            message: _kundliError ?? 'Kundli unavailable.',
            onAction: _loadSeekerKundli,
          ),
        ],
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
            ? planetsRaw.entries
                .map((e) => e.value is Map ? {'planet': e.key, ...e.value as Map} : {'planet': e.key})
                .toList()
            : const [];

    String dob = _str(birth['dateOfBirth']);
    if (dob.length > 10 && dob.contains('T')) dob = dob.substring(0, 10);

    Widget fact(String label, String value) => Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: const TextStyle(color: AppColors.textOnDarkMuted, fontSize: 11)),
              const SizedBox(height: 2),
              Text(value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: AppColors.textOnDark, fontSize: 15, fontWeight: FontWeight.w700)),
            ],
          ),
        );

    return ListView(
      controller: controller,
      padding: const EdgeInsets.fromLTRB(AppSpacing.page, 0, AppSpacing.page, AppSpacing.xl),
      children: [
        AppCard(
          gradient: AppColors.cosmicGradient,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                fact('Lagna', _str(k['ascendant'])),
                fact('Moon sign', _str(k['moonSign'])),
                fact('Sun sign', _str(k['sunSign'])),
              ]),
              const SizedBox(height: AppSpacing.sm),
              Text(
                'Nakshatra: ${_str(k['nakshatra'])}'
                '${k['nakshatraPada'] != null ? ' (Pada ${k['nakshatraPada']})' : ''}',
                style: const TextStyle(color: AppColors.gold, fontSize: 13, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 4),
              Text(
                'Born $dob at ${_str(birth['timeOfBirth'])} · ${_str(birth['placeOfBirth'])}',
                style: const TextStyle(color: AppColors.textOnDarkMuted, fontSize: 12),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        AppCard(
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(color: AppColors.infoSoft, borderRadius: BorderRadius.circular(10)),
                child: const Icon(Icons.timelapse_rounded, size: 20, color: AppColors.info),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Active dasha', style: AppText.caption),
                    Text(
                      '${_str(dasha['currentMahadasha'])} Mahadasha · ${_str(dasha['antardasha'])} Antardasha',
                      style: AppText.bodyStrong,
                    ),
                    Text('Until ${_str(dasha['dashaEndDate'])}', style: AppText.caption),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SectionHeader(
          title: 'Planetary positions',
          padding: EdgeInsets.fromLTRB(0, AppSpacing.lg, 0, AppSpacing.xs),
        ),
        if (planets.isEmpty)
          const AppCard(
            child: Text('Planetary positions are not available for this seeker.', style: AppText.body),
          )
        else
          AppCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                for (int i = 0; i < planets.length; i++) ...[
                  if (i > 0) const Divider(height: 1),
                  Builder(builder: (_) {
                    final p = planets[i] is Map ? planets[i] as Map : const {};
                    final degree = p['degree'];
                    final degreeText = degree is num
                        ? '${degree.toStringAsFixed(1)}°'
                        : (double.tryParse('${degree ?? ''}') != null
                            ? '${double.parse('$degree').toStringAsFixed(1)}°'
                            : '');
                    return Padding(
                      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
                      child: Row(
                        children: [
                          Expanded(
                            flex: 3,
                            child: Text(_str(p['planet'] ?? p['name'], 'Planet'), style: AppText.bodyStrong),
                          ),
                          Expanded(
                            flex: 4,
                            child: Text(
                              '${_str(p['sign'])}${degreeText.isNotEmpty ? ' ($degreeText)' : ''}',
                              style: AppText.body,
                            ),
                          ),
                          AppBadge(label: 'House ${_str(p['house'], '-')}', color: AppColors.textSecondary),
                        ],
                      ),
                    );
                  }),
                ],
              ],
            ),
          ),
      ],
    );
  }

  void _showSeekerKundliDrawer() {
    final name = _str(_seekerKundli?['seekerName'], _seekerName);
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (ctx) {
        return DraggableScrollableSheet(
          initialChildSize: 0.85,
          minChildSize: 0.4,
          maxChildSize: 0.95,
          expand: false,
          builder: (ctx, controller) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(AppSpacing.page, 0, AppSpacing.xs, AppSpacing.sm),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text("$name's Kundli", maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.title),
                          const Text('Shared for this consultation', style: AppText.caption),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded),
                      tooltip: 'Close',
                      onPressed: () => Navigator.pop(ctx),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ValueListenableBuilder<int>(
                  valueListenable: _kundliTick,
                  builder: (_, __, ___) => _kundliSheetBody(controller),
                ),
              ),
            ],
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
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            style: TextButton.styleFrom(foregroundColor: AppColors.textSecondary),
            child: const Text('Keep chatting'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger, minimumSize: const Size(64, 44)),
            child: const Text('End session'),
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
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(backendService.lastError ?? 'Could not end the session. Please check your connection.'),
            action: SnackBarAction(label: 'Retry', onPressed: _endConsultation),
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
    showAppSnack(
      context,
      'Consultation with $_seekerName completed'
      '${minutes is num ? ' · $minutes min · ₹${amount.toStringAsFixed(2)} earned' : '.'}',
    );
    Navigator.pop(context, true);
  }

  // ---------------------------------------------------------------------------
  // UI
  // ---------------------------------------------------------------------------

  Widget _buildToolsBar() {
    Widget kundliChip;
    if (_isLoadingKundli) {
      kundliChip = const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)),
          SizedBox(width: AppSpacing.xs),
          Flexible(
            child: Text('Loading Kundli...', maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.caption),
          ),
        ],
      );
    } else if (_seekerKundli == null) {
      kundliChip = _ToolChip(
        icon: Icons.refresh_rounded,
        label: 'Kundli failed · Retry',
        color: AppColors.danger,
        onTap: _loadSeekerKundli,
      );
    } else {
      kundliChip = _ToolChip(
        icon: Icons.auto_awesome_rounded,
        label: 'Kundli · ${_str(_seekerKundli!['ascendant'], '?')} Lagna',
        color: AppColors.cosmicLight,
        onTap: _showSeekerKundliDrawer,
      );
    }

    final canPrescribe = !_sessionEnded && !_isSavingPrescription;
    return Container(
      padding: const EdgeInsets.fromLTRB(AppSpacing.page, AppSpacing.xs, AppSpacing.page, AppSpacing.xs),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          Flexible(child: Align(alignment: Alignment.centerLeft, child: kundliChip)),
          const SizedBox(width: AppSpacing.xs),
          Flexible(
            child: _ToolChip(
              icon: Icons.spa_outlined,
              label: _isSavingPrescription ? 'Sending...' : 'Send remedy',
              color: AppColors.primary,
              filled: true,
              onTap: canPrescribe ? _showPrescriptionDialog : null,
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
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
        child: Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 6),
            decoration: BoxDecoration(
              color: AppColors.surfaceMuted,
              borderRadius: BorderRadius.circular(AppRadius.pill),
            ),
            child: Text(msg.content, textAlign: TextAlign.center, style: AppText.caption),
          ),
        ),
      );
    }

    if (msg.isPrescription) return SessionPrescriptionCard(message: msg);

    final isMe = msg.senderRole == 'pandit';
    const r = Radius.circular(AppRadius.lg);
    const tail = Radius.circular(4);
    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Semantics(
        label: '${isMe ? 'You' : _seekerName}, $time: ${msg.content}',
        excludeSemantics: true,
        child: Container(
          margin: EdgeInsets.only(bottom: AppSpacing.xs, left: isMe ? 48 : 0, right: isMe ? 0 : 48),
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 8),
          constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.8),
          decoration: BoxDecoration(
            color: isMe ? AppColors.primary : AppColors.surface,
            borderRadius: BorderRadius.only(
              topLeft: r,
              topRight: r,
              bottomLeft: isMe ? r : tail,
              bottomRight: isMe ? tail : r,
            ),
            border: isMe ? null : Border.all(color: AppColors.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Align(
                alignment: Alignment.centerLeft,
                widthFactor: 1,
                child: Text(
                  msg.content,
                  style: TextStyle(
                    color: isMe ? Colors.white : AppColors.textPrimary,
                    fontSize: 14.5,
                    height: 1.4,
                  ),
                ),
              ),
              const SizedBox(height: 3),
              Text(
                time,
                style: TextStyle(color: isMe ? AppColors.textOnDarkMuted : AppColors.textTertiary, fontSize: 10.5),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMessagesSkeleton() {
    Widget bubble(bool right, double w) => Align(
          alignment: right ? Alignment.centerRight : Alignment.centerLeft,
          child: Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: SkeletonBox(width: w, height: 44, radius: AppRadius.lg),
          ),
        );
    return ListView(
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.all(AppSpacing.page),
      children: [
        bubble(false, 220),
        bubble(true, 180),
        bubble(false, 160),
        bubble(true, 240),
      ],
    );
  }

  Widget _buildInvalidSession() {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          tooltip: 'Back to dashboard',
          onPressed: () => Navigator.maybePop(context),
        ),
        title: const Text('Consultation'),
      ),
      body: Center(
        child: SingleChildScrollView(
          child: AppStateView(
            icon: Icons.error_outline_rounded,
            color: AppColors.warning,
            title: 'Could not open this consultation',
            message: 'Its session details are incomplete. Please go back and refresh your dashboard.',
            actionLabel: 'Back to dashboard',
            onAction: () => Navigator.maybePop(context),
          ),
        ),
      ),
    );
  }

  Widget _buildComposer() {
    if (_sessionEnded) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('This consultation has ended · ${formatSessionDuration(_elapsed)}',
              textAlign: TextAlign.center, style: AppText.caption.copyWith(color: AppColors.textSecondary)),
          const SizedBox(height: AppSpacing.xs),
          AppButton(
            label: 'Back to dashboard',
            variant: AppButtonVariant.dark,
            height: 48,
            onPressed: () => Navigator.pop(context, true),
          ),
        ],
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
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
              hintText: 'Type your guidance...',
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              filled: true,
              fillColor: AppColors.surfaceMuted,
              border:
                  OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadius.xl), borderSide: BorderSide.none),
              enabledBorder:
                  OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadius.xl), borderSide: BorderSide.none),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppRadius.xl),
                borderSide: const BorderSide(color: AppColors.primary, width: 1.2),
              ),
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.xs),
        Semantics(
          button: true,
          label: 'Send message',
          excludeSemantics: true,
          child: Material(
            color: AppColors.primary,
            shape: const CircleBorder(),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: _isSending ? null : () => _sendMessage(),
              child: SizedBox(
                width: 46,
                height: 46,
                child: Center(
                  child: _isSending
                      ? const SizedBox(
                          width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.send_rounded, color: Colors.white, size: 20),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_hasValidSession) return _buildInvalidSession();
    final double earned = _ratePerMin * (_elapsed.inSeconds / 60.0);
    final statusColor = _sessionEnded ? AppColors.textTertiary : AppColors.success;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        titleSpacing: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          tooltip: 'Back to dashboard',
          onPressed: () => Navigator.maybePop(context),
        ),
        title: Row(
          children: [
            AppAvatar(name: _seekerName, size: 38, online: !_sessionEnded, color: AppColors.cosmicLight),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(_seekerName, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.subtitle),
                  Text(
                    _sessionEnded
                        ? 'Session ended · ${formatSessionDuration(_elapsed)}'
                        : '${formatSessionDuration(_elapsed)}'
                            '${_ratePerMin > 0 ? ' · ₹${earned.toStringAsFixed(1)} earned' : ' · Live'}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: statusColor,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.menu_book_rounded),
            tooltip: 'View seeker Kundli',
            onPressed: _showSeekerKundliDrawer,
          ),
          Padding(
            padding: const EdgeInsets.only(right: AppSpacing.xs),
            child: TextButton(
              onPressed: _isEnding ? null : _endConsultation,
              style: TextButton.styleFrom(
                foregroundColor: _sessionEnded ? AppColors.textPrimary : AppColors.danger,
                backgroundColor: _sessionEnded ? AppColors.surfaceMuted : AppColors.dangerSoft,
                minimumSize: const Size(56, 40),
                padding: const EdgeInsets.symmetric(horizontal: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.pill)),
              ),
              child: _isEnding
                  ? const SizedBox(
                      width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.danger))
                  : Text(_sessionEnded ? 'Close' : 'End'),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          _buildToolsBar(),
          if (_pollFailures >= _maxSilentFailures && !_sessionEnded)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.page, vertical: AppSpacing.xs),
              color: AppColors.warningSoft,
              child: Row(
                children: [
                  const Icon(Icons.wifi_off_rounded, size: 16, color: AppColors.warning),
                  const SizedBox(width: AppSpacing.xs),
                  Expanded(
                    child: Text('Connection issue – reconnecting to the chat...',
                        style: AppText.caption.copyWith(color: AppColors.textPrimary)),
                  ),
                ],
              ),
            ),
          Expanded(
            child: !_initialLoadDone
                ? _buildMessagesSkeleton()
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.fromLTRB(AppSpacing.page, AppSpacing.sm, AppSpacing.page, AppSpacing.sm),
                    itemCount: _messages.length,
                    itemBuilder: (context, index) => _buildMessage(_messages[index]),
                  ),
          ),
          if (!_sessionEnded)
            SizedBox(
              height: 48,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.page, vertical: 6),
                itemCount: _quickReplies.length,
                separatorBuilder: (_, __) => const SizedBox(width: AppSpacing.xs),
                itemBuilder: (context, index) => AppFilterChip(
                  label: _quickReplies[index],
                  selected: false,
                  onTap: () {
                    if (!_isSending) _sendMessage(customText: _quickReplies[index]);
                  },
                ),
              ),
            ),
          Container(
            decoration: const BoxDecoration(
              color: AppColors.surface,
              border: Border(top: BorderSide(color: AppColors.border)),
            ),
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(AppSpacing.sm, AppSpacing.xs, AppSpacing.sm, AppSpacing.xs),
                child: _buildComposer(),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Compact pill used in the tools bar under the chat header.
class _ToolChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback? onTap;
  final bool filled;

  const _ToolChip({required this.icon, required this.label, required this.color, this.onTap, this.filled = false});

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    final fg = filled ? Colors.white : color;
    return Semantics(
      button: true,
      enabled: enabled,
      label: label,
      excludeSemantics: true,
      child: Opacity(
        opacity: enabled ? 1 : 0.5,
        child: Material(
          color: filled ? color : color.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(AppRadius.pill),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 44),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(icon, size: 16, color: fg),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: fg)),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
