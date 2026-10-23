import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../services/backend_service.dart';
import '../utils/session_messages.dart';
import '../widgets/ui/app_ui.dart';
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

    showAppSnack(context, '$panditName is ready. Opening your chat…');

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
          FilledButton(
            onPressed: () => Navigator.pop(ctx),
            style: FilledButton.styleFrom(minimumSize: const Size(64, 44)),
            child: const Text('OK'),
          ),
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
        content: Text('You will lose your current spot (#$pos) and need to request again.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            style: TextButton.styleFrom(foregroundColor: AppColors.textSecondary),
            child: const Text('Keep my spot'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger, minimumSize: const Size(64, 44)),
            child: const Text('Leave queue'),
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

    final String waitLine = overdue
        ? 'Taking a little longer than estimated. Stay on this screen and we will connect you automatically.'
        : queuePos <= 1
            ? 'You are next. The pandit is finishing the current session.'
            : '${queuePos - 1} ${queuePos - 1 == 1 ? 'person' : 'people'} ahead of you · $totalWaiting waiting in total';

    return PopScope(
      canPop: _hasExited,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _confirmLeaveQueue();
      },
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_rounded),
            tooltip: 'Leave queue',
            onPressed: _confirmLeaveQueue,
          ),
          title: const Text('Waiting room', overflow: TextOverflow.ellipsis),
          actions: [
            IconButton(
              tooltip: _audioVibrateEnabled ? 'Mute turn alert' : 'Enable turn alert',
              icon: Icon(
                _audioVibrateEnabled ? Icons.notifications_active_outlined : Icons.notifications_off_outlined,
                color: _audioVibrateEnabled ? AppColors.primary : AppColors.textTertiary,
              ),
              onPressed: () {
                setState(() => _audioVibrateEnabled = !_audioVibrateEnabled);
                showAppSnack(
                  context,
                  _audioVibrateEnabled
                      ? 'We will vibrate and play a sound when it is your turn.'
                      : 'Turn alert muted.',
                );
              },
            ),
            const SizedBox(width: 4),
          ],
          bottom: const PreferredSize(
            preferredSize: Size.fromHeight(1),
            child: Divider(height: 1, color: AppColors.border),
          ),
        ),
        bottomNavigationBar: Container(
          decoration: const BoxDecoration(
            color: AppColors.surface,
            border: Border(top: BorderSide(color: AppColors.border)),
          ),
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(AppSpacing.page, AppSpacing.sm, AppSpacing.page, AppSpacing.sm),
              child: SizedBox(
                height: 50,
                child: OutlinedButton.icon(
                  onPressed: _confirmLeaveQueue,
                  icon: const Icon(Icons.logout_rounded, size: 20),
                  label: const Text('Leave queue'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.danger,
                    side: BorderSide(color: AppColors.danger.withValues(alpha: 0.4)),
                  ),
                ),
              ),
            ),
          ),
        ),
        body: ListView(
          padding: const EdgeInsets.all(AppSpacing.page),
          children: [
            if (_consecutiveFailures >= _maxSilentFailures)
              Container(
                margin: const EdgeInsets.only(bottom: AppSpacing.sm),
                padding: const EdgeInsets.all(AppSpacing.sm),
                decoration: BoxDecoration(
                  color: AppColors.warningSoft,
                  borderRadius: BorderRadius.circular(AppRadius.md),
                ),
                child: const Row(
                  children: [
                    SizedBox(
                        width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.warning)),
                    SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Text(
                        'Connection issue. Reconnecting to the queue; your spot is safe.',
                        style: TextStyle(fontSize: 13, color: AppColors.textPrimary),
                      ),
                    ),
                  ],
                ),
              ),

            // 1. Queue position + live countdown
            Semantics(
              liveRegion: true,
              label: 'Queue position $queuePos. '
                  '${overdue ? 'Any moment now' : 'Estimated wait ${_formatTimer(_secondsRemaining)}'}',
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(AppSpacing.xl),
                decoration: BoxDecoration(
                  gradient: AppColors.cosmicGradient,
                  borderRadius: BorderRadius.circular(AppRadius.xl),
                ),
                child: ExcludeSemantics(
                  child: Column(
                    children: [
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        child: AppBadge(
                          label: 'Position #$queuePos in line',
                          icon: Icons.confirmation_number_outlined,
                          color: AppColors.gold,
                          background: Colors.white.withValues(alpha: 0.10),
                        ),
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      Text(
                        overdue ? 'Your turn is close' : 'Estimated wait',
                        style: const TextStyle(color: AppColors.textOnDarkMuted, fontSize: 13),
                      ),
                      const SizedBox(height: 4),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          overdue ? 'Any moment now' : _formatTimer(_secondsRemaining),
                          style: TextStyle(
                            color: AppColors.textOnDark,
                            fontSize: overdue ? 30 : 46,
                            fontWeight: FontWeight.w800,
                            letterSpacing: overdue ? -0.4 : 1.0,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      Text(
                        waitLine,
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: AppColors.textOnDarkMuted, fontSize: 13, height: 1.45),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            const SizedBox(height: AppSpacing.md),

            // 2. Pandit profile & activity
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      AppAvatar(
                        imageUrl: avatarUrl.startsWith('http') ? avatarUrl : null,
                        name: panditName,
                        size: 52,
                        online: true,
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(panditName, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.subtitle),
                            const SizedBox(height: 2),
                            Text(specialty,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: AppText.caption.copyWith(color: AppColors.textSecondary)),
                            const SizedBox(height: 6),
                            Wrap(
                              spacing: 6,
                              runSpacing: 4,
                              children: [
                                const AppBadge(
                                    label: 'Human · Live', icon: Icons.verified_user_outlined, color: AppColors.success),
                                AppBadge(
                                  label: '₹${ratePerMin.toStringAsFixed(ratePerMin % 1 == 0 ? 0 : 2)}/min',
                                  color: AppColors.textSecondary,
                                  background: AppColors.surfaceMuted,
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.md),
                  const Divider(height: 1),
                  const SizedBox(height: AppSpacing.sm),
                  Row(
                    children: [
                      Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: AppColors.successSoft,
                          borderRadius: BorderRadius.circular(AppRadius.sm),
                        ),
                        child: const Icon(Icons.forum_outlined, color: AppColors.success, size: 18),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(child: Text(_activeSessionLabel(), style: AppText.body)),
                    ],
                  ),
                ],
              ),
            ),

            const SizedBox(height: AppSpacing.md),

            // 3. Kundli shared with the pandit
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Expanded(child: Text('Shared for this session', style: AppText.subtitle)),
                      AppBadge(
                        label: hasKundli ? 'Kundli ready' : 'No Kundli yet',
                        icon: hasKundli ? Icons.check_circle_outline_rounded : Icons.info_outline_rounded,
                        color: hasKundli ? AppColors.success : AppColors.warning,
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Row(
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: AppColors.infoSoft,
                          borderRadius: BorderRadius.circular(AppRadius.md),
                        ),
                        child: const Icon(Icons.person_outline_rounded, color: AppColors.info, size: 22),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(seekerDisplayName,
                                maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.bodyStrong),
                            Text(
                              hasKundli
                                  ? 'Lagna: ${userKundli['ascendant']} · Moon: ${userKundli['moonSign'] ?? '—'}'
                                  : 'Birth chart not generated yet',
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: AppText.caption,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    hasKundli
                        ? 'The pandit will review this chart as soon as your chat opens.'
                        : 'Tip: share your date, time and place of birth in the chat for an accurate reading.',
                    style: AppText.caption.copyWith(color: AppColors.textSecondary),
                  ),
                ],
              ),
            ),

            const SizedBox(height: AppSpacing.md),

            // 4. What happens next
            const AppCard(
              color: AppColors.surfaceMuted,
              border: false,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.info_outline_rounded, size: 20, color: AppColors.textSecondary),
                  SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      'Keep this screen open. When it is your turn we will alert you and open the chat automatically.',
                      style: AppText.body,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
