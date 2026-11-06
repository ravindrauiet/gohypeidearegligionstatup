import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'backend_service.dart';
import 'notification_service.dart';
import 'rewards_service.dart';

// =============================================================================
// Mantras
// =============================================================================

/// A mantra to chant on the mala.
class JapMantra {
  final String id;
  final String name;
  final String devanagari;
  final String transliteration;
  final String meaning;

  const JapMantra({
    required this.id,
    required this.name,
    required this.devanagari,
    required this.transliteration,
    required this.meaning,
  });

  bool get isCustom => id == JapService.customId;
}

const List<JapMantra> japMantras = [
  JapMantra(
    id: 'shiva',
    name: 'Om Namah Shivaya',
    devanagari: 'ॐ नमः शिवाय',
    transliteration: 'Om Namah Shivaya',
    meaning: 'I bow to Shiva, the auspicious Self within all.',
  ),
  JapMantra(
    id: 'mahamantra',
    name: 'Hare Krishna maha-mantra',
    devanagari: 'हरे कृष्ण हरे कृष्ण कृष्ण कृष्ण हरे हरे ।\nहरे राम हरे राम राम राम हरे हरे ॥',
    transliteration: 'Hare Krishna Hare Krishna, Krishna Krishna Hare Hare,\nHare Rama Hare Rama, Rama Rama Hare Hare',
    meaning: 'The great mantra: calling on Krishna and Rama with love and surrender.',
  ),
  JapMantra(
    id: 'vasudeva',
    name: 'Om Namo Bhagavate Vasudevaya',
    devanagari: 'ॐ नमो भगवते वासुदेवाय',
    transliteration: 'Om Namo Bhagavate Vasudevaya',
    meaning: 'I bow to Lord Vasudeva, who dwells in every being.',
  ),
  JapMantra(
    id: 'gayatri',
    name: 'Gayatri Mantra',
    devanagari: 'ॐ भूर्भुवः स्वः ।\nतत्सवितुर्वरेण्यं भर्गो देवस्य धीमहि ।\nधियो यो नः प्रचोदयात् ॥',
    transliteration: 'Om Bhur Bhuvah Svah,\nTat Savitur Varenyam Bhargo Devasya Dhimahi,\nDhiyo Yo Nah Prachodayat',
    meaning: 'We meditate on the radiant divine light; may it awaken our minds.',
  ),
  JapMantra(
    id: 'ganesha',
    name: 'Om Gan Ganapataye Namah',
    devanagari: 'ॐ गं गणपतये नमः',
    transliteration: 'Om Gam Ganapataye Namah',
    meaning: 'Salutations to Ganesha, remover of obstacles.',
  ),
  JapMantra(
    id: 'ram',
    name: 'Shri Ram Jai Ram',
    devanagari: 'श्री राम जय राम जय जय राम',
    transliteration: 'Shri Ram Jai Ram Jai Jai Ram',
    meaning: 'Glory to Lord Rama, again and again.',
  ),
  JapMantra(
    id: 'hanuman',
    name: 'Om Hanumate Namah',
    devanagari: 'ॐ हनुमते नमः',
    transliteration: 'Om Hanumate Namah',
    meaning: 'I bow to Hanuman, giver of strength and devotion.',
  ),
  JapMantra(
    id: 'lakshmi',
    name: 'Om Shreem Mahalakshmyai Namah',
    devanagari: 'ॐ श्रीं महालक्ष्म्यै नमः',
    transliteration: 'Om Shreem Mahalakshmyai Namah',
    meaning: 'Salutations to Mahalakshmi, giver of abundance and grace.',
  ),
];

// =============================================================================
// Results / stats
// =============================================================================

/// What happened to the coins for a completed mala (shown on the completion card).
enum JapCoinStatus {
  /// Guest: counting works, coins need an account.
  signInToEarn,

  /// Sent to the server (or queued) and waiting for the answer.
  pending,

  /// Queued because the device is offline; retried later.
  queuedOffline,

  /// Paid; see [JapService.lastAwarded].
  awarded,

  /// Today's paid malas are done (the counting continues, unpaid).
  capReached,
}

/// Coins paid for a mala (emitted on [JapService.awards] for the toast).
class JapAward {
  final int amount;
  final int balance;
  final int paidToday;
  const JapAward(this.amount, this.balance, this.paidToday);
}

