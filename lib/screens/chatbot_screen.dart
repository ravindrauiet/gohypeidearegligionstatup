import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/backend_service.dart';

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
  static const List<String> _quickPrompts = [
    'Career Promotion Time',
    'D9 Navamsha Marriage',
    'Active Dasha & Remedies',
    'Love & Soulmate compatibility',
    'Health & Energy Transits',
  ];

  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FocusNode _inputFocusNode = FocusNode();
  final List<ChatMessage> _messages = [];
  bool _isLoading = false;
  bool _isLoadingHistory = true;
  bool _initialized = false;

  Map<String, dynamic>? _astrologer;
  late AnimationController _typingAnimationController;

  @override
  void initState() {
    super.initState();
    _typingAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    _inputFocusNode.addListener(_onInputFocusChanged);
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

  void _onInputFocusChanged() {
    // When the keyboard opens, keep the latest message visible.
    if (_inputFocusNode.hasFocus) {
      Future.delayed(const Duration(milliseconds: 350), () {
        if (mounted) _scrollToBottom();
      });
    }
  }

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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Previous messages unavailable: $historyError')),
      );
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
      if (_messages.isEmpty) {
        _messages.add(
          ChatMessage(
            role: 'assistant',
            content:
                'Namaste! I am $_astroName, your ${_astrologer?['specialty'] ?? 'Vedic Astrology'} advisor. I have opened your Janam Kundli chart. How may I guide your life path today?',
            timestamp: DateTime.now(),
          ),
        );
      }
    });
    _scrollToBottom(animated: false);

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

    if (overrideText == null) _messageController.clear();
    setState(() {
      _messages.add(ChatMessage(
        role: 'user',
        content: text,
        timestamp: DateTime.now(),
      ));
      _isLoading = true;
    });
    _typingAnimationController.repeat();
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

    // sendChatMessage returns null on failure (reason in lastError).
    final reply = response?.trim() ?? '';
    final failed = reply.isEmpty;
    final errorText = backendService.lastError;

    setState(() {
      _isLoading = false;
      if (failed) {
        _messages.add(ChatMessage(
          role: 'assistant',
          content: errorText ?? 'Could not reach $_astroName. Please check your connection and try again.',
          timestamp: DateTime.now(),
          isError: true,
          retryText: text,
        ));
      } else {
        _messages.add(ChatMessage(
          role: 'assistant',
          content: reply,
          isDiagnostic: reply.contains('?') && reply.length < 250,
          timestamp: DateTime.now(),
        ));
      }
    });
    _scrollToBottom();
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

  void _scrollToBottom({bool animated = true}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      final target = _scrollController.position.maxScrollExtent;
      if (animated) {
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

  @override
  void dispose() {
    _inputFocusNode.removeListener(_onInputFocusChanged);
    _inputFocusNode.dispose();
    _typingAnimationController.dispose();
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Widget _buildInitialAvatar(String name, double fontSize) {
    return Center(
      child: Text(
        name.isNotEmpty ? name[0].toUpperCase() : 'A',
        style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: fontSize),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final astroName = _astroName;
    final specialty = _specialty;
    final rawBg = _astrologer?['avatarBg'];
    final Color avatarBg = rawBg is Color ? rawBg : const Color(0xFFE83D66);
    final String imageUrl = _astrologer?['imageUrl']?.toString() ?? '';

    return Scaffold(
      backgroundColor: const Color(0xFFFCF7F1),
      resizeToAvoidBottomInset: true,
      appBar: AppBar(
        backgroundColor: const Color(0xFFFCF7F1),
        elevation: 0,
        titleSpacing: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, color: Colors.black, size: 20),
          tooltip: 'Back',
          onPressed: () => Navigator.maybePop(context),
        ),
        title: Row(
          children: [
            // Profile Image / Initial Avatar with Live Green Status Dot
            Stack(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: avatarBg,
                    shape: BoxShape.circle,
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(20),
                    child: imageUrl.isNotEmpty
                        ? Image.network(
                            imageUrl,
                            fit: BoxFit.cover,
                            width: 40,
                            height: 40,
                            errorBuilder: (context, error, stackTrace) => _buildInitialAvatar(astroName, 16),
                          )
                        : _buildInitialAvatar(astroName, 16),
                  ),
                ),
                Positioned(
                  right: 0,
                  bottom: 0,
                  child: Container(
                    width: 11,
                    height: 11,
                    decoration: BoxDecoration(
                      color: const Color(0xFF4CAF50),
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 2),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    astroName,
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.black),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    _isLoading ? 'typing...' : specialty,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: _isLoading ? FontWeight.bold : FontWeight.w500,
                      color: _isLoading ? const Color(0xFFE83D66) : Colors.grey.shade600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          Container(
            margin: const EdgeInsets.only(right: 12, left: 8),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xFF4CAF50).withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFF4CAF50).withValues(alpha: 0.3)),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.circle, color: Color(0xFF4CAF50), size: 8),
                SizedBox(width: 6),
                Text(
                  'ONLINE',
                  style: TextStyle(
                    color: Color(0xFF2E7D32),
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          // Active Session Info Banner
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            color: Colors.white,
            child: Row(
              children: [
                const Icon(Icons.verified_user_rounded, color: Color(0xFF7C77E6), size: 16),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '1-on-1 Consultation • $astroName is reviewing your birth chart',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade800, fontWeight: FontWeight.w600),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),

          // Messages List
          Expanded(
            child: _isLoadingHistory
                ? const Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CircularProgressIndicator(color: Color(0xFFE83D66)),
                        SizedBox(height: 12),
                        Text('Loading your conversation...', style: TextStyle(color: Colors.black54)),
                      ],
                    ),
                  )
                : GestureDetector(
                    onTap: () => FocusScope.of(context).unfocus(),
                    child: ListView.builder(
                      controller: _scrollController,
                      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                      padding: const EdgeInsets.all(16),
                      itemCount: _messages.length + (_isLoading ? 1 : 0),
                      itemBuilder: (context, index) {
                        if (index == _messages.length && _isLoading) {
                          return _buildAstrologerTypingBubble(astroName);
                        }
                        return _buildMessageBubble(_messages[index]);
                      },
                    ),
                  ),
          ),

          // Quick Astrological Questions Chips
          Container(
            height: 44,
            color: Colors.white,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              children: _quickPrompts
                  .map((prompt) => Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ActionChip(
                          backgroundColor: const Color(0xFFFCF7F1),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          label: Text(prompt,
                              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.black87)),
                          onPressed: (_isLoading || _isLoadingHistory) ? null : () => _sendMessage(prompt),
                        ),
                      ))
                  .toList(),
            ),
          ),

          // Message Input Field
          Container(
            color: Colors.white,
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
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
                        style: const TextStyle(fontSize: 15),
                        decoration: InputDecoration(
                          hintText: 'Message $astroName...',
                          hintMaxLines: 1,
                          counterText: '',
                          hintStyle: TextStyle(color: Colors.grey.shade400),
                          filled: true,
                          fillColor: const Color(0xFFFCF7F1),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(24),
                            borderSide: BorderSide.none,
                          ),
                        ),
                        onSubmitted: (_) => _sendMessage(),
                      ),
                    ),
                    const SizedBox(width: 8),
                    ValueListenableBuilder<TextEditingValue>(
                      valueListenable: _messageController,
                      builder: (context, value, _) {
                        final canSend = value.text.trim().isNotEmpty && !_isLoading && !_isLoadingHistory;
                        return Material(
                          color: canSend ? const Color(0xFFE83D66) : Colors.grey.shade300,
                          shape: const CircleBorder(),
                          child: InkWell(
                            customBorder: const CircleBorder(),
                            onTap: canSend ? () => _sendMessage() : null,
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: _isLoading
                                  ? const SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                    )
                                  : const Icon(Icons.send_rounded, color: Colors.white, size: 20),
                            ),
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMessageBubble(ChatMessage msg) {
    final isUser = msg.role == 'user';
    final maxWidth = MediaQuery.of(context).size.width * 0.82;

    if (msg.isError) {
      return Align(
        alignment: Alignment.centerLeft,
        child: Container(
          margin: const EdgeInsets.only(bottom: 12),
          constraints: BoxConstraints(maxWidth: maxWidth),
          padding: const EdgeInsets.fromLTRB(14, 12, 6, 6),
          decoration: BoxDecoration(
            color: const Color(0xFFFFEBEE),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.redAccent.withValues(alpha: 0.4)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.error_outline_rounded, color: Colors.redAccent, size: 18),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      msg.content,
                      style: const TextStyle(fontSize: 13, color: Color(0xFFB71C1C), height: 1.35),
                    ),
                  ),
                ],
              ),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: _isLoading ? null : () => _retry(msg),
                  icon: const Icon(Icons.refresh_rounded, size: 16),
                  label: const Text('Retry', style: TextStyle(fontWeight: FontWeight.bold)),
                  style: TextButton.styleFrom(foregroundColor: const Color(0xFFB71C1C)),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Column(
        crossAxisAlignment: isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          if (msg.isDiagnostic && !isUser)
            Container(
              margin: const EdgeInsets.only(bottom: 4, left: 4),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFFFFB74D),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.help_outline_rounded, size: 12, color: Colors.black),
                  SizedBox(width: 4),
                  Text(
                    'Astrologer Question',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.black),
                  ),
                ],
              ),
            ),
          Container(
              margin: const EdgeInsets.only(bottom: 4),
              constraints: BoxConstraints(maxWidth: maxWidth),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: isUser ? const Color(0xFF1E1A17) : Colors.white,
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(18),
                  topRight: const Radius.circular(18),
                  bottomLeft: Radius.circular(isUser ? 18 : 4),
                  bottomRight: Radius.circular(isUser ? 4 : 18),
                ),
                border: msg.isDiagnostic ? Border.all(color: const Color(0xFFFFB74D), width: 1.5) : null,
                boxShadow: [
                  if (!isUser)
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.04),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                ],
              ),
            child: SelectableText.rich(
              TextSpan(children: _formatSpans(msg.content, isUser ? Colors.white : Colors.black87)),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(bottom: 10, left: 4, right: 4),
            child: Text(
              _formatTime(msg.timestamp),
              style: TextStyle(fontSize: 10, color: Colors.grey.shade500),
            ),
          ),
        ],
      ),
    );
  }

  String _formatTime(DateTime t) {
    final h = t.hour % 12 == 0 ? 12 : t.hour % 12;
    final m = t.minute.toString().padLeft(2, '0');
    return '$h:$m ${t.hour < 12 ? 'AM' : 'PM'}';
  }

  /// Renders **bold** markdown segments returned by the AI astrologer.
  List<TextSpan> _formatSpans(String text, Color color) {
    final base = TextStyle(fontSize: 14, color: color, height: 1.4);
    final bold = base.copyWith(fontWeight: FontWeight.bold);
    final spans = <TextSpan>[];
    final exp = RegExp(r'\*\*(.+?)\*\*', dotAll: true);
    var start = 0;
    for (final match in exp.allMatches(text)) {
      if (match.start > start) spans.add(TextSpan(text: text.substring(start, match.start), style: base));
      spans.add(TextSpan(text: match.group(1), style: bold));
      start = match.end;
    }
    if (start < text.length) spans.add(TextSpan(text: text.substring(start), style: base));
    return spans;
  }

  // Realistic Astrologer Typing Bubble Widget
  Widget _buildAstrologerTypingBubble(String name) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.82),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(18),
            topRight: Radius.circular(18),
            bottomRight: Radius.circular(18),
            bottomLeft: Radius.circular(4),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Text(
                '$name is typing',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey.shade700,
                ),
              ),
            ),
            const SizedBox(width: 8),
            AnimatedBuilder(
              animation: _typingAnimationController,
              builder: (context, child) {
                final value = _typingAnimationController.value;
                return Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildDot(0, value),
                    const SizedBox(width: 3),
                    _buildDot(1, value),
                    const SizedBox(width: 3),
                    _buildDot(2, value),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDot(int index, double animationValue) {
    final double opacity = ((animationValue * 3 - index) % 1.0).clamp(0.2, 1.0);
    return Opacity(
      opacity: opacity,
      child: Container(
        width: 6,
        height: 6,
        decoration: const BoxDecoration(
          color: Color(0xFFE83D66),
          shape: BoxShape.circle,
        ),
      ),
    );
  }
}
