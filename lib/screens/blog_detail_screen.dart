import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/blog_model.dart';
import 'blog_screen.dart';

class BlogDetailScreen extends StatelessWidget {
  final String blogId;

  const BlogDetailScreen({super.key, required this.blogId});

  @override
  Widget build(BuildContext context) {
    BlogModel? blog;
    for (final b in kCosmicGuideArticles) {
      if (b.id == blogId) {
        blog = b;
        break;
      }
    }

    final published = DateTime.tryParse(blog?.publishedAt?.toString() ?? '');
    final meta = [
      if (published != null) 'Published ${DateFormat('d MMM yyyy').format(published)}',
      if (blog?.readTime != null) blog!.readTime!,
    ].join(' • ');

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
        title: const Text('Article', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
        centerTitle: true,
      ),
      body: blog == null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.article_outlined, size: 52, color: Colors.grey.shade400),
                    const SizedBox(height: 12),
                    const Text('This article is no longer available.', style: TextStyle(color: Colors.grey)),
                    const SizedBox(height: 16),
                    ElevatedButton(onPressed: () => Navigator.maybePop(context), child: const Text('Go back')),
                  ],
                ),
              ),
            )
          : SafeArea(
              top: false,
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
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
                    const SizedBox(height: 12),
                    Text(
                      blog.title,
                      style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.black, height: 1.3),
                    ),
                    const SizedBox(height: 8),
                    if (blog.author != null)
                      Text('By ${blog.author}', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.black87)),
                    if (meta.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(meta, style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                    ],
                    const SizedBox(height: 20),
                    SelectableText(
                      blog.content ?? blog.excerpt ?? '',
                      style: TextStyle(fontSize: 15, color: Colors.grey.shade800, height: 1.6),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}