class JapDayStat {
  final DateTime day;
  final int malas;
  const JapDayStat(this.day, this.malas);
}

/// Pure streak math: consecutive days with at least one mala, ending today or
/// yesterday (so the streak survives until the end of today). Keys are
/// `YYYY-MM-DD` local dates.
int japStreak(Map<String, int> days, DateTime today) {
  var cur = DateTime(today.year, today.month, today.day);
  if ((days[JapService.dayKey(cur)] ?? 0) <= 0) cur = DateTime(cur.year, cur.month, cur.day - 1);
  var n = 0;
  while ((days[JapService.dayKey(cur)] ?? 0) > 0) {
    n++;
    cur = DateTime(cur.year, cur.month, cur.day - 1);
  }
  return n;
}

class _Claim {
  final String owner;
  final String day; // IST day the mala was completed
  final int at; // ms since epoch
  const _Claim(this.owner, this.day, this.at);

  Map<String, dynamic> toJson() => {'owner': owner, 'day': day, 'at': at};

  static _Claim? fromJson(Object? v) {
    if (v is! Map) return null;
    final owner = v['owner']?.toString() ?? '';
    final day = v['day']?.toString() ?? '';
    final at = v['at'] is num ? (v['at'] as num).toInt() : 0;
    if (owner.isEmpty || day.isEmpty) return null;
    return _Claim(owner, day, at);
  }
}

/// Signature of the daily reminder scheduler (NotificationService by default).
typedef JapReminderScheduler = Future<bool> Function({required bool enabled, required int hour, required int minute});

// =============================================================================
// Service
// =============================================================================

/// Jap mala counter: per-mantra counts, local practice stats, the daily
/// reminder and coin claims (POST /api/coins/jap, queued while offline).
///
/// Counting and stats are device-local (they work for guests and offline).
/// Coins are server-authoritative: 5 per mala, max 3 a day, >= 90 s apart; the
/// client only asks and shows what the server answers.
class JapService extends ChangeNotifier {
  final BackendService backend;
  final RewardsService? rewards;
  final DateTime Function() _clock;
  final Duration retryDelay;
  final JapReminderScheduler? _reminderScheduler;

  JapService(
    this.backend, {
    this.rewards,
    DateTime Function()? clock,
    this.retryDelay = const Duration(seconds: 45),
    JapReminderScheduler? reminderScheduler,
  })  : _clock = clock ?? DateTime.now,
        _reminderScheduler = reminderScheduler {
    _wasAuthed = backend.isAuthenticated;
    backend.addListener(_onBackendChanged);
  }

  static const String prefsKey = 'jap_state_v1';
  static const String customId = 'custom';
  static const int malaSize = 108;
  static const int defaultCap = 3;
  static const int coinsPerMala = 5;
  static const int minGapSeconds = 90;

