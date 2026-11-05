import 'package:flutter/foundation.dart';

import 'backend_service.dart';

// ---------------------------------------------------------------------------
// Small defensive parsers (the server is authoritative; never crash on shape).
// ---------------------------------------------------------------------------

int _int(Object? v, [int fallback = 0]) {
  if (v is int) return v;
  if (v is num) return v.round();
  if (v is String) return int.tryParse(v.trim()) ?? double.tryParse(v.trim())?.round() ?? fallback;
  return fallback;
}

int? _intOrNull(Object? v) {
  if (v == null) return null;
  if (v is num) return v.round();
  if (v is String) return int.tryParse(v.trim()) ?? double.tryParse(v.trim())?.round();
  return null;
}

String _str(Object? v, [String fallback = '']) {
  if (v == null) return fallback;
  final s = v.toString().trim();
  return s.isEmpty ? fallback : s;
}

bool _bool(Object? v) {
  if (v is bool) return v;
  if (v is num) return v != 0;
  if (v is String) return const {'true', '1', 'yes'}.contains(v.trim().toLowerCase());
  return false;
}

Map<String, dynamic> _map(Object? v) =>
    v is Map ? v.map((k, val) => MapEntry(k.toString(), val)) : <String, dynamic>{};

List<Map<String, dynamic>> _maps(Object? v) =>
    v is List ? v.whereType<Map>().map(_map).toList() : const <Map<String, dynamic>>[];

DateTime? _date(Object? v) {
  if (v is String && v.isNotEmpty) return DateTime.tryParse(v)?.toLocal();
  if (v is num) return DateTime.fromMillisecondsSinceEpoch(v.toInt());
  return null;
}

/// Today's date in India (the coins economy resets at IST midnight), `YYYY-MM-DD`.
String istDayKey([DateTime? now]) {
  final t = (now ?? DateTime.now()).toUtc().add(const Duration(hours: 5, minutes: 30));
  String two(int n) => n.toString().padLeft(2, '0');
  return '${t.year}-${two(t.month)}-${two(t.day)}';
}

/// Current month in India.
DateTime istNow([DateTime? now]) => (now ?? DateTime.now()).toUtc().add(const Duration(hours: 5, minutes: 30));

// ---------------------------------------------------------------------------
// Models
// ---------------------------------------------------------------------------

class CoinEntry {
  final String id;
  final int amount;
  final String reason;
  final String ref;
  final String note;
  final DateTime? createdAt;

  const CoinEntry({
    required this.id,
    required this.amount,
    required this.reason,
    this.ref = '',
    this.note = '',
    this.createdAt,
  });

  factory CoinEntry.fromJson(Map<String, dynamic> j) => CoinEntry(
        id: _str(j['id']),
        amount: _int(j['amount']),
        reason: _str(j['reason']),
        ref: _str(j['ref']),
        note: _str(j['note']),
        createdAt: _date(j['createdAt'] ?? j['created_at']),
      );

  /// Plain-English title for activity lists.
  String get title {
    if (note.isNotEmpty) return note;
    switch (reason) {
      case 'daily_login':
        return 'Daily check-in';
      case 'game':
        final game = ref.split(':').first;
        return switch (game) {
          'quest' => 'Played Graha Quest',
          'cards' => 'Collected a Nakshatra card',
          'moksha' => 'Played Moksha Patam',
          'circle' => 'Played Cosmic Match',
          _ => 'Played a game',
        };
      case 'video':
        return 'Watched a new video';
      case 'question':
        return 'Answered a mindset question';
      case 'trip':
        return 'Temple trip request';
      case 'trip_refund':
        return 'Temple trip refund';
      default:
        return amount >= 0 ? 'Coins earned' : 'Coins used';
    }
  }
}

class EarnRule {
  final String key;
  final String title;
  final int coins;
  final String note;
  const EarnRule({required this.key, required this.title, required this.coins, this.note = ''});

  factory EarnRule.fromJson(Map<String, dynamic> j) =>
      EarnRule(key: _str(j['key']), title: _str(j['title']), coins: _int(j['coins']), note: _str(j['note']));
}

class MindsetQuestion {
  final String id;
  final String text;
  final String category;
  final List<String> options;
  const MindsetQuestion({required this.id, required this.text, this.category = '', this.options = const []});

  factory MindsetQuestion.fromJson(Map<String, dynamic> j) => MindsetQuestion(
        id: _str(j['id']),
        text: _str(j['text'] ?? j['question']),
        category: _str(j['category']),
        options: j['options'] is List
            ? (j['options'] as List).where((o) => o != null).map((o) => _str(o)).toList()
            : const [],
      );
}

class Temple {
  final String id;
  final String name;
  final String deity;
  final String city;
  final String state;
  final String? image;
  final int? distanceKm;
  final String why;

