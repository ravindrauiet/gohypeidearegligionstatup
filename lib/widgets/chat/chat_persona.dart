import 'package:flutter/material.dart';

/// Local, deterministic copy for the AI astrologer chat: greetings, thinking
/// status lines, suggested and follow-up questions. Nothing here pretends to
/// be data from the server; it only shapes the conversation UI.

enum ChatFocus { love, career, kundli, guidance }

ChatFocus chatFocusFor(String? field, String? specialty) {
  final f = '${field ?? ''} ${specialty ?? ''}'.toLowerCase();
  if (f.contains('love') || f.contains('marriage') || f.contains('relationship')) return ChatFocus.love;
  if (f.contains('career') || f.contains('wealth') || f.contains('job') || f.contains('finan')) {
    return ChatFocus.career;
  }
  if (f.contains('kundli') || f.contains('dasha') || f.contains('dosha') || f.contains('birth chart')) {
    return ChatFocus.kundli;
  }
  return ChatFocus.guidance;
}

const _honorifics = {'dr', 'dr.', 'acharya', 'pandit', 'guru', 'astro', 'shri', 'sri', 'mr', 'mrs', 'ms'};

/// "Dr. Ananya Roy" -> "Ananya", "Acharya Dev Sharma" -> "Dev".
String personaShortName(String name) {
  final trimmed = name.trim();
  if (trimmed.isEmpty) return 'Astrologer';
  if (trimmed.toLowerCase() == 'ai astrologer') return trimmed;
  final parts = trimmed.split(RegExp(r'\s+'));
  for (final p in parts) {
    if (!_honorifics.contains(p.toLowerCase())) return p;
  }
  return parts.last;
}

String personaGreeting(ChatFocus focus, String shortName, {required bool hasKundli}) {
  final source = hasKundli ? 'from your own chart' : 'using Vedic astrology';
  final me = shortName == 'AI Astrologer' ? 'your AI Astrologer' : shortName;
  switch (focus) {
    case ChatFocus.love:
      return 'I am $me. Tell me what is on your heart, whether it is a relationship, '
          'marriage timing or compatibility, and I will answer $source.';
    case ChatFocus.career:
      return 'I am $me. Ask me about your job, promotion, business or money, '
          'and I will tell you what the timing looks like, $source.';
    case ChatFocus.kundli:
      return 'I am $me. I can explain your Kundli in simple words: your Dasha, '
          'planets, doshas and the remedies that suit you.';
    case ChatFocus.guidance:
      return 'I am $me. Whatever is on your mind today, ask me in your own words. '
          'I will give you calm, practical guidance $source.';
  }
}

String personaFallbackBio(ChatFocus focus) {
  switch (focus) {
    case ChatFocus.love:
      return 'Focuses on love, marriage timing and compatibility.';
    case ChatFocus.career:
      return 'Focuses on career moves, promotions, business and money.';
    case ChatFocus.kundli:
      return 'Explains your birth chart, Dasha periods, doshas and remedies.';
    case ChatFocus.guidance:
      return 'Everyday guidance on any part of life, any time of day.';
  }
}

List<String> personaHelpBullets(ChatFocus focus) {
  switch (focus) {
    case ChatFocus.love:
      return const [
        'Good periods for marriage and commitment',
        'Compatibility with a partner',
        'Clearing misunderstandings and delays',
        'Simple remedies for harmony at home',
      ];
    case ChatFocus.career:
      return const [
        'Timing for promotions and job changes',
        'Business and investment periods',
        'Career paths that suit your chart',
        'Remedies for obstacles at work',
      ];
    case ChatFocus.kundli:
      return const [
        'Your current Dasha in plain English',
        'Strong and weak planets in your chart',
        'Doshas such as Manglik or Sade Sati',
        'Gemstones, mantras and daily remedies',
      ];
    case ChatFocus.guidance:
      return const [
        'Day-to-day decisions and timing',
        'Career, love, health and money questions',
        'Understanding planetary transits',
        'Simple remedies for peace of mind',
      ];
  }
}

/// Status lines shown next to the typing dots. Only mentions the Kundli when
/// the user actually has saved birth details.
List<String> thinkingLines(ChatFocus focus, {required bool hasKundli}) {
  if (!hasKundli) {
    return const [
      'Understanding your question…',
      'Applying Vedic principles…',
      'Thinking it through…',
      'Writing your answer…',
    ];
  }
  final middle = switch (focus) {
    ChatFocus.love => ['Looking at your 7th house…', 'Checking Venus in your chart…'],
    ChatFocus.career => ['Checking your 10th house…', 'Checking your current Dasha…'],
    ChatFocus.kundli => ['Checking your current Dasha…', 'Weighing planetary strengths…'],
    ChatFocus.guidance => ['Checking your current Dasha…', 'Looking at today\'s planets…'],
  };
  return ['Reading your Kundli…', ...middle, 'Writing your answer…'];
}