  static String dayKey(DateTime d) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${d.year}-${two(d.month)}-${two(d.day)}';
  }

  // ---- State ----------------------------------------------------------------
  bool loaded = false;
  String selectedId = japMantras.first.id;
  Map<String, int> _counts = {};
  String customText = '';
  Map<String, int> _days = {};
  int totalMalas = 0;
  bool soundOn = false;
  bool reminderOn = false;
  int reminderHour = 6;
  int reminderMinute = 30;

  // Coins
  int cap = defaultCap;
  int _paidToday = 0;
  String? _paidDay; // IST day [_paidToday] belongs to
  String? _paidOwner;
  int? _lastPaidAt;
  List<_Claim> _pending = [];
  bool _flushing = false;
  bool _offline = false;
  int lastAwarded = 0;
  JapCoinStatus? lastCoinStatus;

  Timer? _retry;
  Future<void>? _loading;
  bool _disposed = false;
  bool _wasAuthed = false;
  int _generation = 0;

  final StreamController<JapAward> _awards = StreamController<JapAward>.broadcast();

  /// Coins paid for a mala (the screen shows a toast for each).
  Stream<JapAward> get awards => _awards.stream;

  DateTime get now => _clock();
  String get _istToday => istDayKey(now);
  String get _today => dayKey(now);

  bool get registered => backend.isAuthenticated;
  String get _owner => backend.user?['id']?.toString() ?? 'me';

  JapMantra get mantra {
    if (selectedId == customId) {
      final t = customText.trim();
      return JapMantra(
        id: customId,
        name: t.isEmpty ? 'Custom mantra' : t,
        devanagari: '',
        transliteration: t.isEmpty ? 'Your own mantra' : t,
        meaning: 'Chant any name or mantra that is dear to you.',
      );
    }
    return japMantras.firstWhere((m) => m.id == selectedId, orElse: () => japMantras.first);
  }

  /// Count of the current (unfinished) mala for the selected mantra.
  int get count => _counts[selectedId] ?? 0;
  int countFor(String id) => _counts[id] ?? 0;
  double get progress => (count / malaSize).clamp(0.0, 1.0);

  int get todayMalas => _days[_today] ?? 0;
  int get streak => japStreak(_days, now);
  Map<String, int> get days => Map.unmodifiable(_days);

  /// Paid malas today (server count for this account, 0 for guests).
  int get paidToday {
    if (!registered || _paidDay != _istToday || _paidOwner != _owner) return 0;
    return _paidToday;
  }

  bool get dailyCapReached => registered && paidToday >= cap;

  /// Claims waiting for the server (this account, today).
  int get pendingClaims => _pending.where((c) => c.owner == _owner && c.day == _istToday).length;

  bool get offline => _offline;

  /// The last 7 days (oldest first, today last).
  List<JapDayStat> get last7Days {
    final t = now;
    return [
      for (var i = 6; i >= 0; i--)
        () {
          final d = DateTime(t.year, t.month, t.day - i);
          return JapDayStat(d, _days[dayKey(d)] ?? 0);
        }(),
    ];
  }

  // ---- Lifecycle ------------------------------------------------------------

  /// Loads the saved state; safe to call many times.
  Future<void> load() => _loading ??= _load();

  Future<void> _load() async {
    try {
      final sp = await SharedPreferences.getInstance();
      final raw = sp.getString(prefsKey);
      if (raw != null) _apply(json.decode(raw));
    } catch (e) {
      debugPrint('Jap state unreadable, starting fresh: $e');
    }
    loaded = true;
    _notify();
    if (registered) unawaited(syncToday());
  }

  void _apply(Object? v) {
    if (v is! Map) return;
    int i(Object? x, [int f = 0]) => x is num ? x.toInt() : (int.tryParse('${x ?? ''}') ?? f);
    Map<String, int> ints(Object? x) => x is Map
        ? {for (final e in x.entries) e.key.toString(): i(e.value)}
        : <String, int>{};
    final sel = v['sel']?.toString();
    if (sel != null && (sel == customId || japMantras.any((m) => m.id == sel))) selectedId = sel;
    _counts = ints(v['counts'])..removeWhere((_, c) => c <= 0 || c >= malaSize);
    customText = (v['custom'] ?? '').toString();
    _days = ints(v['days'])..removeWhere((_, c) => c <= 0);
    totalMalas = i(v['total']);
    soundOn = v['sound'] == true;
    final rem = v['rem'];
    if (rem is Map) {
      reminderOn = rem['on'] == true;
      reminderHour = i(rem['h'], 6).clamp(0, 23);
      reminderMinute = i(rem['m'], 30).clamp(0, 59);
    }
    final paid = v['paid'];
    if (paid is Map) {
      _paidDay = paid['day']?.toString();
      _paidOwner = paid['owner']?.toString();
      _paidToday = i(paid['n']);
      _lastPaidAt = paid['last'] is num ? (paid['last'] as num).toInt() : null;
    }
    final pend = v['pending'];
    _pending = pend is List ? pend.map(_Claim.fromJson).whereType<_Claim>().toList() : [];
  }

  Map<String, dynamic> _toJson() {
    // Keep ~13 months of daily history.
    final t = now;
    final cutoff = dayKey(DateTime(t.year, t.month, t.day - 400));
    _days.removeWhere((k, _) => k.compareTo(cutoff) < 0);
    final ist = _istToday;
    _pending.removeWhere((c) => c.day != ist);
    return {
      'sel': selectedId,
      'counts': _counts,
      'custom': customText,
      'days': _days,
      'total': totalMalas,
      'sound': soundOn,
      'rem': {'on': reminderOn, 'h': reminderHour, 'm': reminderMinute},
      'paid': {'day': _paidDay, 'owner': _paidOwner, 'n': _paidToday, 'last': _lastPaidAt},
      'pending': [for (final c in _pending) c.toJson()],
    };
  }

  Future<void> _save() async {
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.setString(prefsKey, json.encode(_toJson()));
    } catch (e) {
      debugPrint('Saving jap state failed: $e');
    }
  }

  void _onBackendChanged() {
    final authed = backend.isAuthenticated;
    if (authed == _wasAuthed) return;
    _wasAuthed = authed;
    // Account changed: drop server-derived state so the next account never
    // sees (or sends) the previous one's coins.
    _generation++;
    _retry?.cancel();
    _retry = null;
    _flushing = false;
    _offline = false;
    lastAwarded = 0;
    lastCoinStatus = null;
    _paidToday = 0;
    _paidDay = null;
    _paidOwner = null;
    _lastPaidAt = null;
    _pending = [];
    cap = defaultCap;
    unawaited(_save());
    _notify();
    if (authed && loaded) unawaited(syncToday());
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _retry?.cancel();
    backend.removeListener(_onBackendChanged);
    _awards.close();
    super.dispose();
  }

  // ---- Counting -------------------------------------------------------------

  /// Counts one bead. Returns true when this tap completed a mala of 108.
  bool tap() {
    final next = count + 1;
    if (next < malaSize) {
      _counts[selectedId] = next;
      _notify();
      unawaited(_save());
      return false;
    }
    _counts.remove(selectedId);
    _days[_today] = (_days[_today] ?? 0) + 1;
    totalMalas++;
    _onMalaComplete();
    _notify();
    unawaited(_save());
    return true;
  }

  /// Takes back the last bead of the current mala (no-op at 0).
  bool undo() {
    final c = count;
    if (c <= 0) return false;
    if (c == 1) {
      _counts.remove(selectedId);
    } else {
      _counts[selectedId] = c - 1;
    }
    _notify();
    unawaited(_save());
    return true;
  }

  /// Clears the current mala's count for the selected mantra.
  void reset() {
    if (_counts.remove(selectedId) == null) return;
    _notify();
    unawaited(_save());
  }

  void select(String id) {
    if (id != customId && !japMantras.any((m) => m.id == id)) return;
    if (id == selectedId) return;
    selectedId = id;
    _notify();
    unawaited(_save());
  }

  void setCustomText(String text) {
    customText = text.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (customText.length > 80) customText = customText.substring(0, 80);
    selectedId = customId;
    _notify();
    unawaited(_save());
  }

  void setSound(bool on) {
    soundOn = on;
    _notify();
    unawaited(_save());
  }

  /// Turns the daily "Remind me to chant" reminder on/off at [hour]:[minute].
  /// Returns false when notifications are not permitted (the toggle stays off).
  Future<bool> setReminder(bool on, {int? hour, int? minute}) async {
    final h = (hour ?? reminderHour).clamp(0, 23);
    final m = (minute ?? reminderMinute).clamp(0, 59);
    var ok = true;
    try {
      final s = _reminderScheduler ?? NotificationService.instance?.setJapReminder;
      if (s != null) ok = await s(enabled: on, hour: h, minute: m);
    } catch (e) {
      debugPrint('Jap reminder failed: $e');
      ok = !on;
    }
    reminderOn = on && ok;
    reminderHour = h;
    reminderMinute = m;
    _notify();
    await _save();
    return ok;
  }

  // ---- Coins ----------------------------------------------------------------

  void _onMalaComplete() {
    lastAwarded = 0;
    if (!registered) {
      lastCoinStatus = JapCoinStatus.signInToEarn;
      return;
    }
    if (paidToday + pendingClaims >= cap) {
      lastCoinStatus = JapCoinStatus.capReached;
      return;
    }
    _pending.add(_Claim(_owner, _istToday, now.millisecondsSinceEpoch));
    lastCoinStatus = _offline ? JapCoinStatus.queuedOffline : JapCoinStatus.pending;
    unawaited(flush());
  }

  void _setPaid(int n, {int? lastAt}) {
    _paidDay = _istToday;
    _paidOwner = _owner;
    _paidToday = n;
    if (lastAt != null) _lastPaidAt = lastAt;
  }

  /// Today's paid count from the server (GET /api/coins/jap/today).
  Future<void> syncToday() async {
    if (!registered) return;
    final gen = _generation;
    try {
      final r = await backend.api('GET', '/coins/jap/today');
      if (gen != _generation) return;
      _offline = false;
      final c = r['cap'];
      if (c is num && c > 0) cap = c.toInt();
      final p = r['paidToday'];
      if (p is num) _setPaid(p.toInt());
      _notify();
      unawaited(_save());
    } on BackendException catch (e) {
      if (gen != _generation) return;
      if (e.statusCode == null || e.statusCode! >= 500) _offline = true;
      _notify();
    } catch (_) {}
    if (gen == _generation) unawaited(flush());
  }

  /// Sends queued claims one by one. The server decides what is paid.
  Future<void> flush() async {
    if (_flushing || !registered) return;
    _flushing = true;
    final gen = _generation;
    try {
      while (true) {
        if (gen != _generation) return;
        final owner = _owner;
        final ist = _istToday;
        // Stale days and other accounts' claims are never sent.
        _pending.removeWhere((c) => c.owner != owner || c.day != ist);
        if (_pending.isEmpty) break;
        if (paidToday >= cap) {
          _pending.clear();
          break;
        }
        Map<String, dynamic> r;
        try {
          r = await backend.api('POST', '/coins/jap', body: {'malaIndex': (_days[_today] ?? 0).clamp(1, 1000)});
        } on BackendException catch (e) {
          if (gen != _generation) return;
          final code = e.statusCode;
          if (code == 401 || code == 403) {
            // Not a registered account after all: nothing to claim.
            _pending.clear();
            lastCoinStatus = JapCoinStatus.signInToEarn;
          } else if (code == 429) {
            _offline = false;
            _scheduleRetry(_tooSoonDelay());
          } else if (code == null || code >= 500) {
            _offline = true;
            if (lastCoinStatus == JapCoinStatus.pending) lastCoinStatus = JapCoinStatus.queuedOffline;
            _scheduleRetry(retryDelay);
          } else {
            _pending.removeAt(0); // rejected for good
          }
          break;
        }
        if (gen != _generation) return;
        _offline = false;
        if (_pending.isNotEmpty) _pending.removeAt(0);
        final awarded = r['awarded'] is num ? (r['awarded'] as num).toInt() : 0;
        final c = r['cap'];
        if (c is num && c > 0) cap = c.toInt();
        final p = r['paidToday'];
        final nowMs = now.millisecondsSinceEpoch;
        _setPaid(p is num ? p.toInt() : paidToday + (awarded > 0 ? 1 : 0), lastAt: awarded > 0 ? nowMs : null);
        final balance = r['balance'] is num ? (r['balance'] as num).toInt() : null;
        if (awarded > 0) {
          lastAwarded = awarded;
          lastCoinStatus = JapCoinStatus.awarded;
          rewards?.applyAward(awarded, reason: 'jap_mala', ref: '$ist:$paidToday', balance: balance);
          if (!_awards.isClosed) _awards.add(JapAward(awarded, balance ?? 0, paidToday));
        } else if (r['dailyCapReached'] == true) {
          lastCoinStatus = JapCoinStatus.capReached;
        }
        if (r['dailyCapReached'] == true) _pending.clear();
        _notify();
      }
    } finally {
      if (gen == _generation) _flushing = false;
      _notify();
      unawaited(_save());
    }
  }

  Duration _tooSoonDelay() {
    final last = _lastPaidAt;
    if (last == null) return retryDelay;
    final wait = (minGapSeconds + 1) * 1000 - (now.millisecondsSinceEpoch - last);
    return Duration(milliseconds: wait.clamp(1000, (minGapSeconds + 1) * 1000));
  }

  void _scheduleRetry(Duration d) {
    _retry?.cancel();
    if (_disposed) return;
    _retry = Timer(d, () {
      _retry = null;
      unawaited(flush());
    });
  }

  /// Test hook: whether a retry is scheduled.
  @visibleForTesting
  bool get retryScheduled => _retry != null;
}
