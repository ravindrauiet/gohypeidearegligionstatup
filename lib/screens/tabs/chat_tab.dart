import 'package:flutter/material.dart';

class ChatTab extends StatefulWidget {
  const ChatTab({super.key});

  @override
  State<ChatTab> createState() => _ChatTabState();
}

class _ChatTabState extends State<ChatTab> {
  int _selectedFilterIndex = 0;

  final List<String> _filters = [
    'All',
    'Western Astrologer',
    'Vedic Astrologer',
    'Astrocartography Expert',
    'AI Astrologer'
  ];

  final List<Map<String, dynamic>> _astrologers = [
    {
      'name': 'Mira Solis',
      'specialty': 'Western Astrologer',
      'rating': '4.8',
      'reviews': '982',
      'avatarBg': const Color(0xFF4A3525),
      'imageUrl': 'https://images.unsplash.com/photo-1544005313-94ddf0286df2?auto=format&fit=crop&w=300&q=80',
    },
    {
      'name': 'Pt. Rishiraj Tiwari',
      'specialty': 'Vedic Astrologer',
      'rating': '4.8',
      'reviews': '769',
      'avatarBg': const Color(0xFFD95D39),
      'imageUrl': 'https://images.unsplash.com/photo-1507003211169-0a1dd7228f2d?auto=format&fit=crop&w=300&q=80',
    },
    {
      'name': 'Elena Meridian',
      'specialty': 'Astrocartography Expert',
      'rating': '4.9',
      'reviews': '540',
      'avatarBg': const Color(0xFF7C77E6),
      'imageUrl': 'https://images.unsplash.com/photo-1573496359142-b8d87734a5a2?auto=format&fit=crop&w=300&q=80',
    },
    {
      'name': 'AstroAI Kundli Assistant',
      'specialty': 'Instant 24/7 Vedic & Western AI',
      'rating': '5.0',
      'reviews': '2,450',
      'avatarBg': const Color(0xFFE83D66),
      'isAI': true,
    },
  ];

  @override
  Widget build(BuildContext context) {
    final filteredList = _selectedFilterIndex == 0
        ? _astrologers
        : _astrologers.where((a) => a['specialty'].toString().contains(_filters[_selectedFilterIndex]) || (_filters[_selectedFilterIndex] == 'AI Astrologer' && a['isAI'] == true)).toList();

    return Scaffold(
      backgroundColor: const Color(0xFFFCF7F1),
      appBar: AppBar(
        backgroundColor: const Color(0xFFFCF7F1),
        elevation: 0,
        automaticallyImplyLeading: false,
        titleSpacing: 16,
        leading: Container(
          margin: const EdgeInsets.only(left: 16, top: 8, bottom: 8),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.grey.shade300),
          ),
          child: IconButton(
            icon: const Icon(Icons.menu_rounded, color: Colors.black, size: 20),
            padding: EdgeInsets.zero,
            onPressed: () {},
          ),
        ),
        title: const Text(
          'Chat',
          style: TextStyle(
            color: Colors.black,
            fontSize: 24,
            fontWeight: FontWeight.w800,
          ),
        ),
        actions: [
          // Wallet pill badge ₹0
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: const Color(0xFF6B1A3A),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              children: const [
                Icon(Icons.shopping_bag_outlined, color: Colors.white, size: 16),
                SizedBox(width: 4),
                Text(
                  '₹0',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          // User Avatar Circle
          Container(
            margin: const EdgeInsets.only(right: 16),
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.grey.shade300),
            ),
            child: const Center(
              child: Text(
                'R',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.black),
              ),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          const SizedBox(height: 12),

          // 1. Horizontal Category Filter Chips (Matching Image 4)
          SizedBox(
            height: 40,
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
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
                    decoration: BoxDecoration(
                      color: isSelected ? const Color(0xFFECE4D9) : Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: isSelected ? Colors.transparent : Colors.grey.shade300,
                      ),
                    ),
                    child: Text(
                      _filters[index],
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: isSelected ? FontWeight.w800 : FontWeight.w500,
                        color: Colors.black87,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),

          const SizedBox(height: 16),

          // 2. Astrologers Cards List (Matching Image 4)
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
    final bool isAI = astro['isAI'] == true;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        children: [
          // Astrologer Avatar Circle
          ClipRRect(
            borderRadius: BorderRadius.circular(40),
            child: Container(
              width: 75,
              height: 75,
              color: astro['avatarBg'] ?? Colors.grey.shade300,
              child: isAI
                  ? const Icon(Icons.auto_awesome_rounded, color: Colors.white, size: 36)
                  : Image.network(
                      astro['imageUrl'],
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) {
                        return Center(
                          child: Text(
                            astro['name'][0],
                            style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold),
                          ),
                        );
                      },
                    ),
            ),
          ),

          const SizedBox(width: 14),

          // Astrologer Info Details
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  astro['name'],
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    color: Colors.black,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  astro['specialty'],
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.grey.shade600,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Icon(Icons.star_rounded, color: Color(0xFFFFC107), size: 16),
                    const SizedBox(width: 4),
                    Text(
                      "${astro['rating']} (${astro['reviews']})",
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

          // Pink Chat Now Button (Matching Image 4)
          SizedBox(
            height: 42,
            child: ElevatedButton(
              onPressed: () {
                Navigator.pushNamed(context, '/chatbot');
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFE83D66),
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 16),
              ),
              child: const Text(
                'Chat Now',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
