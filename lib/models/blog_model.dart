class BlogModel {
  final String id;
  final String title;
  final String? excerpt;
  final String? content;
  final String? author;
  final String? authorBio;
  final String? category;
  final String? image;
  final List<String>? tags;
  final List<Map<String, dynamic>>? sections;
  final String? readTime;
  final dynamic publishedAt;
  final dynamic createdAt;
  final dynamic updatedAt;
  final String status;

  BlogModel({
    required this.id,
    required this.title,
    this.excerpt,
    this.content,
    this.author,
    this.authorBio,
    this.category,
    this.image,
    this.tags,
    this.sections,
    this.readTime,
    this.publishedAt,
    this.createdAt,
    this.updatedAt,
    this.status = 'published',
  });

  factory BlogModel.fromMap(Map<String, dynamic> map) {
    return BlogModel(
      id: map['id'] ?? '',
      title: map['title'] ?? '',
      excerpt: map['excerpt'],
      content: map['content'],
      author: map['author'],
      authorBio: map['authorBio'],
      category: map['category'],
      image: map['image'],
      tags: map['tags'] != null ? List<String>.from(map['tags']) : null,
      sections: map['sections'] != null ? List<Map<String, dynamic>>.from(map['sections']) : null,
      readTime: map['readTime'],
      publishedAt: map['publishedAt'],
      createdAt: map['createdAt'],
      updatedAt: map['updatedAt'],
      status: map['status'] ?? 'published',
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title,
      'excerpt': excerpt,
      'content': content,
      'author': author,
      'authorBio': authorBio,
      'category': category,
      'image': image,
      'tags': tags,
      'sections': sections,
      'readTime': readTime,
      'publishedAt': publishedAt,
      'createdAt': createdAt,
      'updatedAt': updatedAt,
      'status': status,
    };
  }

  BlogModel copyWith({
    String? id,
    String? title,
    String? excerpt,
    String? content,
    String? author,
    String? authorBio,
    String? category,
    String? image,
    List<String>? tags,
    List<Map<String, dynamic>>? sections,
    String? readTime,
    dynamic publishedAt,
    dynamic createdAt,
    dynamic updatedAt,
    String? status,
  }) {
    return BlogModel(
      id: id ?? this.id,
      title: title ?? this.title,
      excerpt: excerpt ?? this.excerpt,
      content: content ?? this.content,
      author: author ?? this.author,
      authorBio: authorBio ?? this.authorBio,
      category: category ?? this.category,
      image: image ?? this.image,
      tags: tags ?? this.tags,
      sections: sections ?? this.sections,
      readTime: readTime ?? this.readTime,
      publishedAt: publishedAt ?? this.publishedAt,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      status: status ?? this.status,
    );
  }

  @override
  String toString() {
    return 'BlogModel(id: $id, title: $title, category: $category, status: $status)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is BlogModel && other.id == id;
  }

  @override
  int get hashCode => id.hashCode;
}





