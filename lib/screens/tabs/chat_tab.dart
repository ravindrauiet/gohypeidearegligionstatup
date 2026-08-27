import 'package:flutter/material.dart';

class ChatTab extends StatefulWidget {
  const ChatTab({super.key});

  @override
  State<ChatTab> createState() => _ChatTabState();
}

class _ChatTabState extends State<ChatTab> {
  int _selectedFilterIndex = 0;

  final List<String> _filters = [
    'All (10)',
    'Love & Relationships',
    'Career & Wealth',
    'Vedic Kundli',
    '24/7 Guidance'
  ];

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

  @override
  Widget build(BuildContext context) {
    final selectedFilter = _filters[_selectedFilterIndex];
    final filteredList = _selectedFilterIndex == 0
        ? _astrologers
        : _astrologers.where((a) => a['field'].toString().toLowerCase() == selectedFilter.toLowerCase() || a['specialty'].toString().toLowerCase().contains(selectedFilter.toLowerCase())).toList();

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
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Expert Astrologers',
                  style: TextStyle(color: Colors.grey, fontSize: 12, fontWeight: FontWeight.w500),
                ),
                Text(
                  '10 Specialized Advisors',
                  style: TextStyle(
                    color: Colors.black.withValues(alpha: 0.9),
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ],
        ),
        actions: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: const Color(0xFF6B1A3A),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              children: const [
                Icon(Icons.shopping_bag_outlined, color: Colors.white, size: 14),
                SizedBox(width: 4),
                Text(
                  'FREE',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
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
              itemCount: _filters.length,
              itemBuilder: (context, index) {
                final isSelected = _selectedFilterIndex == index;
                return GestureDetector(
                  onTap: () {
                    setState(() {
                      _selectedFilterIndex = index;
                    });
                  },
                  child: Container(
                    margin: const EdgeInsets.only(right: 8),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    decoration: BoxDecoration(
                      color: isSelected ? const Color(0xFF1E1A17) : Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: isSelected ? Colors.transparent : Colors.grey.shade300,
                      ),
                    ),
                    child: Text(
                      _filters[index],
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                        color: isSelected ? Colors.white : Colors.black87,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),

          const SizedBox(height: 14),

          // 2. Astrologers Cards List (10 Specialized Accounts with Images)
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              itemCount: filteredList.length,
              itemBuilder: (context, index) {
                final astro = filteredList[index];
                return _buildAstrologerCard(context, astro);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAstrologerCard(BuildContext context, Map<String, dynamic> astro) {
    final Color avatarBg = astro['avatarBg'] ?? const Color(0xFF7C77E6);
    final String imageUrl = astro['imageUrl'] ?? '';

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
                      child: Image.network(
                        imageUrl,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) {
                          return Center(
                            child: Text(
                              astro['name'][0].toUpperCase(),
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 24,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          );
                        },
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
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Flexible(
                          child: Text(
                            astro['name'],
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                              color: Colors.black,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFCF7F1),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.grey.shade300),
                          ),
                          child: Text(
                            astro['experience'],
                            style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.black87),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      astro['specialty'],
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
                        Text(
                          "${astro['rating']} (${astro['reviews']} chats)",
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: Colors.black87,
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
            astro['bio'],
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
            child: ElevatedButton(
              onPressed: () {
                Navigator.pushNamed(context, '/chatbot', arguments: astro);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFE83D66),
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.chat_bubble_outline_rounded, size: 18),
                  const SizedBox(width: 8),
                  Text(
                    'Chat with ${astro['name'].toString().split(' ')[0]}',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
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
}
