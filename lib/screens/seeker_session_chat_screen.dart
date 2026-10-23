import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/backend_service.dart';
import '../utils/session_messages.dart';
import '../widgets/session_prescription_card.dart';
import '../widgets/ui/app_ui.dart';
import 'wallet_screen.dart';

double _toDouble(dynamic v, [double fallback = 0]) {
  if (v is num) return v.toDouble();
  if (v is String) return double.tryParse(v) ?? fallback;
  return fallback;
}

/// Live 1-on-1 chat between a seeker and a registered (human) Pandit.
///
/// Messages are polled from `/pandit/session/:id/messages`; billing happens
/// server-side when either participant ends the session.
class SeekerSessionChatScreen extends StatefulWidget {
  /// A `consultation_queue` row (id, pandit_id, started_at, status, ...).
  final Map<String, dynamic> session;
  final String panditName;
  final String specialty;
  final String avatarUrl;
  final double ratePerMin;

  const SeekerSessionChatScreen({
    super.key,
    required this.session,
    required this.panditName,
    this.specialty = 'Vedic Astrology',
    this.avatarUrl = '',
    this.ratePerMin = 0,
  });

  @override
  State<SeekerSessionChatScreen> createState() => _SeekerSessionChatScreenState();
}

class _SeekerSessionChatScreenState extends State<SeekerSessionChatScreen> {
  static const Duration _pollInterval = Duration(seconds: 3);
  static const int _maxSilentFailures = 3;

  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final List<SessionMessage> _messages = [];

  int? _sessionId;
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

  // Post-session summary
  bool _loadingSummary = false;
  int? _billedMinutes;
  double? _amountCharged;
  double? _balanceAfter;

