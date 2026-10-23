import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/blog_model.dart';
import '../utils/app_routes.dart';
import '../widgets/ui/app_ui.dart';
import 'blog_screen.dart';

class BlogDetailScreen extends StatelessWidget {
  final String blogId;

  const BlogDetailScreen({super.key, required this.blogId});

  static const _bodyStyle = TextStyle(fontSize: 16, height: 1.6, color: AppColors.textPrimary);

  @override
  Widget build(BuildContext context) {
    BlogModel? blog;
    for (final b in kCosmicGuideArticles) {
      if (b.id == blogId) {
        blog = b;
        break;
      }
    }

    if (blog == null) {
      return Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(title: const Text('Article')),
        body: Center(
          child: AppStateView(
            icon: Icons.article_outlined,
            title: 'Article not available',
            message: 'This article may have been moved or removed.',
            actionLabel: 'Go back',
            onAction: () => Navigator.maybePop(context),
          ),
        ),
      );
    }

    final article = blog;
    final published = DateTime.tryParse(article.publishedAt?.toString() ?? '');
    final meta = [
      if (published != null) DateFormat('d MMM yyyy').format(published),
      if (article.readTime != null) article.readTime!,
    ].join(' · ');
    final more = kCosmicGuideArticles.where((b) => b.id != article.id).toList();

    return Scaffold(
      backgroundColor: AppColors.surface,
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            pinned: true,
            expandedHeight: 260,
            backgroundColor: AppColors.surface,
            leading: Padding(
              padding: const EdgeInsets.all(6),
              child: Material(
                color: AppColors.surface.withValues(alpha: 0.92),
                shape: const CircleBorder(),
                child: IconButton(
                  tooltip: 'Back',
                  icon: const Icon(Icons.arrow_back_rounded, color: AppColors.textPrimary, size: 20),
                  onPressed: () => Navigator.maybePop(context),
                ),
              ),
            ),
            flexibleSpace: FlexibleSpaceBar(
              background: AppImage(article.image ?? 'assets/images/astrology.jpg'),
            ),
          ),
          SliverToBoxAdapter(
            child: SelectionArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.lg, AppSpacing.lg, AppSpacing.md),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if ((article.category ?? '').isNotEmpty) ...[
                      Text(article.category!.toUpperCase(),
                          style: AppText.overline.copyWith(color: AppColors.primary)),
                      const SizedBox(height: AppSpacing.xs),
                    ],
                    Text(article.title, style: AppText.display.copyWith(fontSize: 26)),
                    const SizedBox(height: AppSpacing.md),
                    Row(
                      children: [
                        AppAvatar(name: article.author ?? 'CosmicGuide', size: 36, color: AppColors.primary),
                        const SizedBox(width: AppSpacing.sm),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(article.author ?? 'CosmicGuide', style: AppText.bodyStrong),
                              if (meta.isNotEmpty) Text(meta, style: AppText.caption),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    const Divider(),
                    const SizedBox(height: AppSpacing.lg),
                    ..._buildBody(article.content ?? article.excerpt ?? ''),
                  ],
                ),
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
              child: AppCard(
                gradient: AppColors.cosmicGradient,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('See this in your own chart', style: AppText.subtitle.copyWith(color: AppColors.textOnDark)),
                    const SizedBox(height: 4),
                    Text('Ask the AI astrologer how this applies to your Kundli.',
                        style: AppText.body.copyWith(color: AppColors.textOnDarkMuted)),
                    const SizedBox(height: AppSpacing.md),
                    AppButton(
                      label: 'Ask AI astrologer',
                      icon: Icons.auto_awesome_rounded,
                      height: 44,
                      onPressed: () => Navigator.pushNamed(context, AppRoutes.chatbot),
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (more.isNotEmpty) ...[
            const SliverToBoxAdapter(
              child: SectionHeader(
                title: 'More to read',
                padding: EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.xl, AppSpacing.lg, AppSpacing.sm),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(AppSpacing.lg, 0, AppSpacing.lg, AppSpacing.xxl),
              sliver: SliverList.separated(
                itemCount: more.length,
                separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.sm),
                itemBuilder: (context, i) => _RelatedTile(
                  blog: more[i],
                  onTap: () => Navigator.pushReplacement(
                    context,
                    MaterialPageRoute(builder: (_) => BlogDetailScreen(blogId: more[i].id)),
                  ),
                ),
              ),
            ),
          ] else
            const SliverToBoxAdapter(child: SizedBox(height: AppSpacing.xxl)),
        ],
      ),
    );
  }

  /// Splits plain-text content into readable paragraphs, list items and tips.
  List<Widget> _buildBody(String content) {
    final widgets = <Widget>[];
    for (final block in content.split(RegExp(r'\n\s*\n'))) {
      final text = block.trim();
      if (text.isEmpty) continue;
      if (text.startsWith('Tip:')) {
        widgets.add(Container(
          width: double.infinity,
          margin: const EdgeInsets.only(bottom: AppSpacing.lg),
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            color: AppColors.primarySoft,
            borderRadius: BorderRadius.circular(AppRadius.md),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.lightbulb_outline_rounded, color: AppColors.primaryDark, size: 20),
              const SizedBox(width: AppSpacing.sm),
              Expanded(child: Text(text.substring(4).trim(), style: _bodyStyle.copyWith(fontSize: 15))),
            ],
          ),
        ));
        continue;
      }
      final lines = text.split('\n');
      for (final raw in lines) {
        final line = raw.trim();
        if (line.isEmpty) continue;
        final m = RegExp(r'^(\d+)\.\s+(.*)$').firstMatch(line);
        if (m != null) {
          widgets.add(Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.xs, left: 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 24,
                  child: Text('${m.group(1)}.', style: _bodyStyle.copyWith(color: AppColors.primary, fontWeight: FontWeight.w700)),
                ),
                Expanded(child: Text(m.group(2)!, style: _bodyStyle)),
              ],
            ),
          ));
        } else {
          widgets.add(Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.xs),
            child: Text(line, style: _bodyStyle),
          ));
        }
      }
      widgets.add(const SizedBox(height: AppSpacing.sm));
    }
    return widgets;
  }
}

class _RelatedTile extends StatelessWidget {
  final BlogModel blog;
  final VoidCallback onTap;

  const _RelatedTile({required this.blog, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Article: ${blog.title}',
      excludeSemantics: true,
      child: AppCard(
        padding: const EdgeInsets.all(AppSpacing.sm),
        onTap: onTap,
        child: Row(
          children: [
            AppImage(
              blog.image ?? 'assets/images/astrology.jpg',
              width: 72,
              height: 72,
              radius: BorderRadius.circular(AppRadius.md),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(blog.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppText.bodyStrong),
                  if (blog.readTime != null) ...[
                    const SizedBox(height: 4),
                    Text(blog.readTime!, style: AppText.caption),
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
