import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/backend_service.dart';
import '../utils/app_routes.dart';
import '../widgets/chat/chat_markdown.dart';
import '../widgets/chat/chat_persona.dart';
import '../widgets/ui/app_ui.dart';

class ChatMessage {
  final String role; // 'user' or 'assistant'
  final String content;
  final bool isDiagnostic;
  final DateTime timestamp;

  /// True when this bubble represents a failed send (rendered as an error
  /// bubble with a retry action). [retryText] holds the user's original text.
  final bool isError;
  final String? retryText;

  ChatMessage({
    required this.role,
    required this.content,
    this.isDiagnostic = false,
    required this.timestamp,
    this.isError = false,
    this.retryText,
  });
}

class ChatbotScreen extends StatefulWidget {
  const ChatbotScreen({super.key});

  @override
  State<ChatbotScreen> createState() => _ChatbotScreenState();
}

class _ChatbotScreenState extends State<ChatbotScreen> with TickerProviderStateMixin {
  static const Duration _groupGap = Duration(minutes: 5);
  static const Duration _thinkingStep = Duration(milliseconds: 1600);
  static const Duration _revealTick = Duration(milliseconds: 40);

  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FocusNode _inputFocusNode = FocusNode();
  final List<ChatMessage> _messages = [];
  bool _isLoading = false;
  bool _isLoadingHistory = true;
  bool _initialized = false;
  bool _showScrollDown = false;
  int _unseenCount = 0;

  Map<String, dynamic>? _astrologer;
  late AnimationController _typingAnimationController;

  /// Messages added in this session that should animate in once.
  final Set<ChatMessage> _animateIn = {};

  // Progressive reveal of a freshly received reply.
  ChatMessage? _revealing;
  List<int> _revealEnds = const [];
  int _revealCount = 0;
  int _revealStep = 2;
  Timer? _revealTimer;

  // Honest "thinking" status while waiting for the reply.
  Timer? _thinkingTimer;
  int _thinkingIndex = 0;

  // Per-persona draft persistence.
  Timer? _draftTimer;
  SharedPreferences? _prefs;

