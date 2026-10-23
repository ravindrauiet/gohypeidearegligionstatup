import 'package:flutter/material.dart';
import '../models/blog_model.dart';
import '../widgets/ui/app_ui.dart';
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
    image: 'assets/images/topic_birth_chart.jpg',
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
    image: 'assets/images/astrology.jpg',
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
    image: 'assets/images/topic_moon_calendar.jpg',
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

  void _open(BuildContext context, BlogModel blog) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => BlogDetailScreen(blogId: blog.id)));
  }

  @override
  Widget build(BuildContext context) {
    final articles = kCosmicGuideArticles;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Articles')),
      body: articles.isEmpty
          ? const Center(
              child: AppStateView(
                icon: Icons.menu_book_outlined,
                title: 'No articles yet',
                message: 'Fresh reads on Vedic astrology are on their way. Check back soon.',
              ),
            )
          : ListView.separated(
              padding: const EdgeInsets.fromLTRB(AppSpacing.page, AppSpacing.md, AppSpacing.page, AppSpacing.xl),
              itemCount: articles.length + 1,
              separatorBuilder: (_, i) => SizedBox(height: i == 0 ? AppSpacing.sm : AppSpacing.md),
              itemBuilder: (context, index) {
                if (index == 0) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 4),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Learn Jyotish', style: AppText.headline),
                        SizedBox(height: 4),
                        Text('Short, practical reads from the CosmicGuide editorial team.', style: AppText.body),
                      ],
                    ),
                  );
                }
                final blog = articles[index - 1];
                return BlogArticleCard(blog: blog, onTap: () => _open(context, blog));
              },
            ),
    );
  }
}

/// Magazine-style article card: cover image, category, title, excerpt, meta.
class BlogArticleCard extends StatelessWidget {
  final BlogModel blog;
  final VoidCallback onTap;

  const BlogArticleCard({super.key, required this.blog, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final meta = [blog.author, blog.readTime].whereType<String>().join(' · ');
    return Semantics(
      button: true,
      label: 'Article: ${blog.title}',
      child: AppCard(
        padding: EdgeInsets.zero,
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AspectRatio(
              aspectRatio: 16 / 9,
              child: AppImage(blog.image ?? 'assets/images/astrology.jpg'),
            ),
            Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if ((blog.category ?? '').isNotEmpty) ...[
                    Text(blog.category!.toUpperCase(), style: AppText.overline.copyWith(color: AppColors.primary)),
                    const SizedBox(height: 6),
                  ],
                  Text(blog.title, maxLines: 3, overflow: TextOverflow.ellipsis, style: AppText.title),
                  if ((blog.excerpt ?? '').isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(blog.excerpt!, maxLines: 3, overflow: TextOverflow.ellipsis, style: AppText.body),
                  ],
                  if (meta.isNotEmpty) ...[
                    const SizedBox(height: AppSpacing.sm),
                    Row(
                      children: [
                        const Icon(Icons.schedule_rounded, size: 14, color: AppColors.textTertiary),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(meta, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.caption),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
