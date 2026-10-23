import 'package:flutter/material.dart';

import '../ui/app_ui.dart';

/// Tiny markdown renderer for AI replies: headings (#), bullet and numbered
/// lists, horizontal rules, **bold** and *italic*. No external package.
class ChatMarkdown extends StatelessWidget {
  final String text;
  const ChatMarkdown(this.text, {super.key});

  static const _base = TextStyle(fontSize: 15, height: 1.5, color: AppColors.textPrimary);
  static final _heading = RegExp(r'^(#{1,6})\s+(.*)$');
  static final _bullet = RegExp(r'^[-*•]\s+(.*)$');
  static final _numbered = RegExp(r'^(\d{1,3})[.)]\s+(.*)$');
  static final _rule = RegExp(r'^(-{3,}|\*{3,}|_{3,})$');
  static final _inline = RegExp(r'\*\*(.+?)\*\*|__(.+?)__|(?<![\*\w])\*(?!\s)(.+?)(?<!\s)\*(?![\*\w])');

  /// Plain text without markdown markers (for quoting / sharing snippets).
  static String plain(String s) => s
      .replaceAll(RegExp(r'^#{1,6}\s+', multiLine: true), '')
      .replaceAll(RegExp(r'^\s*[-*•]\s+', multiLine: true), '')
      .replaceAll('**', '')
      .replaceAll('__', '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  static List<InlineSpan> _spans(String s, TextStyle style) {
    final spans = <InlineSpan>[];
    var start = 0;
    for (final m in _inline.allMatches(s)) {
      if (m.start > start) spans.add(TextSpan(text: s.substring(start, m.start)));
      final bold = m.group(1) ?? m.group(2);
      if (bold != null) {
        spans.add(TextSpan(text: bold, style: const TextStyle(fontWeight: FontWeight.w700)));
      } else {
        spans.add(TextSpan(text: m.group(3), style: const TextStyle(fontStyle: FontStyle.italic)));
      }
      start = m.end;
    }
    if (start < s.length) spans.add(TextSpan(text: s.substring(start)));
    return [TextSpan(style: style, children: spans)];
  }

  @override
  Widget build(BuildContext context) {
    final blocks = <Widget>[];
    var lastWasGap = true;

    void gap(double h) {
      if (lastWasGap) return;
      blocks.add(SizedBox(height: h));
      lastWasGap = true;
    }

    for (final raw in text.replaceAll('\r\n', '\n').split('\n')) {
      final indent = raw.length - raw.trimLeft().length;
      final line = raw.trim();
      if (line.isEmpty) {
        gap(8);
        continue;
      }
      final level = (indent ~/ 2).clamp(0, 3);

      final h = _heading.firstMatch(line);
      if (h != null) {
        gap(4);
        final depth = h.group(1)!.length;
        blocks.add(Text.rich(
          TextSpan(
            children: _spans(
              h.group(2)!,
              _base.copyWith(
                fontSize: depth <= 1 ? 18 : (depth == 2 ? 16.5 : 15.5),
                fontWeight: FontWeight.w800,
                height: 1.35,
              ),
            ),
          ),
        ));
        blocks.add(const SizedBox(height: 4));
        lastWasGap = true;
        continue;
      }

      if (_rule.hasMatch(line)) {
        gap(4);
        blocks.add(const Padding(padding: EdgeInsets.symmetric(vertical: 6), child: Divider(height: 1)));
        lastWasGap = true;
        continue;
      }

      final b = _bullet.firstMatch(line);
      final n = b == null ? _numbered.firstMatch(line) : null;
      if (b != null || n != null) {
        final marker = b != null
            ? Padding(
                padding: const EdgeInsets.only(top: 9, right: 10),
                child: Container(
                  width: 5,
                  height: 5,
                  decoration: BoxDecoration(
                    color: level == 0 ? AppColors.primary : AppColors.textTertiary,
                    shape: BoxShape.circle,
                  ),
                ),
              )
            : Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Text('${n!.group(1)}.',
                    style: _base.copyWith(fontWeight: FontWeight.w700, color: AppColors.primaryDark)),
              );
        final content = b != null ? b.group(1)! : n!.group(2)!;
        blocks.add(Padding(
          padding: EdgeInsets.only(left: 4.0 + level * 14, bottom: 4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              marker,
              Expanded(child: Text.rich(TextSpan(children: _spans(content, _base)))),
            ],
          ),
        ));
        lastWasGap = false;
        continue;
      }

      blocks.add(Text.rich(TextSpan(children: _spans(line, _base))));
      lastWasGap = false;
    }

    while (blocks.isNotEmpty && blocks.last is SizedBox) {
      blocks.removeLast();
    }
    if (blocks.isEmpty) return Text(text, style: _base);

    return Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: blocks);
  }
}