  @override
  void initState() {
    super.initState();
    _typingAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    _inputFocusNode.addListener(_onInputFocusChanged);
    _scrollController.addListener(_onScroll);
    _messageController.addListener(_onDraftChanged);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_initialized) {
      _initialized = true;
      final args = ModalRoute.of(context)?.settings.arguments;
      if (args is Map) {
        _astrologer = Map<String, dynamic>.from(args);
      }
      _restoreDraft();
      _loadHistoryAndWelcome();
    }
  }

  String get _astroName {
    final n = _astrologer?['name']?.toString().trim() ?? '';
    return n.isEmpty ? 'Senior Astrologer' : n;
  }

  String get _specialty {
    final s = _astrologer?['specialty']?.toString().trim() ?? '';
    return s.isEmpty ? 'Vedic Advisor' : s;
  }

  String get _shortName => personaShortName(_astroName);
  String? get _imageUrl => _astrologer?['imageUrl']?.toString();
  ChatFocus get _focus => chatFocusFor(_astrologer?['field']?.toString(), _astrologer?['specialty']?.toString());
  bool get _hasKundli => Provider.of<BackendService>(context, listen: false).hasBirthDetails;
  bool get _reduceMotion => MediaQuery.maybeDisableAnimationsOf(context) ?? false;
  String get _draftKey => 'chat_draft_v1_${_astroName.toLowerCase()}';

  bool get _isNearBottom {
    if (!_scrollController.hasClients) return true;
    final pos = _scrollController.position;
    return pos.maxScrollExtent - pos.pixels < 140;
  }

  void _onInputFocusChanged() {
    // When the keyboard opens, keep the latest message visible.
    if (_inputFocusNode.hasFocus && _messages.isNotEmpty) {
      Future.delayed(const Duration(milliseconds: 350), () {
        if (mounted) _scrollToBottom();
      });
    }
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final pos = _scrollController.position;
    final show = pos.maxScrollExtent - pos.pixels > 320;
    if (show != _showScrollDown || (!show && _unseenCount > 0)) {
      setState(() {
        _showScrollDown = show;
        if (!show) _unseenCount = 0;
      });
    }
  }

  // ---------------------------------------------------------------------------
  // Draft persistence
  // ---------------------------------------------------------------------------

  Future<void> _restoreDraft() async {
    try {
      final prefs = _prefs ??= await SharedPreferences.getInstance();
      final saved = prefs.getString(_draftKey) ?? '';
      if (!mounted || saved.isEmpty || _messageController.text.isNotEmpty) return;
      _messageController.text = saved;
      _messageController.selection = TextSelection.collapsed(offset: saved.length);
    } catch (_) {
      // Drafts are a convenience only.
    }
  }

  void _onDraftChanged() {
    _draftTimer?.cancel();
    _draftTimer = Timer(const Duration(milliseconds: 400), _saveDraft);
  }

  Future<void> _saveDraft() async {
    final text = _messageController.text;
    try {
      final prefs = _prefs ??= await SharedPreferences.getInstance();
      if (text.trim().isEmpty) {
        await prefs.remove(_draftKey);
      } else {
        await prefs.setString(_draftKey, text);
      }
    } catch (_) {}
  }

  // ---------------------------------------------------------------------------
  // Backend flow (unchanged calls)
  // ---------------------------------------------------------------------------

  Future<void> _loadHistoryAndWelcome() async {
    final backendService = Provider.of<BackendService>(context, listen: false);
    List<Map<String, dynamic>> history = const [];
    String? historyError;
    try {
      // Throws BackendException on failure.
      history = await backendService.fetchChatHistory(astrologerName: _astroName);
    } on BackendException catch (e) {
      historyError = e.message;
    } catch (e) {
      debugPrint('Chat history load failed: $e');
      historyError = 'Could not load your previous conversation.';
    }
    if (!mounted) return;
    if (historyError != null) {
      showAppSnack(context, 'Previous messages unavailable: $historyError', error: true);
    }

    setState(() {
      _isLoadingHistory = false;
      _messages.clear();
      for (final item in history) {
        final content = item['content']?.toString() ?? '';
        if (content.trim().isEmpty) continue;
        _messages.add(
          ChatMessage(
            role: item['role'] == 'user' ? 'user' : 'assistant',
            content: content,
            isDiagnostic: item['isDiagnostic'] == true,
            timestamp: DateTime.tryParse(item['timestamp']?.toString() ?? '')?.toLocal() ?? DateTime.now(),
          ),
        );
      }
      // An empty conversation shows the welcome state (greeting + suggested
      // questions) instead of a canned message.
    });
    if (_messages.isNotEmpty) _scrollToBottom(animated: false);

    // Screens such as the Love tab / Family profiles open the chat with a
    // pre-composed question. Send it once the conversation has loaded.
    final initialMessage = _astrologer?['initialMessage']?.toString().trim() ?? '';
    if (initialMessage.isNotEmpty) {
      _astrologer!.remove('initialMessage');
      _sendMessage(initialMessage);
    }
  }

  Future<void> _sendMessage([String? overrideText]) async {
    final text = (overrideText ?? _messageController.text).trim();
    if (text.isEmpty || _isLoading) return;
    if (_revealing != null) _finishReveal(haptic: false);

    if (overrideText == null) _messageController.clear();
    HapticFeedback.lightImpact();
    final userMsg = ChatMessage(role: 'user', content: text, timestamp: DateTime.now());
    setState(() {
      _messages.add(userMsg);
      _animateIn.add(userMsg);
      _isLoading = true;
      _thinkingIndex = 0;
    });
    if (!_reduceMotion) _typingAnimationController.repeat();
    _thinkingTimer?.cancel();
    _thinkingTimer = Timer.periodic(_thinkingStep, (_) {
      if (mounted && _isLoading) setState(() => _thinkingIndex++);
    });
    _scrollToBottom();

    final backendService = Provider.of<BackendService>(context, listen: false);
    String? response;
    try {
      response = await backendService.sendChatMessage(
        text,
        astrologerName: _astroName,
        specialty: _astrologer?['specialty']?.toString(),
        field: _astrologer?['field']?.toString(),
      );
    } catch (e) {
      debugPrint('Chat send failed: $e');
      response = null;
    }

    if (!mounted) return;
    _typingAnimationController.stop();
    _thinkingTimer?.cancel();

    // sendChatMessage returns null on failure (reason in lastError).
    final reply = response?.trim() ?? '';
    final failed = reply.isEmpty;
    final errorText = backendService.lastError;
    final wasNearBottom = _isNearBottom;

    late final ChatMessage added;
    setState(() {
      _isLoading = false;
      if (failed) {
        added = ChatMessage(
          role: 'assistant',
          content: errorText ?? 'Could not reach $_astroName. Please check your connection and try again.',
          timestamp: DateTime.now(),
          isError: true,
          retryText: text,
        );
      } else {
        added = ChatMessage(
          role: 'assistant',
          content: reply,
          isDiagnostic: reply.contains('?') && reply.length < 250,
          timestamp: DateTime.now(),
        );
      }
      _messages.add(added);
      _animateIn.add(added);
      if (!wasNearBottom) _unseenCount++;
    });

    if (!failed) {
      _startReveal(added);
    }
    if (wasNearBottom) _scrollToBottom();
  }

  void _retry(ChatMessage errorMessage) {
    if (_isLoading || errorMessage.retryText == null) return;
    setState(() {
      final errorIndex = _messages.indexOf(errorMessage);
      if (errorIndex >= 0) {
        _messages.removeAt(errorIndex);
        // Remove the user bubble that preceded the error; it is re-added by _sendMessage.
        if (errorIndex > 0 &&
            _messages[errorIndex - 1].role == 'user' &&
            _messages[errorIndex - 1].content == errorMessage.retryText) {
          _messages.removeAt(errorIndex - 1);
        }
      }
    });
    _sendMessage(errorMessage.retryText);
  }

  // ---------------------------------------------------------------------------
  // Progressive reveal
  // ---------------------------------------------------------------------------

  void _startReveal(ChatMessage msg) {
    final ends = RegExp(r'\S+\s*').allMatches(msg.content).map((m) => m.end).toList();
    if (_reduceMotion || ends.length <= 4) {
      HapticFeedback.selectionClick();
      return;
    }
    // ~62 ticks of 40 ms keeps even long replies at about 2.5 s.
    _revealStep = math.max(2, (ends.length / 62).ceil());
    setState(() {
      _revealing = msg;
      _revealEnds = ends;
      _revealCount = 0;
    });
    _revealTimer?.cancel();
    _revealTimer = Timer.periodic(_revealTick, (_) => _revealTickHandler());
  }

  void _revealTickHandler() {
    if (!mounted || _revealing == null) return;
    final follow = _isNearBottom;
    final next = _revealCount + _revealStep;
    if (next >= _revealEnds.length) {
      _finishReveal();
      return;
    }
    setState(() => _revealCount = next);
    if (follow) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _scrollController.hasClients) {
          _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
        }
      });
    }
  }

  void _finishReveal({bool haptic = true}) {
    _revealTimer?.cancel();
    _revealTimer = null;
    if (_revealing == null) return;
    final follow = _isNearBottom;
    setState(() => _revealing = null);
    if (haptic) HapticFeedback.selectionClick();
    if (follow) _scrollToBottom();
  }

  String _visibleText(ChatMessage msg) {
    if (!identical(msg, _revealing) || _revealEnds.isEmpty) return msg.content;
    final end = _revealEnds[_revealCount.clamp(0, _revealEnds.length - 1)];
    var text = msg.content.substring(0, end).trimRight();
    // Close a bold run that is still being typed so it renders as bold.
    if ('**'.allMatches(text).length.isOdd) text = '$text**';
    return text;
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  void _scrollToBottom({bool animated = true}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      final target = _scrollController.position.maxScrollExtent;
      if (animated && !_reduceMotion) {
        _scrollController.animateTo(
          target,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      } else {
        _scrollController.jumpTo(target);
      }
    });
  }

  Future<void> _copy(String text, {String message = 'Reply copied'}) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (mounted) showAppSnack(context, message);
  }

  Future<void> _share(ChatMessage msg) async {
    final text = '${msg.content}\n\n— $_astroName, AI astrologer on CosmicGuide';
    try {
      await SharePlus.instance.share(ShareParams(text: text, subject: 'Astrology reply from $_astroName'));
    } catch (_) {
      await Clipboard.setData(ClipboardData(text: text));
      if (mounted) showAppSnack(context, 'Sharing is not available here, so the reply was copied');
    }
  }

  void _askFollowUp(ChatMessage msg) {
    final words = ChatMarkdown.plain(msg.content).split(' ');
    final snippet = words.take(8).join(' ');
    final quote = words.length > 8 ? '$snippet…' : snippet;
    final text = 'About "$quote": ';
    _messageController.text = text;
    _messageController.selection = TextSelection.collapsed(offset: text.length);
    _inputFocusNode.requestFocus();
  }

  void _insertStarter(String starter) {
    _messageController.text = starter;
    _messageController.selection = TextSelection.collapsed(offset: starter.length);
    _inputFocusNode.requestFocus();
  }

  void _copyConversation() {
    final real = _messages.where((m) => !m.isError).toList();
    if (real.isEmpty) {
      showAppSnack(context, 'Nothing to copy yet');
      return;
    }
    final text = real.map((m) => '${m.role == 'user' ? 'You' : _astroName}: ${m.content}').join('\n\n');
    _copy(text, message: 'Conversation copied');
  }

  void _showProfileSheet() {
    final bio = (_astrologer?['bio']?.toString().trim().isNotEmpty ?? false)
        ? _astrologer!['bio'].toString().trim()
        : personaFallbackBio(_focus);
    showAppSheet<void>(
      context,
      builder: (ctx) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(AppSpacing.page, 0, AppSpacing.page, AppSpacing.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(child: _PersonaPhoto(imageUrl: _imageUrl, name: _astroName, size: 104)),
              const SizedBox(height: AppSpacing.sm),
              Center(child: _NameWithAiBadge(name: _astroName, style: AppText.title)),
              const SizedBox(height: 4),
              Center(
                child: Text(_specialty, textAlign: TextAlign.center, style: AppText.body),
              ),
              const SizedBox(height: AppSpacing.md),
              Text(bio, style: AppText.body.copyWith(color: AppColors.textPrimary)),
              const SizedBox(height: AppSpacing.lg),
              const Text('How I can help', style: AppText.subtitle),
              const SizedBox(height: AppSpacing.xs),
              for (final b in personaHelpBullets(_focus))
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Padding(
                        padding: EdgeInsets.only(top: 2),
                        child: Icon(Icons.check_circle_outline_rounded, size: 18, color: AppColors.success),
                      ),
                      const SizedBox(width: AppSpacing.xs),
                      Expanded(child: Text(b, style: AppText.body)),
                    ],
                  ),
                ),
              const SizedBox(height: AppSpacing.md),
              AppCard(
                color: AppColors.infoSoft,
                border: false,
                padding: const EdgeInsets.all(AppSpacing.sm),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.auto_awesome_rounded, size: 20, color: AppColors.info),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Text(
                        '$_shortName is an AI astrologer, not a human. Answers are generated instantly'
                        '${_hasKundli ? ' from your saved birth chart' : ''} using Vedic astrology rules, and chatting is free. '
                        'Treat replies as guidance, not medical, legal or financial advice. '
                        'For a human reading, choose a live pandit in the Ask Astro tab.',
                        style: AppText.body.copyWith(color: AppColors.textPrimary),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              AppButton(label: 'Chat with $_shortName', onPressed: () => Navigator.pop(ctx)),
            ],
          ),
        ),
      ),
    );
  }

  void _showMessageActions(ChatMessage msg) {
    HapticFeedback.selectionClick();
    showAppSheet<void>(
      context,
      scrollable: false,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          AppListRow(
            icon: Icons.copy_rounded,
            title: 'Copy text',
            color: AppColors.primary,
            trailing: const SizedBox.shrink(),
            onTap: () {
              Navigator.pop(ctx);
              _copy(msg.content, message: msg.role == 'user' ? 'Message copied' : 'Reply copied');
            },
          ),
          if (msg.role == 'user' && !_isLoading)
            AppListRow(
              icon: Icons.edit_outlined,
              title: 'Edit and ask again',
              color: AppColors.primary,
              trailing: const SizedBox.shrink(),
              onTap: () {
                Navigator.pop(ctx);
                _insertStarter(msg.content);
              },
            ),
          const SizedBox(height: AppSpacing.xs),
        ]),
      ),
    );
  }

  @override
  void dispose() {
    _revealTimer?.cancel();
    _thinkingTimer?.cancel();
    if (_draftTimer?.isActive ?? false) {
      _draftTimer!.cancel();
      _saveDraft();
    }
    _inputFocusNode.removeListener(_onInputFocusChanged);
    _inputFocusNode.dispose();
    _scrollController.removeListener(_onScroll);
    _messageController.removeListener(_onDraftChanged);
    _typingAnimationController.dispose();
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final busy = _isLoading || _revealing != null;

    return Scaffold(
      backgroundColor: AppColors.background,
      resizeToAvoidBottomInset: true,
      appBar: AppBar(
        titleSpacing: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          tooltip: 'Back',
          onPressed: () => Navigator.maybePop(context),
        ),
        title: Semantics(
          button: true,
          label: 'View profile of $_astroName',
          child: InkWell(
            onTap: _showProfileSheet,
            borderRadius: BorderRadius.circular(AppRadius.md),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  AppAvatar(imageUrl: _imageUrl, name: _astroName, size: 40, online: true),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _NameWithAiBadge(
                          name: _astroName,
                          style: AppText.subtitle.copyWith(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 1),
                        AnimatedSwitcher(
                          duration: Duration(milliseconds: _reduceMotion ? 0 : 200),
                          child: Text(
                            busy ? '$_shortName is typing…' : 'Online · replies instantly',
                            key: ValueKey(busy),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppText.caption.copyWith(
                              color: busy ? AppColors.primary : AppColors.success,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        actions: [
          PopupMenuButton<String>(
            tooltip: 'More options',
            icon: const Icon(Icons.more_vert_rounded),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md)),
            color: AppColors.surface,
            onSelected: (v) {
              switch (v) {
                case 'about':
                  _showProfileSheet();
                case 'copy':
                  _copyConversation();
                case 'kundli':
                  Navigator.pushNamed(context, AppRoutes.kundliView);
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(
                value: 'about',
                child: _MenuRow(icon: Icons.info_outline_rounded, label: 'About this astrologer'),
              ),
              PopupMenuItem(
                value: 'kundli',
                child: _MenuRow(icon: Icons.auto_awesome_outlined, label: 'View my Kundli'),
              ),
              PopupMenuItem(
                value: 'copy',
                child: _MenuRow(icon: Icons.copy_rounded, label: 'Copy conversation'),
              ),
            ],
          ),
          const SizedBox(width: 4),
        ],
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(1),
          child: Divider(height: 1, color: AppColors.border),
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: Stack(
              children: [
                Positioned.fill(child: _buildBody()),
                Positioned(
                  right: AppSpacing.md,
                  bottom: AppSpacing.sm,
                  child: _buildScrollDownButton(),
                ),
              ],
            ),
          ),
          _buildInputBar(),
        ],
      ),
    );
  }

  Widget _buildScrollDownButton() {
    return AnimatedScale(
      scale: _showScrollDown ? 1 : 0,
      duration: Duration(milliseconds: _reduceMotion ? 0 : 180),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Material(
            color: AppColors.surface,
            shape: const CircleBorder(side: BorderSide(color: AppColors.border)),
            elevation: 2,
            shadowColor: AppColors.textPrimary.withValues(alpha: 0.2),
            child: IconButton(
              tooltip: _unseenCount > 0
                  ? '$_unseenCount new ${_unseenCount == 1 ? 'message' : 'messages'}, scroll to latest'
                  : 'Scroll to latest',
              icon: const Icon(Icons.keyboard_arrow_down_rounded, color: AppColors.textPrimary),
              onPressed: _showScrollDown ? () => _scrollToBottom() : null,
            ),
          ),
          if (_unseenCount > 0)
            Positioned(
              top: -4,
              right: -4,
              child: Container(
                constraints: const BoxConstraints(minWidth: 20, minHeight: 20),
                padding: const EdgeInsets.symmetric(horizontal: 5),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppColors.primary,
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                  border: Border.all(color: Colors.white, width: 2),
                ),
                child: Text(
                  _unseenCount > 9 ? '9+' : '$_unseenCount',
                  style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w800),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoadingHistory) return _buildHistorySkeleton();
    if (_messages.isEmpty && !_isLoading) return _buildWelcome();

    final followUps = _currentFollowUps();
    final extra = (_isLoading ? 1 : 0) + (followUps.isNotEmpty ? 1 : 0);

    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: ListView.builder(
        controller: _scrollController,
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: const EdgeInsets.fromLTRB(AppSpacing.page, AppSpacing.sm, AppSpacing.page, AppSpacing.md),
        itemCount: _messages.length + extra,
        itemBuilder: (context, index) {
          if (index >= _messages.length) {
            if (_isLoading) return _buildTypingBubble();
            return _FollowUpChips(
              key: ValueKey(_messages.last),
              questions: followUps,
              animate: !_reduceMotion,
              onTap: (q) => _sendMessage(q),
            );
          }
          final msg = _messages[index];
          final prev = index > 0 ? _messages[index - 1] : null;
          final next = index + 1 < _messages.length ? _messages[index + 1] : null;
          final showDate = prev == null || !_sameDay(prev.timestamp, msg.timestamp);
          final groupedWithPrev = !showDate && prev.role == msg.role && !prev.isError && !msg.isError &&
              msg.timestamp.difference(prev.timestamp) < _groupGap;
          final lastOfGroup = next == null ||
              next.role != msg.role ||
              next.isError ||
              msg.isError ||
              !_sameDay(msg.timestamp, next.timestamp) ||
              next.timestamp.difference(msg.timestamp) >= _groupGap;

          Widget bubble = _buildMessage(msg, next: next, showTime: lastOfGroup);
          if (_animateIn.contains(msg)) {
            bubble = _Appear(
              key: ObjectKey(msg),
              animate: !_reduceMotion,
              onDone: () => _animateIn.remove(msg),
              child: bubble,
            );
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (showDate) _DateSeparator(label: _dayLabel(msg.timestamp)),
              Padding(
                padding: EdgeInsets.only(top: groupedWithPrev ? 3 : AppSpacing.sm),
                child: bubble,
              ),
            ],
          );
        },
      ),
    );
  }

  List<String> _currentFollowUps() {
    if (_isLoading || _revealing != null || _messages.isEmpty) return const [];
    final last = _messages.last;
    if (last.role != 'assistant' || last.isError) return const [];
    String? lastUser;
    for (var i = _messages.length - 2; i >= 0; i--) {
      if (_messages[i].role == 'user') {
        lastUser = _messages[i].content;
        break;
      }
    }
    return followUpSuggestions(last.content, _focus, lastUserText: lastUser);
  }

  Widget _buildHistorySkeleton() {
    return ListView(
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.all(AppSpacing.page),
      children: const [
        Align(alignment: Alignment.centerLeft, child: SkeletonBox(width: 240, height: 64, radius: AppRadius.lg)),
        SizedBox(height: AppSpacing.md),
        Align(alignment: Alignment.centerRight, child: SkeletonBox(width: 180, height: 40, radius: AppRadius.lg)),
        SizedBox(height: AppSpacing.md),
        Align(alignment: Alignment.centerLeft, child: SkeletonBox(width: 280, height: 96, radius: AppRadius.lg)),
        SizedBox(height: AppSpacing.md),
        Align(alignment: Alignment.centerRight, child: SkeletonBox(width: 150, height: 40, radius: AppRadius.lg)),
      ],
    );
  }

  Widget _buildWelcome() {
    final backend = Provider.of<BackendService>(context, listen: false);
    final rawName = (backend.kundliData?['birthDetails']?['fullName'] ?? backend.user?['fullName'] ?? '')
        .toString()
        .trim();
    final firstName = rawName.isEmpty ? '' : rawName.split(RegExp(r'\s+')).first;
    final hasKundli = backend.hasBirthDetails;

    return ListView(
      controller: _scrollController,
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: const EdgeInsets.fromLTRB(AppSpacing.page, AppSpacing.xl, AppSpacing.page, AppSpacing.lg),
      children: [
        Center(
          child: Semantics(
            button: true,
            label: 'View profile of $_astroName',
            child: GestureDetector(
              onTap: _showProfileSheet,
              child: _PersonaPhoto(imageUrl: _imageUrl, name: _astroName, size: 96),
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Center(child: _NameWithAiBadge(name: _astroName, style: AppText.title)),
        const SizedBox(height: 2),
        Text(_specialty, textAlign: TextAlign.center, style: AppText.caption.copyWith(color: AppColors.textSecondary)),
        const SizedBox(height: AppSpacing.lg),
        AppCard(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(firstName.isEmpty ? 'Namaste!' : 'Namaste, $firstName!', style: AppText.title),
              const SizedBox(height: 6),
              Text(
                personaGreeting(_focus, _shortName, hasKundli: hasKundli),
                style: AppText.body.copyWith(color: AppColors.textPrimary, fontSize: 15),
              ),
            ],
          ),
        ),
        if (!hasKundli) ...[
          const SizedBox(height: AppSpacing.sm),
          AppCard(
            color: AppColors.warningSoft,
            border: false,
            onTap: () => Navigator.pushNamed(context, AppRoutes.birthDetails),
            padding: const EdgeInsets.all(AppSpacing.sm),
            child: Row(children: [
              const Icon(Icons.info_outline_rounded, color: AppColors.warning),
              const SizedBox(width: AppSpacing.sm),
              const Expanded(
                child: Text(
                  'Add your birth details for answers based on your own chart.',
                  style: AppText.bodyStrong,
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: AppColors.textSecondary.withValues(alpha: 0.8)),
            ]),
          ),
        ],
        const SizedBox(height: AppSpacing.xl),
        const Text('Try asking', style: AppText.subtitle),
        const SizedBox(height: AppSpacing.sm),
        for (final s in suggestedQuestions(_focus)) ...[
          _SuggestionCard(
            icon: s.$1,
            label: s.$2,
            onTap: _isLoading ? null : () => _sendMessage(s.$2),
          ),
          const SizedBox(height: AppSpacing.xs),
        ],
      ],
    );
  }

  Widget _buildMessage(ChatMessage msg, {ChatMessage? next, required bool showTime}) {
    final maxWidth = MediaQuery.sizeOf(context).width * 0.84;

    if (msg.isError) {
      return Align(
        alignment: Alignment.centerLeft,
        child: Container(
          constraints: BoxConstraints(maxWidth: maxWidth),
          padding: const EdgeInsets.fromLTRB(14, 12, 6, 4),
          decoration: BoxDecoration(
            color: AppColors.dangerSoft,
            borderRadius: BorderRadius.circular(AppRadius.lg),
            border: Border.all(color: AppColors.danger.withValues(alpha: 0.25)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.error_outline_rounded, color: AppColors.danger, size: 18),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: Text(
                        msg.content,
                        style: AppText.body.copyWith(color: AppColors.textPrimary),
                      ),
                    ),
                  ),
                ],
              ),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: _isLoading ? null : () => _retry(msg),
                  icon: const Icon(Icons.refresh_rounded, size: 18),
                  label: const Text('Retry'),
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.danger,
                    minimumSize: const Size(44, 44),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    final isUser = msg.role == 'user';
    final time = DateFormat('h:mm a').format(msg.timestamp);

    if (isUser) {
      // Single tick once sent, double tick once the astrologer has replied.
      final answered = next != null && next.role == 'assistant' && !next.isError;
      final failed = next != null && next.isError;
      return Align(
        alignment: Alignment.centerRight,
        child: GestureDetector(
          onLongPress: () => _showMessageActions(msg),
          child: Container(
            constraints: BoxConstraints(maxWidth: maxWidth),
            padding: const EdgeInsets.fromLTRB(14, 10, 12, 8),
            decoration: const BoxDecoration(
              color: AppColors.primary,
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(18),
                topRight: Radius.circular(18),
                bottomLeft: Radius.circular(18),
                bottomRight: Radius.circular(6),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(msg.content, style: const TextStyle(color: Colors.white, fontSize: 15, height: 1.4)),
                const SizedBox(height: 3),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (showTime)
                      Text(time, style: const TextStyle(color: AppColors.textOnDarkMuted, fontSize: 11)),
                    if (!failed) ...[
                      if (showTime) const SizedBox(width: 4),
                      Semantics(
                        label: answered ? 'Answered' : 'Sent',
                        child: Icon(
                          answered ? Icons.done_all_rounded : Icons.done_rounded,
                          size: 15,
                          color: AppColors.textOnDarkMuted,
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ),
      );
    }

    final revealing = identical(msg, _revealing);
    return Align(
      alignment: Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            GestureDetector(
              onTap: revealing ? () => _finishReveal() : null,
              onLongPress: revealing ? null : () => _showMessageActions(msg),
              child: Container(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(6),
                    topRight: Radius.circular(18),
                    bottomLeft: Radius.circular(18),
                    bottomRight: Radius.circular(18),
                  ),
                  border: Border.all(
                    color: msg.isDiagnostic ? AppColors.primary.withValues(alpha: 0.35) : AppColors.border,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (msg.isDiagnostic) ...[
                      const AppBadge(label: 'Question for you', icon: Icons.help_outline_rounded),
                      const SizedBox(height: AppSpacing.xs),
                    ],
                    ChatMarkdown(_visibleText(msg)),
                  ],
                ),
              ),
            ),
            if (revealing)
              Padding(
                padding: const EdgeInsets.only(left: 6, top: 4),
                child: Text('Tap to show the full answer', style: AppText.caption.copyWith(fontSize: 11)),
              )
            else
              Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  if (showTime)
                    Padding(
                      padding: const EdgeInsets.only(left: 6, right: 2),
                      child: Text(time, style: AppText.caption.copyWith(fontSize: 11)),
                    ),
                  _ActionIcon(icon: Icons.copy_rounded, tooltip: 'Copy reply', onTap: () => _copy(msg.content)),
                  _ActionIcon(icon: Icons.share_outlined, tooltip: 'Share reply', onTap: () => _share(msg)),
                  TextButton.icon(
                    onPressed: () => _askFollowUp(msg),
                    icon: const Icon(Icons.reply_rounded, size: 16),
                    label: const Text('Ask follow-up'),
                    style: TextButton.styleFrom(
                      foregroundColor: AppColors.textSecondary,
                      textStyle: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
                      minimumSize: const Size(44, 36),
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildTypingBubble() {
    final lines = thinkingLines(_focus, hasKundli: _hasKundli);
    final status = lines[_thinkingIndex % lines.length];
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.sm),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Semantics(
          liveRegion: true,
          label: '$_shortName is typing. $status',
          child: ExcludeSemantics(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.84),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(6),
                  topRight: Radius.circular(18),
                  bottomLeft: Radius.circular(18),
                  bottomRight: Radius.circular(18),
                ),
                border: Border.all(color: AppColors.border),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AnimatedBuilder(
                    animation: _typingAnimationController,
                    builder: (context, _) {
                      final v = _typingAnimationController.value;
                      return Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          for (int i = 0; i < 3; i++) ...[
                            if (i > 0) const SizedBox(width: 5),
                            _buildDot(i, v),
                          ],
                        ],
                      );
                    },
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Flexible(
                    child: AnimatedSwitcher(
                      duration: Duration(milliseconds: _reduceMotion ? 0 : 250),
                      child: Text(
                        status,
                        key: ValueKey(status),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppText.caption.copyWith(color: AppColors.textSecondary, fontSize: 13),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDot(int index, double t) {
    // Each dot rises and brightens in turn.
    final phase = ((t - index * 0.18) % 1.0 + 1.0) % 1.0;
    final wave = phase < 0.5 ? (phase * 2) : (2 - phase * 2); // 0..1..0
    final lift = _reduceMotion ? 0.0 : -3.0 * wave;
    final opacity = _reduceMotion ? 0.7 : 0.35 + 0.65 * wave;
    return Transform.translate(
      offset: Offset(0, lift),
      child: Container(
        width: 7,
        height: 7,
        decoration: BoxDecoration(
          color: AppColors.textTertiary.withValues(alpha: opacity),
          shape: BoxShape.circle,
        ),
      ),
    );
  }

  Widget _buildInputBar() {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ValueListenableBuilder<TextEditingValue>(
              valueListenable: _messageController,
              builder: (context, value, _) {
                final show = value.text.isEmpty && !_isLoadingHistory;
                return AnimatedSize(
                  duration: Duration(milliseconds: _reduceMotion ? 0 : 180),
                  alignment: Alignment.topCenter,
                  child: show
                      ? SizedBox(
                          height: 48,
                          child: ListView.separated(
                            scrollDirection: Axis.horizontal,
                            padding: const EdgeInsets.fromLTRB(AppSpacing.sm, AppSpacing.xs, AppSpacing.sm, 0),
                            itemCount: chatTopicStarters.length,
                            separatorBuilder: (_, __) => const SizedBox(width: AppSpacing.xs),
                            itemBuilder: (context, i) {
                              final (label, starter) = chatTopicStarters[i];
                              return _TopicChip(label: label, onTap: () => _insertStarter(starter));
                            },
                          ),
                        )
                      : const SizedBox(width: double.infinity),
                );
              },
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(AppSpacing.sm, AppSpacing.xs, AppSpacing.xs, AppSpacing.xs),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: TextField(
                      controller: _messageController,
                      focusNode: _inputFocusNode,
                      minLines: 1,
                      maxLines: 5,
                      maxLength: 2000,
                      textCapitalization: TextCapitalization.sentences,
                      textInputAction: TextInputAction.send,
                      style: const TextStyle(fontSize: 15, color: AppColors.textPrimary, height: 1.35),
                      decoration: InputDecoration(
                        hintText: 'Ask $_shortName anything…',
                        hintMaxLines: 1,
                        counterText: '',
                        filled: true,
                        fillColor: AppColors.surfaceMuted,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: BorderSide.none,
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: BorderSide.none,
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: BorderSide(color: AppColors.primary.withValues(alpha: 0.5)),
                        ),
                      ),
                      onSubmitted: (_) => _sendMessage(),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  ValueListenableBuilder<TextEditingValue>(
                    valueListenable: _messageController,
                    builder: (context, value, _) {
                      final canSend = value.text.trim().isNotEmpty && !_isLoading && !_isLoadingHistory;
                      return Semantics(
                        button: true,
                        enabled: canSend,
                        label: 'Send message',
                        child: AnimatedContainer(
                          duration: Duration(milliseconds: _reduceMotion ? 0 : 180),
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
                              onTap: canSend ? () => _sendMessage() : null,
                              child: Center(
                                child: _isLoading
                                    ? const SizedBox(
                                        width: 18,
                                        height: 18,
                                        child:
                                            CircularProgressIndicator(strokeWidth: 2, color: AppColors.textTertiary),
                                      )
                                    : AnimatedScale(
                                        scale: canSend ? 1 : 0.85,
                                        duration: Duration(milliseconds: _reduceMotion ? 0 : 180),
                                        child: Icon(
                                          Icons.arrow_upward_rounded,
                                          color: canSend ? Colors.white : AppColors.textTertiary,
                                          size: 22,
                                        ),
                                      ),
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
          ],
        ),
      ),
    );
  }

  static bool _sameDay(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;

  static String _dayLabel(DateTime d) {
    final now = DateTime.now();
    if (_sameDay(d, now)) return 'Today';
    if (_sameDay(d, now.subtract(const Duration(days: 1)))) return 'Yesterday';
    if (d.year == now.year) return DateFormat('EEE, d MMM').format(d);
    return DateFormat('d MMM yyyy').format(d);
  }
}

// -----------------------------------------------------------------------------
// Private widgets
// -----------------------------------------------------------------------------

/// Fades and slides a new bubble in once (180 ms, 8 px).
class _Appear extends StatefulWidget {
  final Widget child;
  final bool animate;
  final VoidCallback onDone;
  const _Appear({super.key, required this.child, required this.animate, required this.onDone});

  @override
  State<_Appear> createState() => _AppearState();
}

class _AppearState extends State<_Appear> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 180));

  @override
  void initState() {
    super.initState();
    if (widget.animate) {
      _c.forward().whenComplete(widget.onDone);
    } else {
      _c.value = 1;
      widget.onDone();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      child: widget.child,
      builder: (context, child) {
        final t = Curves.easeOut.transform(_c.value);
        return Opacity(
          opacity: t,
          child: Transform.translate(offset: Offset(0, 8 * (1 - t)), child: child),
        );
      },
    );
  }
}

class _PersonaPhoto extends StatelessWidget {
  final String? imageUrl;
  final String name;
  final double size;
  const _PersonaPhoto({required this.imageUrl, required this.name, required this.size});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.25), width: 3),
        boxShadow: AppShadows.glow(AppColors.primary),
        color: AppColors.surface,
      ),
      child: AppAvatar(imageUrl: imageUrl, name: name, size: size, online: true),
    );
  }
}

class _NameWithAiBadge extends StatelessWidget {
  final String name;
  final TextStyle style;
  const _NameWithAiBadge({required this.name, required this.style});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(child: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: style)),
        const SizedBox(width: 6),
        const AppBadge(label: 'AI', icon: Icons.auto_awesome_rounded, color: AppColors.info),
      ],
    );
  }
}

class _ActionIcon extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  const _ActionIcon({required this.icon, required this.tooltip, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: tooltip,
      visualDensity: VisualDensity.compact,
      constraints: const BoxConstraints(minWidth: 44, minHeight: 36),
      iconSize: 16,
      color: AppColors.textTertiary,
      icon: Icon(icon),
      onPressed: onTap,
    );
  }
}

class _FollowUpChips extends StatelessWidget {
  final List<String> questions;
  final bool animate;
  final ValueChanged<String> onTap;
  const _FollowUpChips({super.key, required this.questions, required this.animate, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.xs),
      child: _Appear(
        animate: animate,
        onDone: () {},
        child: Wrap(
          spacing: AppSpacing.xs,
          runSpacing: AppSpacing.xs,
          children: [
            for (final q in questions)
              Semantics(
                button: true,
                label: 'Ask: $q',
                excludeSemantics: true,
                child: Material(
                  color: AppColors.primarySoft,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppRadius.pill),
                    side: BorderSide(color: AppColors.primary.withValues(alpha: 0.3)),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: () => onTap(q),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(minHeight: 40),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                        child: Text(
                          q,
                          style: const TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w600,
                            color: AppColors.primaryDark,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _TopicChip extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _TopicChip({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Semantics(
        button: true,
        label: 'Start a question about $label',
        excludeSemantics: true,
        child: Material(
          color: AppColors.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.pill),
            side: const BorderSide(color: AppColors.border),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              child: Text(label,
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
            ),
          ),
        ),
      ),
    );
  }
}

class _MenuRow extends StatelessWidget {
  final IconData icon;
  final String label;
  const _MenuRow({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      Icon(icon, size: 20, color: AppColors.textSecondary),
      const SizedBox(width: AppSpacing.sm),
      Flexible(child: Text(label, style: AppText.bodyStrong)),
    ]);
  }
}

class _DateSeparator extends StatelessWidget {
  final String label;
  const _DateSeparator({required this.label});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.md, bottom: AppSpacing.xxs),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          decoration: BoxDecoration(
            color: AppColors.surfaceMuted,
            borderRadius: BorderRadius.circular(AppRadius.pill),
          ),
          child: Text(label, style: AppText.caption.copyWith(color: AppColors.textSecondary)),
        ),
      ),
    );
  }
}

class _SuggestionCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  const _SuggestionCard({required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Ask: $label',
      excludeSemantics: true,
      child: AppCard(
        onTap: onTap,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: 14),
        child: Row(children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(color: AppColors.primarySoft, borderRadius: BorderRadius.circular(10)),
            child: Icon(icon, size: 20, color: AppColors.primary),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(child: Text(label, style: AppText.bodyStrong.copyWith(fontSize: 15))),
          const SizedBox(width: AppSpacing.xs),
          const Icon(Icons.north_east_rounded, size: 18, color: AppColors.textTertiary),
        ]),
      ),
    );
  }
}
