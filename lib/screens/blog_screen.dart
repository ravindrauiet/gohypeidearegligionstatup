import 'package:flutter/material.dart';
import '../models/blog_model.dart';
import 'blog_detail_screen.dart';

/// Built-in CosmicGuide articles (shared with [BlogDetailScreen]).
final List<BlogModel> kCosmicGuideArticles = [
  BlogModel(
    id: '1',
    title: 'Understanding Your Lagna (Ascendant) in Vedic Astrology',
    category: 'Vedic Astrology',
    author: 'CosmicGuide Editorial',
    publishedAt: '2026-08-25',
    readTime: '5 min read',
    excerpt: 'Your Lagna represents your physical body, character traits and overall life path in Vedic Astrology.',
    content: 'In Vedic Astrology (Jyotish), the Ascendant or Lagna is the zodiac sign rising on the eastern horizon at the exact moment of your birth. '
        'Because the rising sign changes roughly every two hours, an accurate birth time is essential for finding it.\n\n'
        'While Western astrology emphasises the Sun sign, Vedic astrology treats the Lagna and the Moon sign as the foundations of chart analysis. '
        'The Lagna becomes the 1st house, and every other house is counted from it.\n\n'
        'Key points to study:\n'
        '1. The 1st house – health, vitality, appearance and self-expression.\n'
        '2. The Lagna lord – the planet ruling your rising sign, and the house it occupies, shows where your life energy flows.\n'
        '3. Planets in the 1st house – they colour your personality strongly.\n'
        '4. The Nakshatra of the Lagna – reveals subtler motivations and temperament.\n\n'
        'Tip: Open "My Kundli Chart" in CosmicGuide to see your Lagna, its lord and the planets placed in your first house.',
  ),
  BlogModel(
    id: '2',
    title: 'How Mahadashas Influence Key Cycles of Your Life',
    category: 'Planetary Dashas',
    author: 'CosmicGuide Editorial',
    publishedAt: '2026-08-20',
    readTime: '7 min read',
    excerpt: 'Learn how major planetary periods shape career opportunities, marriage timing and spiritual growth.',
    content: 'The Vimshottari Dasha system divides a 120-year life cycle into periods ruled by the nine grahas. '
        'Your starting Dasha is determined by the Nakshatra the Moon occupied at your birth.\n\n'
        'Each Mahadasha (major period) is divided into Antardashas (sub-periods). Results depend on:\n'
        '1. The house the Dasha lord rules and occupies in your chart.\n'
        '2. Its strength – sign dignity, aspects and conjunctions.\n'
        '3. Its relationship with your Lagna lord.\n\n'
        'For example, a well-placed Jupiter Mahadasha often brings growth through learning, children and mentors, '
        'while a Saturn period rewards discipline and patient effort, even if progress feels slow.\n\n'
        'Dashas describe tendencies and timing – not fixed outcomes. Conscious effort, remedies and good choices matter in every period.',
  ),
  BlogModel(
    id: '3',
    title: 'Why Your Moon Sign (Rasi) Matters More Than Your Sun Sign',
    category: 'Horoscope',
    author: 'CosmicGuide Editorial',
    publishedAt: '2026-08-15',
    readTime: '4 min read',
    excerpt: 'Discover why Indian astrology prioritises the Moon sign for emotional wellbeing and daily predictions.',
    content: 'In Jyotish, the Moon represents the mind (manas) – your emotions, instincts and sense of comfort. '
        'Since the Moon moves through a sign in about two and a half days, it is a far more personal marker than the Sun, which stays in a sign for a month.\n\n'
        'That is why Vedic daily horoscopes, Gochar (transit) readings and Sade Sati are all calculated from your Moon sign (Rasi).\n\n'
        'Your Janma Nakshatra – the lunar mansion of the Moon at birth – also determines your Dasha sequence and is used in Guna Milan for marriage compatibility.\n\n'
        'Tip: Your Moon sign and Nakshatra appear on your CosmicGuide profile once your birth details are added.',
  ),
];

class BlogScreen extends StatelessWidget {
  const BlogScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFCF7F1),
      appBar: AppBar(
        backgroundColor: const Color(0xFFFCF7F1),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, color: Colors.black),
          tooltip: 'Back',
          onPressed: () => Navigator.maybePop(context),
        ),
        title: const Text('Articles & Insights', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
        centerTitle: true,
      ),
      body: kCosmicGuideArticles.isEmpty
          ? const Center(child: Text('No articles yet. Check back soon.', style: TextStyle(color: Colors.grey)))
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: kCosmicGuideArticles.length,
              itemBuilder: (context, index) {
                final blog = kCosmicGuideArticles[index];
                return Container(
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 10, offset: const Offset(0, 4)),
                    ],
                  ),
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(20),
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => BlogDetailScreen(blogId: blog.id)),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if ((blog.category ?? '').isNotEmpty)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(color: const Color(0xFFFFF7ED), borderRadius: BorderRadius.circular(12)),
                                child: Text(blog.category!,
                                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFFFB9548))),
                              ),
                            const SizedBox(height: 10),
                            Text(blog.title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.black)),
                            const SizedBox(height: 6),
                            Text(blog.excerpt ?? '', style: TextStyle(fontSize: 13, color: Colors.grey.shade700, height: 1.4)),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    [blog.author, blog.readTime].whereType<String>().join(' • '),
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                                  ),
                                ),
                                const Icon(Icons.arrow_forward_ios, size: 14, color: Colors.black),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
    );
  }
}
