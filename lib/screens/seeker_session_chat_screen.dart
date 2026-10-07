import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/backend_service.dart';
import '../utils/session_messages.dart';
import '../widgets/session_prescription_card.dart';
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(backendService.lastError ?? 'Message not sent. Please try again.'),
          backgroundColor: Colors.red,
        ),
      );
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
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Keep Chatting')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('End Session', style: TextStyle(color: Colors.white)),
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(backendService.lastError ?? 'Could not end the session. Please try again.'),
          backgroundColor: Colors.red,
        ),
      );
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
        padding: const EdgeInsets.only(bottom: 12),
        child: Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(color: Colors.grey.shade200, borderRadius: BorderRadius.circular(12)),
            child: Text(msg.content, textAlign: TextAlign.center, style: const TextStyle(fontSize: 11, color: Colors.black54)),
          ),
        ),
      );
    }
    if (msg.isPrescription) return SessionPrescriptionCard(message: msg, fromName: widget.panditName);

    final isMe = msg.senderRole == 'seeker';
    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.78),
        decoration: BoxDecoration(
          color: isMe ? Colors.black : Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: isMe ? null : Border.all(color: Colors.grey.shade200),
        ),
        child: Column(
          crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            Text(msg.content, style: TextStyle(color: isMe ? Colors.white : Colors.black, fontSize: 14, height: 1.4)),
            const SizedBox(height: 4),
            Text(formatSessionClock(msg.time), style: TextStyle(color: isMe ? Colors.white60 : Colors.grey, fontSize: 10)),
          ],
        ),
      ),
    );
  }

  Widget _summaryRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        children: [
          Expanded(child: Text(label, style: const TextStyle(fontSize: 13, color: Colors.black54))),
          Text(value, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.black)),
        ],
      ),
    );
  }

  Widget _buildSummary() {
    return SafeArea(
      top: false,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border(top: BorderSide(color: Colors.grey.shade200)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.receipt_long_rounded, color: Color(0xFF059669), size: 20),
                SizedBox(width: 8),
                Expanded(
                  child: Text('Consultation Summary', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                ),
              ],
            ),
            if (_loadingSummary)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))),
              )
            else ...[
              _summaryRow('Duration', formatSessionDuration(_elapsed)),
              if (_billedMinutes != null) _summaryRow('Minutes billed', '$_billedMinutes min'),
              _summaryRow(
                'Amount charged',
                _amountCharged != null ? '₹${_amountCharged!.toStringAsFixed(2)}' : 'Unavailable',
              ),
              _summaryRow(
                'Wallet balance',
                _balanceAfter != null ? '₹${_balanceAfter!.toStringAsFixed(2)}' : 'Unavailable',
              ),
            ],
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const WalletScreen())),
                    child: const FittedBox(fit: BoxFit.scaleDown, child: Text('Wallet')),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(context),
                    child: const FittedBox(fit: BoxFit.scaleDown, child: Text('Done')),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildComposer() {
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
        color: Colors.white,
        child: Row(
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
                  hintText: 'Ask ${widget.panditName.split(' ').first}...',
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
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFFE83D66)))
                  : const Icon(Icons.send_rounded, color: Color(0xFFE83D66)),
              tooltip: 'Send',
              onPressed: _isSending ? null : _sendMessage,
            ),
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
                'We could not open this consultation. Please go back and request it again.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.black54),
              ),
              const SizedBox(height: 16),
              ElevatedButton(onPressed: () => Navigator.maybePop(context), child: const Text('Go Back')),
            ],
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
    final subtitle = _sessionEnded
        ? 'Session ended · ${formatSessionDuration(_elapsed)}'
        : '${formatSessionDuration(_elapsed)}'
            '${rate > 0 ? ' · $rateLabel · ≈₹${_estimatedCost.toStringAsFixed(0)}' : ''}';

    return PopScope(
      canPop: _sessionEnded,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _handleBack();
      },
      child: Scaffold(
        backgroundColor: const Color(0xFFFCF7F1),
        appBar: AppBar(
          backgroundColor: const Color(0xFFFCF7F1),
          elevation: 0,
          titleSpacing: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.black),
            tooltip: 'Back',
            onPressed: _handleBack,
          ),
          title: Row(
            children: [
              CircleAvatar(
                radius: 18,
                backgroundColor: const Color(0xFFFFF7ED),
                foregroundImage: widget.avatarUrl.startsWith('http') ? NetworkImage(widget.avatarUrl) : null,
                onForegroundImageError: widget.avatarUrl.startsWith('http') ? (_, __) {} : null,
                child: const Icon(Icons.person_rounded, color: Color(0xFFFB9548), size: 20),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.panditName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: _sessionEnded ? Colors.grey : const Color(0xFF059669),
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          actions: [
            if (!_sessionEnded)
              TextButton(
                onPressed: _isEnding ? null : _endSession,
                child: _isEnding
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.red))
                    : const Text('End', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
              ),
          ],
        ),
        body: Column(
          children: [
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
            if (_sessionEnded) _buildSummary() else _buildComposer(),
          ],
        ),
      ),
    );
  }
}