List<(IconData, String)> suggestedQuestions(ChatFocus focus) {
  const general = <(IconData, String)>[
    (Icons.trending_up_rounded, 'When will I get a promotion?'),
    (Icons.favorite_border_rounded, 'Is this a good year for marriage?'),
    (Icons.timelapse_rounded, 'What does my current Dasha mean?'),
    (Icons.self_improvement_rounded, 'How will my health and energy be this month?'),
    (Icons.spa_outlined, 'Which simple remedy will help me most right now?'),
  ];
  final specific = switch (focus) {
    ChatFocus.love => const <(IconData, String)>[
        (Icons.favorite_border_rounded, 'Is this a good year for marriage?'),
        (Icons.people_outline_rounded, 'What kind of partner suits me?'),
        (Icons.healing_outlined, 'How can I improve my relationship?'),
      ],
    ChatFocus.career => const <(IconData, String)>[
        (Icons.trending_up_rounded, 'When will I get a promotion?'),
        (Icons.work_outline_rounded, 'Should I change my job this year?'),
        (Icons.savings_outlined, 'When will my finances improve?'),
      ],
    ChatFocus.kundli => const <(IconData, String)>[
        (Icons.timelapse_rounded, 'What does my current Dasha mean?'),
        (Icons.auto_awesome_outlined, 'What are the strengths in my Kundli?'),
        (Icons.spa_outlined, 'Do I have any dosha, and what is the remedy?'),
      ],
    ChatFocus.guidance => const <(IconData, String)>[],
  };
  final seen = <String>{};
  return [...specific, ...general].where((s) => seen.add(s.$2)).take(5).toList();
}

/// Topic starters shown above the input field.
const List<(String, String)> chatTopicStarters = [
  ('Career', 'About my career: '),
  ('Love', 'About my love life: '),
  ('Health', 'About my health: '),
  ('Money', 'About my money: '),
  ('Remedies', 'Which remedy should I do for '),
];

const Map<String, List<String>> _followUpsByTopic = {
  'career': ['When is a good time to change jobs?', 'Will I get a promotion this year?', 'Which career suits my chart?'],
  'love': ['When will I get married?', 'Is my partner compatible with me?', 'How can I improve my love life?'],
  'health': ['Which months need extra care for health?', 'Which remedy helps my health?'],
  'money': ['When will my finances improve?', 'Is this a good time to invest?'],
  'dasha': ['How long does this Dasha last?', 'What will my next Dasha bring?'],
  'saturn': ['How can I reduce Saturn\'s effects?', 'When does my Sade Sati end?'],
  'remedy': ['Which gemstone suits me?', 'Give me a simple daily mantra', 'How do I do this remedy correctly?'],
};

final Map<String, RegExp> _topicPatterns = {
  'career': RegExp(r'\b(career|job|jobs|promotion|work|office|business|profession)\b', caseSensitive: false),
  'love': RegExp(r'\b(marriage|marry|married|love|partner|spouse|relationship|wedding|romance)\b',
      caseSensitive: false),
  'health': RegExp(r'\b(health|illness|disease|stress|energy|sleep|healthy)\b', caseSensitive: false),
  'money': RegExp(r'\b(money|finance|finances|financial|wealth|income|salary|invest\w*|savings?)\b',
      caseSensitive: false),
  'dasha': RegExp(r'\b(dasha|mahadasha|antardasha)\b', caseSensitive: false),
  'saturn': RegExp(r'\b(saturn|shani|sade\s?sati)\b', caseSensitive: false),
  'remedy': RegExp(r'\b(remed\w*|gemstones?|mantras?|puja|fasting)\b', caseSensitive: false),
};

const Map<ChatFocus, String> _focusTopic = {
  ChatFocus.love: 'love',
  ChatFocus.career: 'career',
  ChatFocus.kundli: 'dasha',
  ChatFocus.guidance: 'remedy',
};

/// 2 to 3 short follow-up questions picked locally from the reply's keywords
/// and the persona's focus.
List<String> followUpSuggestions(String reply, ChatFocus focus, {String? lastUserText}) {
  final matches = <(int, String)>[];
  _topicPatterns.forEach((topic, re) {
    final m = re.firstMatch(reply);
    if (m != null) matches.add((m.start, topic));
  });
  matches.sort((a, b) => a.$1.compareTo(b.$1));

  final topics = <String>[
    ...matches.map((m) => m.$2).take(2),
    _focusTopic[focus]!,
  ];
  final asked = (lastUserText ?? '').trim().toLowerCase();
  final out = <String>[];
  final seed = reply.length;
  for (final t in topics) {
    final options = _followUpsByTopic[t]!;
    for (var i = 0; i < options.length; i++) {
      final q = options[(seed + i) % options.length];
      if (q.toLowerCase() != asked && !out.contains(q)) {
        out.add(q);
        break;
      }
    }
    if (out.length == 3) break;
  }
  for (final q in const ['Tell me more', 'What should I do next?', 'Any simple remedy for this?']) {
    if (out.length >= 2) break;
    if (!out.contains(q)) out.add(q);
  }
  return out.take(3).toList();
}