  const Temple({
    required this.id,
    required this.name,
    this.deity = '',
    this.city = '',
    this.state = '',
    this.image,
    this.distanceKm,
    this.why = '',
  });

  factory Temple.fromJson(Map<String, dynamic> j) => Temple(
        id: _str(j['id']),
        name: _str(j['name'], 'Temple'),
        deity: _str(j['deity']),
        city: _str(j['city']),
        state: _str(j['state']),
        image: j['image'] is String && (j['image'] as String).isNotEmpty ? j['image'] as String : null,
        distanceKm: _intOrNull(j['distanceKm']),
        why: _str(j['why']),
      );

  String get place => [city, state].where((s) => s.isNotEmpty).join(', ');
}

class TempleList {
  final List<Temple> temples;
  final List<String> recommended;
  const TempleList(this.temples, this.recommended);

  List<Temple> get recommendedTemples {
    final byId = {for (final t in temples) t.id: t};
    return [for (final id in recommended) if (byId[id] != null) byId[id]!];
  }

  List<Temple> get others => temples.where((t) => !recommended.contains(t.id)).toList();
}

/// A buddy you can travel with (accepted connection).
class TripBuddy {
  final int userId;
  final String displayName;
  final String city;
  final String? photoUrl;
  final int? score;
  const TripBuddy({required this.userId, required this.displayName, this.city = '', this.photoUrl, this.score});

  factory TripBuddy.fromJson(Map<String, dynamic> j) => TripBuddy(
        userId: _int(j['userId'] ?? j['id']),
        displayName: _str(j['displayName'] ?? j['name'], 'Buddy'),
        city: _str(j['city']),
        photoUrl: j['photoUrl'] is String ? j['photoUrl'] as String : null,
        score: _intOrNull(j['score']),
      );
}

class TripRequest {
  final String id;
  final Temple temple;
  final TripBuddy buddy;
  final String preferredMonth;
  final String status;
  final DateTime? createdAt;

  /// Coins taken for this request (refunded if it is cancelled or rejected).
  final int coinsSpent;

  /// True when I made the request; false when a buddy invited me (only the
  /// requester can cancel).
  final bool mine;

  const TripRequest({
    required this.id,
    required this.temple,
    required this.buddy,
    this.preferredMonth = '',
    this.status = 'pending',
    this.createdAt,
    this.coinsSpent = 0,
    this.mine = true,
  });

  factory TripRequest.fromJson(Map<String, dynamic> j) {
    final t = j['temple'];
    return TripRequest(
      id: _str(j['id']),
      temple: t is Map ? Temple.fromJson(_map(t)) : Temple(id: _str(j['templeId']), name: _str(t, 'Temple')),
      buddy: TripBuddy.fromJson(_map(j['buddy'])),
      preferredMonth: _str(j['preferredMonth'] ?? j['preferred_month']),
      status: _str(j['status'], 'pending').toLowerCase(),
      createdAt: _date(j['createdAt'] ?? j['created_at']),
      coinsSpent: _int(j['coinsSpent'] ?? j['coins_spent']),
      mine: j.containsKey('mine') ? _bool(j['mine']) : true,
    );
  }

  bool get isPending => status == 'pending';

  /// Only my own pending requests can be cancelled (POST /trips/:id/cancel).
  bool get canCancel => isPending && mine;
}

/// Raised when an action needs a registered account.
class LoginRequiredException implements Exception {
  final String message;
  const LoginRequiredException([this.message = 'Please log in to earn and use coins.']);
  @override
  String toString() => message;
}

// ---------------------------------------------------------------------------
// Service
// ---------------------------------------------------------------------------

/// Coins balance, daily check-in, mindset quiz and temple trips (/api/coins, /api/trips).
/// Registered in main.dart; read it with `context.read<RewardsService>()`.
class RewardsService extends ChangeNotifier {
  final BackendService backend;

  RewardsService(this.backend) {
    _wasAuthenticated = _authed;
    backend.addListener(_onBackendChanged);
  }

  static const int defaultGoal = 10000;
  static const int defaultQuestionCount = 50;

  // Wallet
  int balance = 0;
  int goal = defaultGoal;
  int streakDays = 0;
  bool dailyClaimed = false;
  int todayEarned = 0;
  List<CoinEntry> recent = const [];
  List<EarnRule> earnRules = const [];

  // Quiz
  List<MindsetQuestion> questions = const [];
  Map<String, int> answers = const {};
  int answeredCount = 0;
  int coinsPerQuestion = 50;
  bool questionsLoaded = false;

  // State
  bool loading = false;
  bool loaded = false;
  String? error;
  bool _loggedInFlag = true;
  bool _disposed = false;
  bool _wasAuthenticated = false;
  Future<void>? _inflight;

  /// Bumped whenever the signed-in account changes, so late responses for the
  /// previous account are dropped instead of overwriting the new one.
  int _generation = 0;

