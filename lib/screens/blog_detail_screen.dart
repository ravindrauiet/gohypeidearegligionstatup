import 'package:flutter/material.dart';

class BlogDetailScreen extends StatelessWidget {
  final String blogId;

  const BlogDetailScreen({super.key, required this.blogId});

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
        title: const Text('Astrology Article', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(color: const Color(0xFFFFF7ED), borderRadius: BorderRadius.circular(12)),
              child: const Text('Vedic Astrology', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFFFB9548))),
            ),
            const SizedBox(height: 12),
            const Text(
              'Understanding Your Lagna (Ascendant) in Vedic Astrology',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.black, height: 1.3),
            ),
            const SizedBox(height: 8),
            Text('Published on Aug 25, 2026 • 5 min read', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
            const SizedBox(height: 20),
            Text(
              'In Vedic Astrology (Jyotish), the Ascendant or Lagna is the sign rising on the eastern horizon at the exact time of your birth. It determines your physical structure, core personality, and life approach.\n\nWhile Western astrology places primary emphasis on the Sun Sign, Vedic astrology regards Lagna and Moon Sign as the foundational pillars of horoscope analysis.\n\nKey Insights:\n1. 1st House: Health, vitality, self-expression.\n2. Ascendant Lord: Planet governing your life path.\n3. Nakshatra of Lagna: Deep subtle personality motivations.',
              style: TextStyle(fontSize: 14, color: Colors.grey.shade800, height: 1.6),
            ),
          ],
        ),
      ),
    );
  }
}
