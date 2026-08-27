import 'package:flutter/material.dart';

class BlogScreen extends StatefulWidget {
  const BlogScreen({super.key});

  @override
  State<BlogScreen> createState() => _BlogScreenState();
}

class _BlogScreenState extends State<BlogScreen> {
  final List<Map<String, dynamic>> _blogs = [
    {
      'id': '1',
      'title': 'Understanding Your Lagna (Ascendant) in Vedic Astrology',
      'category': 'Vedic Astrology',
      'author': 'Acharya Shastri',
      'date': '2026-08-25',
      'readTime': '5 min read',
      'summary': 'Your Lagna represents your physical body, character traits, and overall destiny path in Vedic Astrology.'
    },
    {
      'id': '2',
      'title': 'How Mahadashas Influence Key Cycles of Your Life',
      'category': 'Planetary Dashas',
      'author': 'Astro Guide',
      'date': '2026-08-20',
      'readTime': '7 min read',
      'summary': 'Learn how major planetary periods govern career opportunities, marriage timing, and spiritual growth.'
    },
    {
      'id': '3',
      'title': 'The Importance of Moon Sign (Rasi) vs Sun Sign',
      'category': 'Horoscope',
      'author': 'Dr. Cosmic',
      'date': '2026-08-15',
      'readTime': '4 min read',
      'summary': 'Discover why Indian astrology prioritizes the Moon sign for emotional wellness and daily predictions.'
    },
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFCF7F1),
      appBar: AppBar(
        backgroundColor: const Color(0xFFFCF7F1),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, color: Colors.black),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('Astrology Articles & Insights', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
        centerTitle: true,
      ),
      body: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _blogs.length,
        itemBuilder: (context, index) {
          final blog = _blogs[index];
          return Container(
            margin: const EdgeInsets.only(bottom: 16),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 10, offset: const Offset(0, 4)),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(color: const Color(0xFFFFF7ED), borderRadius: BorderRadius.circular(12)),
                  child: Text(blog['category'], style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFFFB9548))),
                ),
                const SizedBox(height: 10),
                Text(blog['title'], style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.black)),
                const SizedBox(height: 6),
                Text(blog['summary'], style: TextStyle(fontSize: 13, color: Colors.grey.shade700, height: 1.4)),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text("By ${blog['author']} • ${blog['readTime']}", style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
                    const Icon(Icons.arrow_forward_ios, size: 14, color: Colors.black),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}