  bool get _authed => backend.isAuthenticated;

  /// True when a registered user is signed in (coins need an account).
  bool get loggedIn => _authed && _loggedInFlag;

  double get progress => goal <= 0 ? 0 : (balance / goal).clamp(0.0, 1.0);
  int get coinsToGoal => (goal - balance).clamp(0, goal);
  bool get tripUnlocked => balance >= goal;
  int get questionTotal => questions.isNotEmpty ? questions.length : defaultQuestionCount;

  /// Daily reward is waiting (used for the dot on [CoinsPill]).
  bool get dailyAvailable => loggedIn && loaded && !dailyClaimed;

  void _onBackendChanged() {
    final now = _authed;
    if (now == _wasAuthenticated) return;
    _wasAuthenticated = now;
    _reset();
    if (now) {
      refresh();
    } else {
      _notify();
    }
  }

  void _reset() {
    _generation++;
    _inflight = null;
    loading = false;
    balance = 0;
    goal = defaultGoal;
    streakDays = 0;
    dailyClaimed = false;
    todayEarned = 0;
    recent = const [];
    earnRules = const [];
    questions = const [];
    answers = const {};
    answeredCount = 0;
    questionsLoaded = false;
    loaded = false;
    error = null;
    _loggedInFlag = true;
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    backend.removeListener(_onBackendChanged);
    super.dispose();
  }

  // LOGIN_REQUIRED is always a 401. (backend.lastErrorCode is shared by every
  // request in flight, so it says nothing reliable about this one.)
  bool _isLoginError(BackendException e) => e.statusCode == 401;

  static const _accountChanged = LoginRequiredException('Your account changed. Please try again.');

  Future<Map<String, dynamic>> _call(String method, String path, {Map<String, dynamic>? body}) async {
    if (!_authed) {
      _loggedInFlag = false;
      _notify();
      throw const LoginRequiredException();
    }
    final gen = _generation;
    try {
      final r = await backend.api(method, path, body: body);
      if (gen != _generation) throw _accountChanged;
      _loggedInFlag = true;
      return r;
    } on BackendException catch (e) {
      if (gen != _generation) throw _accountChanged;
      if (_isLoginError(e)) {
        _loggedInFlag = false;
        _notify();
        throw LoginRequiredException(e.message.isNotEmpty ? e.message : 'Please log in to earn and use coins.');
      }
      rethrow;
    }
  }

  void _applyBalance(Map<String, dynamic> r) {
    if (r.containsKey('balance')) balance = _int(r['balance'], balance);
  }

  void _addLocal(int amount, String reason, {String ref = '', String note = ''}) {
    if (amount == 0) return;
    if (amount > 0) todayEarned += amount;
    recent = [
      CoinEntry(
          id: 'local-${DateTime.now().microsecondsSinceEpoch}',
          amount: amount,
          reason: reason,
          ref: ref,
          note: note,
          createdAt: DateTime.now()),
      ...recent,
    ].take(30).toList();
  }

  /// Loads the wallet. Safe to call often; concurrent calls share one request.
  Future<void> refresh() {
    final existing = _inflight;
    if (existing != null) return existing;
    late final Future<void> f;
    f = _refresh().whenComplete(() {
      if (identical(_inflight, f)) _inflight = null;
    });
    return _inflight = f;
  }

  Future<void> _refresh() async {
    if (!_authed) {
      _loggedInFlag = false;
      loaded = false;
      _notify();
      return;
    }
    loading = true;
    error = null;
    _notify();
    final gen = _generation;
    try {
      final r = await _call('GET', '/coins');
      balance = _int(r['balance']);
      goal = _int(r['goal'], defaultGoal);
      if (goal <= 0) goal = defaultGoal;
      todayEarned = _int(r['todayEarned']);
      dailyClaimed = _bool(r['dailyClaimed']);
      streakDays = _int(r['streakDays']);
      earnRules = _maps(r['earnRules']).map(EarnRule.fromJson).toList();
      recent = _maps(r['recent']).map(CoinEntry.fromJson).toList();
      loaded = true;
    } on LoginRequiredException {
      if (gen == _generation) loaded = false;
    } catch (e) {
      error = e is BackendException ? e.message : 'Could not load your coins. Please try again.';
    } finally {
      if (gen == _generation) loading = false;
      _notify();
    }
  }

  /// Claims today's check-in coin. Returns the coins awarded (0 if already claimed).
  Future<int> claimDaily() async {
    final r = await _call('POST', '/coins/daily');
    final awarded = _int(r['awarded']);
    _applyBalance(r);
    if (r.containsKey('streakDays')) streakDays = _int(r['streakDays'], streakDays);
    dailyClaimed = true;
    _addLocal(awarded, 'daily_login', ref: istDayKey());
    _notify();
    return awarded;
  }

