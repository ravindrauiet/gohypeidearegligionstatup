import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/backend_service.dart';

class ChatMessage {
  final String role; // 'user' or 'assistant'
  final String content;
  final bool isDiagnostic;
  final DateTime timestamp;

  ChatMessage({
    required this.role,
    required this.content,
    this.isDiagnostic = false,
    required this.timestamp,
  });
}

class ChatbotScreen extends StatefulWidget {
  const ChatbotScreen({super.key});

  @override
  State<ChatbotScreen> createState() => _ChatbotScreenState();
}

class _ChatbotScreenState extends State<ChatbotScreen> with TickerProviderStateMixin {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final List<ChatMessage> _messages = [];
  bool _isLoading = false;
  bool _initialized = false;

  Map<String, dynamic>? _astrologer;
  late AnimationController _typingAnimationController;

  @override
  void initState() {
    super.initState();
    _typingAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_initialized) {
      final args = ModalRoute.of(context)?.settings.arguments;
      if (args is Map<String, dynamic>) {
        _astrologer = args;
      }

      _loadHistoryAndWelcome();
      _initialized = true;
    }
  }

  Future<void> _loadHistoryAndWelcome() async {
    final backendService = Provider.of<BackendService>(context, listen: false);
    final history = await backendService.fetchChatHistory(astrologerName: _astrologer?['name']);

    if (mounted) {
      if (history.isNotEmpty) {
        setState(() {
          _messages.clear();
          for (var item in history) {
            _messages.add(
              ChatMessage(
                role: item['role'] ?? 'assistant',
                content: item['content'] ?? '',
                isDiagnostic: item['isDiagnostic'] == true,
                timestamp: DateTime.tryParse(item['timestamp'] ?? '') ?? DateTime.now(),
              ),
            );
          }
        });
        _scrollToBottom();
      } else {
        final astroName = _astrologer?['name'] ?? 'Senior Astrologer';
        final specialty = _astrologer?['specialty'] ?? 'Vedic Astrology Specialist';

        setState(() {
          _messages.add(
            ChatMessage(
              role: 'assistant',
              content: 'Namaste! I am $astroName, your $specialty advisor. I have opened your Janam Kundli chart. How may I guide your life path today?',
              timestamp: DateTime.now(),
            ),
          );
        });
      }
    }
  }

  Future<void> _sendMessage() async {
    final text = _messageController.text.trim();
    if (text.isEmpty || _isLoading) return;

    _messageController.clear();
    setState(() {
      _messages.add(ChatMessage(
        role: 'user',
        content: text,
        timestamp: DateTime.now(),
      ));
      _isLoading = true;
    });

    _scrollToBottom();

    final backendService = Provider.of<BackendService>(context, listen: false);
    final response = await backendService.sendChatMessage(
      text,
      astrologerName: _astrologer?['name'],
      specialty: _astrologer?['specialty'],
      field: _astrologer?['field'],
    );

    if (mounted) {
      setState(() {
        _messages.add(ChatMessage(
          role: 'assistant',
          content: response,
          isDiagnostic: response.contains('?') && response.length < 250,
          timestamp: DateTime.now(),
        ));
        _isLoading = false;
      });
      _scrollToBottom();
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  void dispose() {
    _typingAnimationController.dispose();
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final astroName = _astrologer?['name'] ?? 'Senior Astrologer';
    final specialty = _astrologer?['specialty'] ?? 'Vedic Advisor';
    final Color avatarBg = _astrologer?['avatarBg'] ?? const Color(0xFFE83D66);
    final String imageUrl = _astrologer?['imageUrl'] ?? '';

    return Scaffold(
      backgroundColor: const Color(0xFFFCF7F1),
      appBar: AppBar(
        backgroundColor: const Color(0xFFFCF7F1),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, color: Colors.black, size: 20),
          onPressed: () => Navigator.pop(context),
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
                            errorBuilder: (context, error, stackTrace) => Center(
                              child: Text(
                                astroName[0].toUpperCase(),
                                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                              ),
                            ),
                          )
                        : Center(
                            child: Text(
                              astroName[0].toUpperCase(),
                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                            ),
                          ),
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
                children: [
                  Text(
                    astroName,
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.black),
                    overflow: TextOverflow.ellipsis,
                  ),
                  Row(
                    children: [
                      Text(
                        _isLoading ? 'typing...' : specialty,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: _isLoading ? FontWeight.bold : FontWeight.w500,
                          color: _isLoading ? const Color(0xFFE83D66) : Colors.grey.shade600,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          Container(
            margin: const EdgeInsets.only(right: 16),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xFF4CAF50).withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFF4CAF50).withValues(alpha: 0.3)),
            ),
            child: Row(
              children: const [
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
                  ),
                ),
              ],
            ),
          ),

          // Messages List
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.all(16),
              itemCount: _messages.length + (_isLoading ? 1 : 0),
              itemBuilder: (context, index) {
                // Render Astrologer Typing Bubble when loading
                if (index == _messages.length && _isLoading) {
                  return _buildAstrologerTypingBubble(astroName, avatarBg, imageUrl);
                }

                final msg = _messages[index];
                final isUser = msg.role == 'user';

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
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: const [
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
                        margin: const EdgeInsets.only(bottom: 12),
                        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.82),
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        decoration: BoxDecoration(
                          color: isUser ? const Color(0xFF1E1A17) : Colors.white,
                          borderRadius: BorderRadius.only(
                            topLeft: const Radius.circular(18),
                            topRight: const Radius.circular(18),
                            bottomLeft: Radius.circular(isUser ? 18 : 4),
                            bottomRight: Radius.circular(isUser ? 4 : 18),
                          ),
                          border: Border.all(
                            color: msg.isDiagnostic ? const Color(0xFFFFB74D) : Colors.transparent,
                            width: msg.isDiagnostic ? 1.5 : 0,
                          ),
                          boxShadow: [
                            if (!isUser)
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.04),
                                blurRadius: 8,
                                offset: const Offset(0, 2),
                              ),
                          ],
                        ),
                        child: Text(
                          msg.content,
                          style: TextStyle(
                            fontSize: 14,
                            color: isUser ? Colors.white : Colors.black87,
                            height: 1.4,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),

          // Message Input Field
          SafeArea(
            child: Container(
              padding: const EdgeInsets.all(12),
              color: Colors.white,
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _messageController,
                      style: const TextStyle(fontSize: 15),
                      decoration: InputDecoration(
                        hintText: 'Type your message to $astroName...',
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
                  GestureDetector(
                    onTap: _sendMessage,
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: const BoxDecoration(
                        color: Color(0xFFE83D66),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.send_rounded, color: Colors.white, size: 20),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Realistic Astrologer Typing Bubble Widget
  Widget _buildAstrologerTypingBubble(String name, Color avatarBg, String imageUrl) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
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
            Text(
              '$name is typing',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Colors.grey.shade700,
              ),
            ),
            const SizedBox(width: 8),
            AnimatedBuilder(
              animation: _typingAnimationController,
              builder: (context, child) {
                final value = _typingAnimationController.value;
                return Row(
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