  @override
  void initState() {
    super.initState();
    _sessionId = parseId(widget.session['id']);
    final started = DateTime.tryParse(widget.session['started_at']?.toString() ?? '');
    final now = DateTime.now();
    _sessionStart = (started != null && started.toLocal().isBefore(now)) ? started.toLocal() : now;
    _elapsed = now.difference(_sessionStart);

    if (_sessionId == null) return;

    _messages.add(SessionMessage.system(
      'You are connected with ${widget.panditName}. Session started at ${formatSessionClock(_sessionStart)}.',
    ));
    _clockTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted || _sessionEnded) return;
      setState(() => _elapsed = DateTime.now().difference(_sessionStart));
    });
    _pollTimer = Timer.periodic(_pollInterval, (_) => _pollMessages());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _pollMessages();
    });
  }

  @override
  void dispose() {
    _stopTimers();
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _stopTimers() {
    _clockTimer?.cancel();
    _pollTimer?.cancel();
    _clockTimer = null;
    _pollTimer = null;
  }

  /// Minutes billed so far are rounded up, like the server does.
  double get _estimatedCost {
    if (widget.ratePerMin <= 0) return 0;
    final minutes = (_elapsed.inSeconds / 60).ceil().clamp(1, 1 << 20);
    return minutes * widget.ratePerMin;
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

  Future<void> _pollMessages() async {
    final sessionId = _sessionId;
    if (sessionId == null || _isPolling || _sessionEnded || !mounted) return;
    _isPolling = true;
    Map<String, dynamic>? data;
    try {
      data = await Provider.of<BackendService>(context, listen: false)
          .fetchSessionMessages(sessionId, afterId: lastSessionMessageId(_messages));
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
      _onSessionEnded('${widget.panditName} has ended the consultation.');
    }
  }

  /// Locks the chat and loads the billing summary + fresh wallet balance.
  Future<void> _onSessionEnded(String reason, {Map<String, dynamic>? billing}) async {
    if (_sessionEnded || !mounted) return;
    _stopTimers();
    setState(() {
      _sessionEnded = true;
      _loadingSummary = true;
      _messages.add(SessionMessage.system(reason));
      if (billing != null) {
        final bal = billing['seekerBalance'];
        if (bal is num) _balanceAfter = bal.toDouble();
      }
    });
    _scrollToBottom();

    final backendService = Provider.of<BackendService>(context, listen: false);
    Map<String, dynamic>? history;
    double? balance;
    try {
      final results = await Future.wait<dynamic>([
        backendService.fetchConsultationHistory(),
        backendService.fetchWalletBalance(),
      ]);
      history = results[0] as Map<String, dynamic>?;
      balance = results[1] as double?;
    } catch (_) {
      // Summary is best-effort; fall back to the billing returned by /end.
    }
    if (!mounted) return;

    Map? row;
    final list = history?['history'];
    if (list is List) {
      for (final h in list) {
        if (h is Map && parseId(h['id']) == _sessionId) {
          row = h;
          break;
        }
      }
    }
    setState(() {
      _loadingSummary = false;
      if (row != null) {
        _billedMinutes = (row['billed_minutes'] as num?)?.toInt() ?? int.tryParse('${row['billed_minutes']}');
        _amountCharged = _toDouble(row['amount_charged']);
      } else if (billing != null) {
        _billedMinutes = (billing['minutesCharged'] as num?)?.toInt();
        _amountCharged = _toDouble(billing['amount']);
      }
      _balanceAfter = balance ?? _balanceAfter;
    });
  }

  Future<void> _sendMessage() async {
    final sessionId = _sessionId;
    if (_sessionEnded || _isSending || sessionId == null) return;
    final text = _messageController.text.trim();
    if (text.isEmpty) return;
    _messageController.clear();
    setState(() => _isSending = true);

    final backendService = Provider.of<BackendService>(context, listen: false);
    Map<String, dynamic>? saved;
    try {
      saved = await backendService.sendSessionMessage(sessionId, text);
    } catch (_) {
      saved = null;
    }
    if (!mounted) return;
    setState(() => _isSending = false);

    final msg = SessionMessage.fromJson(saved);
    if (msg == null) {
      if (_messageController.text.isEmpty) _messageController.text = text;
      showAppSnack(context, backendService.lastError ?? 'Message not sent. Please try again.', error: true);
      _pollMessages();
      return;
    }
    setState(() => mergeSessionMessages(_messages, [msg]));
    _scrollToBottom();
  }

  Future<bool> _confirmEnd() async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('End consultation?'),
        content: Text(
          'Your session with ${widget.panditName} (${formatSessionDuration(_elapsed)}) will end now. '
          'You are billed per started minute${widget.ratePerMin > 0 ? ' at ₹${widget.ratePerMin.toStringAsFixed(widget.ratePerMin % 1 == 0 ? 0 : 2)}/min' : ''}.',
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
    return result == true;
  }

  /// Ends the session. Returns true once the session is no longer active.
  Future<bool> _endSession() async {
    final sessionId = _sessionId;
    if (_isEnding) return false;
    if (_sessionEnded || sessionId == null) return true;
    if (!await _confirmEnd() || !mounted) return false;

    setState(() => _isEnding = true);
    final backendService = Provider.of<BackendService>(context, listen: false);
    Map<String, dynamic>? res;
    try {
      res = await backendService.endConsultationSession(sessionId);
    } catch (_) {
      res = null;
    }
    if (!mounted) return false;
    setState(() => _isEnding = false);

    if (res == null) {
      showAppSnack(context, backendService.lastError ?? 'Could not end the session. Please try again.', error: true);
      // It may already have been ended by the Pandit; the poll will confirm.
      _pollMessages();
      return false;
    }
    final billing = res['billing'];
    await _onSessionEnded(
      'You ended the consultation.',
      billing: billing is Map ? Map<String, dynamic>.from(billing) : null,
    );
    return true;
  }

  Future<void> _handleBack() async {
    if (_sessionEnded || _sessionId == null) {
      Navigator.pop(context);
      return;
    }
    final ended = await _endSession();
    if (ended && mounted) Navigator.pop(context);
  }

  Widget _buildMessage(SessionMessage msg) {
    if (msg.isSystem) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
        child: Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: AppColors.surfaceMuted,
              borderRadius: BorderRadius.circular(AppRadius.pill),
            ),
            child: Text(
              msg.content,
              textAlign: TextAlign.center,
              style: AppText.caption.copyWith(color: AppColors.textSecondary),
            ),
          ),
        ),
      );
    }
    if (msg.isPrescription) return SessionPrescriptionCard(message: msg, fromName: widget.panditName);

    final isMe = msg.senderRole == 'seeker';
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xs),
      child: Align(
        alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 8),
          constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.8),
          decoration: BoxDecoration(
            color: isMe ? AppColors.primary : AppColors.surface,
            borderRadius: BorderRadius.only(
              topLeft: Radius.circular(isMe ? 18 : 6),
              topRight: Radius.circular(isMe ? 18 : 18),
              bottomLeft: const Radius.circular(18),
              bottomRight: Radius.circular(isMe ? 6 : 18),
            ),
            border: isMe ? null : Border.all(color: AppColors.border),
          ),
          child: Column(
            crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                msg.content,
                style: TextStyle(
                  color: isMe ? Colors.white : AppColors.textPrimary,
                  fontSize: 15,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                formatSessionClock(msg.time),
                style: TextStyle(color: isMe ? AppColors.textOnDarkMuted : AppColors.textTertiary, fontSize: 11),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _summaryRow(String label, String value, {bool strong = false}) {
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.xs),
      child: Row(
        children: [
          Expanded(child: Text(label, style: AppText.body)),
          const SizedBox(width: AppSpacing.xs),
          Text(value, style: strong ? AppText.subtitle : AppText.bodyStrong),
        ],
      ),
    );
  }

  Widget _buildSummary() {
    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(AppSpacing.page, AppSpacing.md, AppSpacing.page, AppSpacing.sm),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: AppColors.successSoft,
                      borderRadius: BorderRadius.circular(AppRadius.sm),
                    ),
                    child: const Icon(Icons.receipt_long_rounded, color: AppColors.success, size: 20),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  const Expanded(child: Text('Consultation summary', style: AppText.title)),
                ],
              ),
              const SizedBox(height: AppSpacing.xs),
              if (_loadingSummary)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: AppSpacing.xs),
                  child: Column(children: [
                    SkeletonBox(height: 16),
                    SizedBox(height: AppSpacing.xs),
                    SkeletonBox(height: 16),
                    SizedBox(height: AppSpacing.xs),
                    SkeletonBox(height: 16),
                  ]),
                )
              else ...[
                _summaryRow('Duration', formatSessionDuration(_elapsed)),
                if (_billedMinutes != null) _summaryRow('Minutes billed', '$_billedMinutes min'),
                _summaryRow(
                  'Amount charged',
                  _amountCharged != null ? '₹${_amountCharged!.toStringAsFixed(2)}' : 'Unavailable',
                  strong: true,
                ),
                _summaryRow(
                  'Wallet balance',
                  _balanceAfter != null ? '₹${_balanceAfter!.toStringAsFixed(2)}' : 'Unavailable',
                ),
              ],
              const SizedBox(height: AppSpacing.md),
              Row(
                children: [
                  Expanded(
                    child: AppButton(
                      label: 'Wallet',
                      variant: AppButtonVariant.outline,
                      icon: Icons.account_balance_wallet_outlined,
                      height: 48,
                      onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const WalletScreen())),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: AppButton(
                      label: 'Done',
                      height: 48,
                      onPressed: () => Navigator.pop(context),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildComposer() {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(AppSpacing.sm, AppSpacing.xs, AppSpacing.xs, AppSpacing.xs),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: TextField(
                  controller: _messageController,
                  minLines: 1,
                  maxLines: 5,
                  textCapitalization: TextCapitalization.sentences,
                  textInputAction: TextInputAction.send,
                  onSubmitted: (_) => _sendMessage(),
                  style: const TextStyle(fontSize: 15, color: AppColors.textPrimary),
                  decoration: InputDecoration(
                    hintText: 'Message ${widget.panditName.split(' ').first}…',
                    hintMaxLines: 1,
                    filled: true,
                    fillColor: AppColors.surfaceMuted,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none),
                    enabledBorder:
                        OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(24),
                      borderSide: BorderSide(color: AppColors.primary.withValues(alpha: 0.5)),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              ValueListenableBuilder<TextEditingValue>(
                valueListenable: _messageController,
                builder: (context, value, _) {
                  final canSend = value.text.trim().isNotEmpty && !_isSending;
                  return Semantics(
                    button: true,
                    enabled: canSend,
                    label: 'Send message',
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      width: 46,
                      height: 46,
                      decoration: BoxDecoration(
                        color: canSend ? AppColors.primary : AppColors.border,
                        shape: BoxShape.circle,
                      ),
                      child: Material(
                        type: MaterialType.transparency,
                        shape: const CircleBorder(),
                        clipBehavior: Clip.antiAlias,
                        child: InkWell(
                          onTap: canSend ? _sendMessage : null,
                          child: Center(
                            child: _isSending
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.textTertiary),
                                  )
                                : Icon(Icons.arrow_upward_rounded,
                                    color: canSend ? Colors.white : AppColors.textTertiary, size: 22),
                          ),
                        ),
                      ),
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

  Widget _buildInvalidSession() {
    return Scaffold(
      appBar: AppBar(title: const Text('Consultation')),
      body: Center(
        child: SingleChildScrollView(
          child: AppStateView(
            icon: Icons.chat_bubble_outline_rounded,
            color: AppColors.warning,
            title: 'We could not open this consultation',
            message: 'Please go back and request it again.',
            actionLabel: 'Go back',
            onAction: () => Navigator.maybePop(context),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_sessionId == null) return _buildInvalidSession();
    final rate = widget.ratePerMin;
    final rateLabel = rate > 0 ? '₹${rate.toStringAsFixed(rate % 1 == 0 ? 0 : 2)}/min' : '';

    return PopScope(
      canPop: _sessionEnded,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _handleBack();
      },
      child: Scaffold(
        appBar: AppBar(
          titleSpacing: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_rounded),
            tooltip: 'Back',
            onPressed: _handleBack,
          ),
          title: Row(
            children: [
              AppAvatar(
                imageUrl: widget.avatarUrl.startsWith('http') ? widget.avatarUrl : null,
                name: widget.panditName,
                size: 40,
                online: !_sessionEnded,
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      widget.panditName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.subtitle.copyWith(fontWeight: FontWeight.w700),
                    ),
                    Text(
                      _sessionEnded ? 'Session ended' : 'Live · ${widget.specialty}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.caption.copyWith(
                        color: _sessionEnded ? AppColors.textTertiary : AppColors.success,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          actions: [
            if (!_sessionEnded)
              Padding(
                padding: const EdgeInsets.only(right: AppSpacing.xs),
                child: TextButton(
                  onPressed: _isEnding ? null : _endSession,
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.danger,
                    minimumSize: const Size(56, 44),
                  ),
                  child: _isEnding
                      ? const SizedBox(
                          width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.danger))
                      : const Text('End'),
                ),
              ),
          ],
          bottom: const PreferredSize(
            preferredSize: Size.fromHeight(1),
            child: Divider(height: 1, color: AppColors.border),
          ),
        ),
        body: Column(
          children: [
            // Session meter: elapsed time, rate and running estimate.
            Container(
              width: double.infinity,
              color: AppColors.surface,
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.page, vertical: AppSpacing.xs),
              child: Row(
                children: [
                  Icon(
                    _sessionEnded ? Icons.timer_off_outlined : Icons.timer_outlined,
                    size: 18,
                    color: _sessionEnded ? AppColors.textTertiary : AppColors.primary,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    formatSessionDuration(_elapsed),
                    style: AppText.bodyStrong.copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
                  ),
                  if (rate > 0) ...[
                    const SizedBox(width: AppSpacing.xs),
                    Flexible(
                      child: Text(
                        '· $rateLabel',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppText.caption.copyWith(color: AppColors.textSecondary),
                      ),
                    ),
                  ],
                  const Spacer(),
                  if (rate > 0 && !_sessionEnded)
                    AppBadge(
                      label: '≈ ₹${_estimatedCost.toStringAsFixed(0)} so far',
                      color: AppColors.textSecondary,
                      background: AppColors.surfaceMuted,
                    ),
                ],
              ),
            ),
            if (_pollFailures >= _maxSilentFailures && !_sessionEnded)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.page, vertical: AppSpacing.xs),
                color: AppColors.warningSoft,
                child: const Row(
                  children: [
                    SizedBox(
                        width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.warning)),
                    SizedBox(width: AppSpacing.xs),
                    Expanded(
                      child: Text(
                        'Connection issue. Reconnecting to the chat…',
                        style: TextStyle(fontSize: 13, color: AppColors.textPrimary),
                      ),
                    ),
                  ],
                ),
              ),
            Expanded(
              child: !_initialLoadDone
                  ? ListView(
                      physics: const NeverScrollableScrollPhysics(),
                      padding: const EdgeInsets.all(AppSpacing.page),
                      children: const [
                        Center(child: SkeletonBox(width: 220, height: 26, radius: AppRadius.pill)),
                        SizedBox(height: AppSpacing.md),
                        Align(
                            alignment: Alignment.centerLeft,
                            child: SkeletonBox(width: 220, height: 56, radius: AppRadius.lg)),
                        SizedBox(height: AppSpacing.sm),
                        Align(
                            alignment: Alignment.centerRight,
                            child: SkeletonBox(width: 160, height: 40, radius: AppRadius.lg)),
                      ],
                    )
                  : GestureDetector(
                      onTap: () => FocusScope.of(context).unfocus(),
                      child: ListView.builder(
                        controller: _scrollController,
                        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                        padding: const EdgeInsets.fromLTRB(AppSpacing.page, AppSpacing.sm, AppSpacing.page, AppSpacing.md),
                        itemCount: _messages.length,
                        itemBuilder: (context, index) => _buildMessage(_messages[index]),
                      ),
                    ),
            ),
            if (_sessionEnded) _buildSummary() else _buildComposer(),
          ],
        ),
      ),
    );
  }
}