  /// Pays 1 coin the first time a video is watched. Returns coins awarded.
  Future<int> rewardVideo(String videoId, [String? title]) async {
    final r = await _call('POST', '/coins/video', body: {'videoId': videoId, if (title != null) 'title': title});
    final awarded = _int(r['awarded']);
    _applyBalance(r);
    _addLocal(awarded, 'video', ref: videoId);
    _notify();
    return awarded;
  }

  /// Records coins the server already paid elsewhere (a game route's
  /// `coinsAwarded`, or `POST /coins/video`). Pass the server's [balance] when
  /// it is known. If the wallet hasn't loaded yet it is fetched, not guessed.
  void applyAward(int amount, {String reason = 'game', String ref = '', int? balance}) {
    if (amount <= 0 && balance == null) return;
    if (!loaded) {
      if (loggedIn && !loading) refresh();
      return;
    }
    if (balance != null) {
      this.balance = balance;
    } else {
      this.balance += amount;
    }
    _addLocal(amount, reason, ref: ref);
    _notify();
  }

  /// The 50 mindset questions plus the answers given so far.
  Future<void> loadQuestions() async {
    final r = await _call('GET', '/coins/questions');
    questions = _maps(r['questions']).map(MindsetQuestion.fromJson).where((q) => q.id.isNotEmpty).toList();
    final a = _map(r['answers']);
    answers = {
      for (final e in a.entries)
        if (_intOrNull(e.value) != null) e.key: _intOrNull(e.value)!,
    };
    answeredCount = r.containsKey('answeredCount') ? _int(r['answeredCount']) : answers.length;
    coinsPerQuestion = _int(r['coinsPerQuestion'], 50);
    questionsLoaded = true;
    _notify();
  }

  /// Index of the first unanswered question (or [questions.length] when all are done).
  int get firstUnanswered {
    for (var i = 0; i < questions.length; i++) {
      if (!answers.containsKey(questions[i].id)) return i;
    }
    return questions.length;
  }

  /// Saves an answer. Returns coins awarded (50 the first time, 0 for a change).
  Future<int> answerQuestion(String id, int optionIndex) async {
    final r = await _call('POST', '/coins/questions/${Uri.encodeComponent(id)}/answer',
        body: {'optionIndex': optionIndex});
    final awarded = _int(r['awarded']);
    _applyBalance(r);
    answers = {...answers, id: optionIndex};
    answeredCount = r.containsKey('answeredCount') ? _int(r['answeredCount']) : answers.length;
    _addLocal(awarded, 'question', ref: id);
    _notify();
    return awarded;
  }

  // ---- Trips ---------------------------------------------------------------

  /// Accepted buddies you can request a trip with (from /api/buddy/connections).
  Future<List<TripBuddy>> loadTripBuddies() async {
    final r = await _call('GET', '/buddy/connections');
    return _maps(r['buddies'])
        .map((c) => TripBuddy.fromJson(_map(c['other'])))
        .where((b) => b.userId > 0)
        .toList();
  }

  Future<TempleList> loadTemples(int? buddyId) async {
    final r = await _call('GET', buddyId == null ? '/trips/temples' : '/trips/temples?buddyId=$buddyId');
    final temples = _maps(r['temples']).map(Temple.fromJson).where((t) => t.id.isNotEmpty).toList();
    final rec = r['recommended'] is List ? (r['recommended'] as List).map((e) => _str(e)).toList() : <String>[];
    return TempleList(temples, rec);
  }

  /// Requests a trip; the server deducts [goal] coins. Returns the new request.
  Future<TripRequest> requestTrip({required int buddyId, required String templeId, required String preferredMonth}) async {
    final r = await _call('POST', '/trips/request',
        body: {'buddyId': buddyId, 'templeId': templeId, 'preferredMonth': preferredMonth});
    final request = TripRequest.fromJson(_map(r['request']));
    final spent = request.coinsSpent > 0 ? request.coinsSpent : goal;
    _applyBalance(r);
    if (!r.containsKey('balance')) balance = (balance - spent).clamp(0, 1 << 31);
    _addLocal(-spent, 'trip', ref: 'trip:${request.id}');
    _notify();
    return request;
  }

  Future<List<TripRequest>> myTrips() async {
    final r = await _call('GET', '/trips');
    return _maps(r['requests']).map(TripRequest.fromJson).toList();
  }

  /// Cancels one of my pending requests; the server refunds its coins.
  /// Returns the updated request when the server sends it.
  Future<TripRequest?> cancelTrip(String id) async {
    final r = await _call('POST', '/trips/${Uri.encodeComponent(id)}/cancel');
    _applyBalance(r);
    _notify();
    await refresh();
    return r['request'] is Map ? TripRequest.fromJson(_map(r['request'])) : null;
  }
}
