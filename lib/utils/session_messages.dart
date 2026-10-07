/// Helpers shared by the seeker and Pandit sides of a live consultation chat
/// (`/pandit/session/:id/messages`).
library;

/// A message in a consultation session.
///
/// Server messages have an [id]; local notices (e.g. "Session started") use
/// `id == null` and `senderRole == 'system'`.
class SessionMessage {
  final int? id;
  final String senderRole; // 'seeker' | 'pandit' | 'system'
  final String content;
  final bool isPrescription;
  final DateTime time;

  const SessionMessage({
    this.id,
    required this.senderRole,
    required this.content,
    this.isPrescription = false,
    required this.time,
  });

  factory SessionMessage.system(String text) =>
      SessionMessage(senderRole: 'system', content: text, time: DateTime.now());

  /// Parses a message row from the backend; returns null when malformed.
  static SessionMessage? fromJson(dynamic raw) {
    if (raw is! Map) return null;
    final id = parseId(raw['id']);
    if (id == null) return null;
    final created = DateTime.tryParse(raw['createdAt']?.toString() ?? '');
    return SessionMessage(
      id: id,
      senderRole: raw['senderRole']?.toString() ?? 'seeker',
      content: raw['content']?.toString() ?? '',
      isPrescription: raw['isPrescription'] == true,
      time: created?.toLocal() ?? DateTime.now(),
    );
  }

  bool get isSystem => senderRole == 'system';

  /// Prescription text is stored as "Gemstone: …\nMantra: …\nRemedy: …".
  /// Returns label → value pairs (falls back to the whole text as a remedy).
  Map<String, String> get prescriptionParts {
    final parts = <String, String>{};
    for (final line in content.split('\n')) {
      final idx = line.indexOf(':');
      if (idx <= 0) continue;
      final label = line.substring(0, idx).trim();
      final value = line.substring(idx + 1).trim();
      if (value.isNotEmpty && const ['Gemstone', 'Mantra', 'Remedy'].contains(label)) {
        parts[label] = value;
      }
    }
    if (parts.isEmpty && content.trim().isNotEmpty) parts['Remedy'] = content.trim();
    return parts;
  }
}

/// Parses an integer id from an int/num/String value.
int? parseId(dynamic v) {
  if (v is int) return v > 0 ? v : null;
  if (v is num) return v > 0 ? v.toInt() : null;
  if (v is String) {
    final n = int.tryParse(v.trim());
    return (n != null && n > 0) ? n : null;
  }
  return null;
}

/// Adds [incoming] server messages to [messages] (deduplicated by id, kept in
/// id order after any local notices). Returns true when anything was added.
bool mergeSessionMessages(List<SessionMessage> messages, Iterable<SessionMessage> incoming) {
  final known = {for (final m in messages) if (m.id != null) m.id!};
  var added = false;
  for (final m in incoming) {
    if (m.id == null || known.contains(m.id)) continue;
    known.add(m.id!);
    messages.add(m);
    added = true;
  }
  return added;
}

/// Highest server message id in [messages] (0 when none).
int lastSessionMessageId(List<SessionMessage> messages) {
  var maxId = 0;
  for (final m in messages) {
    if (m.id != null && m.id! > maxId) maxId = m.id!;
  }
  return maxId;
}

String formatSessionDuration(Duration d) {
  final h = d.inHours;
  final mm = (d.inMinutes % 60).toString().padLeft(2, '0');
  final ss = (d.inSeconds % 60).toString().padLeft(2, '0');
  return h > 0 ? '$h:$mm:$ss' : '$mm:$ss';
}

String formatSessionClock(DateTime t) {
  final hour = t.hour % 12 == 0 ? 12 : t.hour % 12;
  final minute = t.minute.toString().padLeft(2, '0');
  return '$hour:$minute ${t.hour < 12 ? 'AM' : 'PM'}';
}
