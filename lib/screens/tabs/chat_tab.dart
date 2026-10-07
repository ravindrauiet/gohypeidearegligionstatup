import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../services/backend_service.dart';
import '../consultation_lobby_screen.dart';
import '../seeker_session_chat_screen.dart';
import '../wallet_screen.dart';

class ChatTab extends StatefulWidget {
  const ChatTab({super.key});

  @override
  State<ChatTab> createState() => _ChatTabState();
}

class _ChatTabState extends State<ChatTab> {
  int _selectedFilterIndex = 0;

  static const List<String> _categories = [
    'Love & Relationships',
    'Career & Wealth',
    'Vedic Kundli',
    '24/7 Guidance',
  ];

  // Live human pandits (from /pandit/list) — separate from the free AI personas below.
  List<Map<String, dynamic>> _livePandits = [];
  bool _isLoadingPandits = true;
  bool _panditsLoadFailed = false;
  String? _panditsError;
  String? _requestingPanditId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadLivePandits());
  }

  Future<void> _loadLivePandits() async {
    if (!mounted) return;
    setState(() {
      _isLoadingPandits = true;
      _panditsLoadFailed = false;
    });
    final backendService = Provider.of<BackendService>(context, listen: false);
    List<Map<String, dynamic>> list = const [];
    String? error;
    try {
      // Throws BackendException on failure; an empty list is a valid result.
      list = await backendService.fetchPanditsList();
    } on BackendException catch (e) {
      error = e.message;
    } catch (_) {
      error = 'Could not load live pandits.';
    }
    if (!mounted) return;
    setState(() {
      if (error == null) _livePandits = list;
      _isLoadingPandits = false;
      _panditsLoadFailed = error != null;
      _panditsError = error;
    });
  }

  static double _toDouble(dynamic v, double fallback) {
    if (v is num) return v.toDouble();
    return double.tryParse(v?.toString() ?? '') ?? fallback;
  }

  final List<Map<String, dynamic>> _astrologers = [
    {
      'id': '1',
      'name': 'Rishi & Olivia',
      'specialty': 'Love & Relationship Compatibility',
      'field': 'Love & Relationships',
      'rating': '4.9',
      'reviews': '1,840',
      'experience': '15 yrs exp',
      'avatarBg': const Color(0xFFE83D66),
      'imageUrl': 'https://images.unsplash.com/photo-1534528741775-53994a69daeb?auto=format&fit=crop&w=300&q=80',
      'bio': 'Specialist in Kundli matching, soulmate connections & love transits.',
      'isOnline': true,
    },
    {
      'id': '2',
      'name': 'Acharya Dev Sharma',
      'specialty': 'Career & Financial Wealth',
      'field': 'Career & Wealth',
      'rating': '4.9',
      'reviews': '2,150',
      'experience': '18 yrs exp',
      'avatarBg': const Color(0xFFD95D39),
      'imageUrl': 'https://images.unsplash.com/photo-1507003211169-0a1dd7228f2d?auto=format&fit=crop&w=300&q=80',
      'bio': '10th House & D10 Dasamsha expert for job promotions, business & investments.',
      'isOnline': true,
    },
    {
      'id': '3',
      'name': 'Dr. Ananya Roy',
      'specialty': 'Love & Marriage Remedies',
      'field': 'Love & Relationships',
      'rating': '4.8',
      'reviews': '1,290',
      'experience': '12 yrs exp',
      'avatarBg': const Color(0xFF7C77E6),
      'imageUrl': 'https://images.unsplash.com/photo-1573496359142-b8d87734a5a2?auto=format&fit=crop&w=300&q=80',
      'bio': 'Specialist in D9 Navamsha chart readings and romantic relationship alignment.',
      'isOnline': true,
    },
    {
      'id': '4',
      'name': 'Pandit Shastri',
      'specialty': 'Vedic Birth Chart & Kundli',
      'field': 'Vedic Kundli',
      'rating': '5.0',
      'reviews': '3,420',
      'experience': '22 yrs exp',
      'avatarBg': const Color(0xFFFFB74D),
      'imageUrl': 'https://images.unsplash.com/photo-1500648767791-00dcc994a43e?auto=format&fit=crop&w=300&q=80',
      'bio': 'Master in Janam Kundli, Lagna calculations, and Guna Milan analysis.',
      'isOnline': true,
    },
    {
      'id': '5',
      'name': 'Astro Maya',
      'specialty': '24/7 Life & Spiritual Guidance',
      'field': '24/7 Guidance',
      'rating': '4.9',
      'reviews': '1,950',
      'experience': '10 yrs exp',
      'avatarBg': const Color(0xFF4CAF50),
      'imageUrl': 'https://images.unsplash.com/photo-1544005313-94ddf0286df2?auto=format&fit=crop&w=300&q=80',
      'bio': 'Intuitive Tarot & Vedic astrologer for daily decision making & peace of mind.',
      'isOnline': true,
    },
    {
      'id': '6',
      'name': 'Guru Varma',
      'specialty': 'Career, Job Switch & Overseas Visas',
      'field': 'Career & Wealth',
      'rating': '4.8',
      'reviews': '1,480',
      'experience': '16 yrs exp',
      'avatarBg': const Color(0xFF3F51B5),
      'imageUrl': 'https://images.unsplash.com/photo-1472099645785-5658abf4ff4e?auto=format&fit=crop&w=300&q=80',
      'bio': 'Guidance for job switches, foreign relocation, visas & promotions.',
      'isOnline': true,
    },
    {
      'id': '7',
      'name': 'Tarun Shastri',
      'specialty': 'Vimshottari Dasha & Remedies',
      'field': 'Vedic Kundli',
      'rating': '4.9',
      'reviews': '1,620',
      'experience': '14 yrs exp',
      'avatarBg': const Color(0xFF9C27B0),
      'imageUrl': 'https://images.unsplash.com/photo-1519085360753-af0119f7cbe7?auto=format&fit=crop&w=300&q=80',
      'bio': 'Specialist in Rahu-Ketu remedies, gemstone selection & Sade Sati relief.',
      'isOnline': true,
    },
    {
      'id': '8',
      'name': 'Rishi Anand',
      'specialty': 'Instant 24/7 AI Astrologer Assistant',
      'field': '24/7 Guidance',
      'rating': '5.0',
      'reviews': '4,900',
      'experience': 'Instant AI',
      'avatarBg': const Color(0xFFE83D66),
      'imageUrl': 'https://images.unsplash.com/photo-1535713875002-d1d0cf377fde?auto=format&fit=crop&w=300&q=80',
      'bio': 'Instant 24/7 personalized answers using your saved Neon DB birth chart.',
      'isOnline': true,
    },
    {
      'id': '9',
      'name': 'Maura Meridian',
      'specialty': 'Astrocartography & Relocation',
      'field': '24/7 Guidance',
      'rating': '4.8',
      'reviews': '890',
      'experience': '11 yrs exp',
      'avatarBg': const Color(0xFF00BCD4),
      'imageUrl': 'https://images.unsplash.com/photo-1580489944761-15a19d654956?auto=format&fit=crop&w=300&q=80',
      'bio': 'Global relocation lines, planet MC/ASC aspects, and travel astrology.',
      'isOnline': true,
    },
    {
      'id': '10',
      'name': 'Siddharth Vedic Master',
      'specialty': 'Manglik & Kaal Sarp Dosha',
      'field': 'Vedic Kundli',
      'rating': '4.9',
      'reviews': '2,730',
      'experience': '20 yrs exp',
      'avatarBg': const Color(0xFF795548),
      'imageUrl': 'https://images.unsplash.com/photo-1506794778202-cad84cf45f1d?auto=format&fit=crop&w=300&q=80',
      'bio': 'Expert in resolving Manglik dosha, family harmony, and planetary pujas.',
      'isOnline': true,
    },
  ];

  List<String> get _filters => [
        'All (${_astrologers.length})',
        ..._categories.map((c) => '$c (${_astrologers.where((a) => a['field'] == c).length})'),
      ];

  @override
  Widget build(BuildContext context) {
    final filteredList = _selectedFilterIndex == 0
        ? _astrologers
        : _astrologers.where((a) => a['field'] == _categories[_selectedFilterIndex - 1]).toList();
    final filters = _filters;

    return Scaffold(
      backgroundColor: const Color(0xFFFCF7F1),
      appBar: AppBar(
        backgroundColor: const Color(0xFFFCF7F1),
        elevation: 0,
        automaticallyImplyLeading: false,
        titleSpacing: 16,
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey.shade300),
              ),
              child: const Icon(Icons.forum_rounded, color: Color(0xFF7C77E6), size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Expert Astrologers',
                    style: TextStyle(color: Colors.grey, fontSize: 12, fontWeight: FontWeight.w500),
                  ),
                  Text(
                    '${_astrologers.length} Specialized Advisors',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.black.withValues(alpha: 0.9),
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: const Color(0xFF6B1A3A),
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.auto_awesome_rounded, color: Colors.white, size: 14),
                  SizedBox(width: 4),
                  Text(
                    'AI FREE',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 16),
        ],
      ),
      body: Column(
        children: [
          const SizedBox(height: 8),

          // 1. Horizontal Category Filter Chips
          SizedBox(
            height: 42,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: filters.length,
              itemBuilder: (context, index) {
                final isSelected = _selectedFilterIndex == index;
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Material(
                    color: isSelected ? const Color(0xFF1E1A17) : Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                      side: BorderSide(color: isSelected ? Colors.transparent : Colors.grey.shade300),
                    ),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(14),
                      onTap: () => setState(() => _selectedFilterIndex = index),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                        child: Text(
                          filters[index],
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                            color: isSelected ? Colors.white : Colors.black87,
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),

          const SizedBox(height: 14),

          // 2. Live pandits strip + AI astrologer cards
          Expanded(
            child: RefreshIndicator(
              onRefresh: _loadLivePandits,
              color: const Color(0xFFE83D66),
              child: ListView.builder(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                itemCount: filteredList.length + 1,
                itemBuilder: (context, index) {
                  if (index == 0) return _buildLivePanditsSection();
                  return _buildAstrologerCard(context, filteredList[index - 1]);
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Live human Pandit consultations (paid, queue based)
  Widget _buildLivePanditsSection() {
    Widget body;
    if (_isLoadingPandits) {
      body = const SizedBox(
        height: 96,
        child: Center(child: CircularProgressIndicator(color: Color(0xFFE83D66))),
      );
    } else if (_panditsLoadFailed) {
      body = Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.grey.shade200),
        ),
        child: Row(
          children: [
            const Icon(Icons.wifi_off_rounded, color: Colors.grey),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                _panditsError ?? 'Could not load live pandits.',
                style: const TextStyle(fontSize: 13, color: Colors.black87),
              ),
            ),
            TextButton(onPressed: _loadLivePandits, child: const Text('Retry')),
          ],
        ),
      );
    } else if (_livePandits.isEmpty) {
      body = Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.grey.shade200),
        ),
        child: const Text(
          'No live pandits are registered right now. Pull down to refresh.',
          style: TextStyle(fontSize: 13, color: Colors.black54),
        ),
      );
    } else {
      body = SizedBox(
        height: 112,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: _livePandits.length,
          separatorBuilder: (_, __) => const SizedBox(width: 10),
          itemBuilder: (context, index) => _buildLivePanditChip(_livePandits[index]),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.circle, color: Color(0xFF4CAF50), size: 10),
              SizedBox(width: 6),
              Expanded(
                child: Text(
                  'LIVE PANDIT CONSULTATIONS',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Colors.grey, letterSpacing: 1.1),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          body,
          const SizedBox(height: 16),
          const Text(
            'AI ASTROLOGERS · FREE 24/7',
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Colors.grey, letterSpacing: 1.1),
          ),
        ],
      ),
    );
  }

  Widget _buildLivePanditChip(Map<String, dynamic> pandit) {
    final id = pandit['id']?.toString() ?? '';
    final name = pandit['full_name']?.toString() ?? pandit['fullName']?.toString() ?? 'Pandit';
    final specialty = pandit['specialty']?.toString() ?? 'Vedic Astrology';
    final rate = _toDouble(pandit['rate_per_min'] ?? pandit['ratePerMin'], 21);
    final isOnline = pandit['is_online'] == true || pandit['isOnline'] == true;
    final isBusy = pandit['is_busy'] == true || pandit['isBusy'] == true;
    final waiting = int.tryParse(pandit['waiting_count']?.toString() ?? '') ?? 0;
    final avatarUrl = pandit['avatar_url']?.toString() ?? pandit['avatarUrl']?.toString() ?? '';
    final isRequesting = _requestingPanditId == id;

    final String statusText = !isOnline ? 'Offline' : (isBusy ? 'Busy · $waiting waiting' : 'Available');
    final Color statusColor = !isOnline ? Colors.grey : (isBusy ? const Color(0xFFD97706) : const Color(0xFF059669));

    return SizedBox(
      width: 232,
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: (!isOnline || _requestingPanditId != null) ? null : () => _startLiveConsultation(pandit),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.grey.shade200),
            ),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 24,
                  backgroundColor: const Color(0xFFE83D66).withValues(alpha: 0.15),
                  foregroundImage: avatarUrl.isNotEmpty ? NetworkImage(avatarUrl) : null,
                  onForegroundImageError: avatarUrl.isNotEmpty ? (_, __) {} : null,
                  child: Text(
                    name.isNotEmpty ? name[0].toUpperCase() : 'P',
                    style: const TextStyle(color: Color(0xFFE83D66), fontWeight: FontWeight.bold),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                      Text(specialty,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 11, color: Colors.grey.shade700)),
                      const SizedBox(height: 4),
                      Text('₹${rate.toStringAsFixed(0)}/min',
                          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.black87)),
                      Text(statusText,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: statusColor)),
                    ],
                  ),
                ),
                if (isRequesting)
                  const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFFE83D66)),
                  )
                else
                  Icon(Icons.arrow_forward_ios_rounded, size: 12, color: isOnline ? Colors.black54 : Colors.grey.shade300),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAstrologerCard(BuildContext context, Map<String, dynamic> astro) {
    final dynamic rawBg = astro['avatarBg'];
    final Color avatarBg = rawBg is Color ? rawBg : const Color(0xFF7C77E6);
    final String imageUrl = astro['imageUrl']?.toString() ?? '';
    final String name = astro['name']?.toString() ?? 'Astrologer';
    final String initial = name.isNotEmpty ? name[0].toUpperCase() : 'A';

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Astrologer Image Avatar Circle with Online Badge
              Stack(
                children: [
                  Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      color: avatarBg,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 2),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.08),
                          blurRadius: 6,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(32),
                      child: imageUrl.isEmpty
                          ? _buildInitial(initial)
                          : Image.network(
                              imageUrl,
                              fit: BoxFit.cover,
                              width: 64,
                              height: 64,
                              errorBuilder: (context, error, stackTrace) => _buildInitial(initial),
                            ),
                    ),
                  ),
                  Positioned(
                    right: 2,
                    bottom: 2,
                    child: Container(
                      width: 14,
                      height: 14,
                      decoration: BoxDecoration(
                        color: const Color(0xFF4CAF50),
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2),
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(width: 14),

              // Astrologer Details
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            name,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                              color: Colors.black,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFCF7F1),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.grey.shade300),
                          ),
                          child: Text(
                            astro['experience']?.toString() ?? '',
                            style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.black87),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      astro['specialty']?.toString() ?? '',
                      style: const TextStyle(
                        fontSize: 13,
                        color: Color(0xFFD95D39),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        const Icon(Icons.star_rounded, color: Color(0xFFFFC107), size: 16),
                        const SizedBox(width: 4),
                        Flexible(
                          child: Text(
                            "${astro['rating']} (${astro['reviews']} chats)",
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: Colors.black87,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 12),

          // Bio / Specialization Tagline
          Text(
            astro['bio']?.toString() ?? '',
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey.shade700,
              height: 1.35,
            ),
          ),

          const SizedBox(height: 14),

          // Action Chat Now Button
          SizedBox(
            width: double.infinity,
            height: 44,
            child: ElevatedButton.icon(
              onPressed: () => Navigator.pushNamed(context, '/chatbot', arguments: astro),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFE83D66),
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              icon: const Icon(Icons.chat_bubble_outline_rounded, size: 18),
              label: Text(
                'Chat with ${name.split(' ').first}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInitial(String initial) {
    return Center(
      child: Text(
        initial,
        style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold),
      ),
    );
  }

  /// Requests a live consultation with a real registered pandit: either starts an
  /// active session immediately or places the seeker in the waiting-queue lobby.
  Future<void> _startLiveConsultation(Map<String, dynamic> pandit) async {
    if (_requestingPanditId != null) return;
    final id = pandit['id'];
    final idStr = id?.toString() ?? '';
    final name = pandit['full_name']?.toString() ?? pandit['fullName']?.toString() ?? 'Pandit';
    final specialty = pandit['specialty']?.toString() ?? 'Vedic Advisor';
    final avatarUrl = pandit['avatar_url']?.toString() ?? '';
    final rate = _toDouble(pandit['rate_per_min'] ?? pandit['ratePerMin'], 21);

    setState(() => _requestingPanditId = idStr);
    final backendService = Provider.of<BackendService>(context, listen: false);
    Map<String, dynamic>? result;
    try {
      result = await backendService.requestConsultation(panditId: id);
    } catch (e) {
      result = null;
    }
    if (!mounted) return;
    setState(() => _requestingPanditId = null);

    final error = result?['error']?.toString();
    final status = result?['status'];

    if (result == null || error != null) {
      if (error == 'INSUFFICIENT_BALANCE') {
        await _showInsufficientBalanceDialog(result!, name);
        return;
      }
      final message = (result?['message'] ?? backendService.lastError ?? 'Could not connect to $name. Please try again.').toString();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          action: error == 'PANDIT_OFFLINE' || error == 'SELF_CONSULTATION'
              ? null
              : SnackBarAction(label: 'Retry', onPressed: () => _startLiveConsultation(pandit)),
        ),
      );
      if (error == 'PANDIT_OFFLINE') _loadLivePandits();
      return;
    }

    if (status == 'active' && result['aiAstrologer'] == true) {
      // Not a registered human Pandit: served by the AI astrologer (free).
      Navigator.pushNamed(context, '/chatbot', arguments: <String, dynamic>{
        'id': id,
        'name': name,
        'specialty': specialty,
        'field': pandit['field'],
        'imageUrl': avatarUrl,
        'ratePerMin': rate,
      });
    } else if (status == 'active') {
      final session = result['session'];
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Connected to $name!'),
          backgroundColor: const Color(0xFF059669),
        ),
      );
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => SeekerSessionChatScreen(
            session: session is Map ? Map<String, dynamic>.from(session) : const <String, dynamic>{},
            panditName: name,
            specialty: specialty,
            avatarUrl: avatarUrl,
            ratePerMin: rate,
          ),
        ),
      );
      if (mounted) _loadLivePandits();
    } else if (status == 'waiting') {
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => ConsultationLobbyScreen(
            initialQueueData: {
              ...?result,
              'panditName': name,
              'specialty': specialty,
              'avatarUrl': avatarUrl,
              'ratePerMin': rate,
            },
          ),
        ),
      );
      if (mounted) _loadLivePandits();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not connect to $name. Please try again.'),
          action: SnackBarAction(label: 'Retry', onPressed: () => _startLiveConsultation(pandit)),
        ),
      );
    }
  }

  Future<void> _showInsufficientBalanceDialog(Map<String, dynamic> result, String panditName) async {
    final balance = _toDouble(result['walletBalance'], 0);
    final rate = _toDouble(result['ratePerMin'], 0);
    final openWallet = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Low wallet balance'),
        content: Text(
          (result['message'] ??
                  'Your wallet balance (₹${balance.toStringAsFixed(2)}) is below $panditName\'s rate '
                      '(₹${rate.toStringAsFixed(2)}/min). Please recharge to start the consultation.')
              .toString(),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Not now')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFE83D66)),
            child: const Text('Recharge Wallet', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (openWallet != true || !mounted) return;
    Navigator.push(context, MaterialPageRoute(builder: (_) => const WalletScreen()));
  }
}
