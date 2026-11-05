import 'dart:async';
import 'dart:collection';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'backend_service.dart';
import 'rewards_service.dart' show istDayKey;

// ============================================================================
// Models
// ============================================================================

/// One curated YouTube playlist from `GET /api/videos/playlists`.
class VideoPlaylist {
  final int no;
  final String title;
  final String category;
  final String playlistId;
  final String? thumbnail;

  const VideoPlaylist({
    required this.no,
    required this.title,
    required this.category,
    required this.playlistId,
    this.thumbnail,
  });

  factory VideoPlaylist.fromJson(Map<String, dynamic> j) => VideoPlaylist(
        no: _toInt(j['no']) ?? 0,
        title: (j['title'] ?? '').toString(),
        category: (j['category'] ?? 'Other').toString(),
        playlistId: (j['playlistId'] ?? '').toString(),
        thumbnail: _nonEmpty(j['thumbnail']),
      );

  /// Title without the channel tag ("| Tilak") and with tidy separators.
  String get displayTitle => VideoCategories.cleanTitle(title);

  bool get isShorts => VideoCategories.isShorts(category);

  String get youtubeUrl => 'https://www.youtube.com/playlist?list=$playlistId';
}

/// One video inside a playlist.
class VideoItem {
  final String videoId;
  final String title;
  final String thumbnail;
  final DateTime? publishedAt;

  const VideoItem({required this.videoId, required this.title, required this.thumbnail, this.publishedAt});

  factory VideoItem.fromJson(Map<String, dynamic> j) {
    final id = (j['videoId'] ?? '').toString();
    return VideoItem(
      videoId: id,
      title: (j['title'] ?? '').toString(),
      thumbnail: _nonEmpty(j['thumbnail']) ?? (id.isEmpty ? '' : 'https://i.ytimg.com/vi/$id/hqdefault.jpg'),
      publishedAt: DateTime.tryParse((j['publishedAt'] ?? '').toString()),
    );
  }

  String get displayTitle => VideoCategories.cleanTitle(title);
  String get youtubeUrl => 'https://www.youtube.com/watch?v=$videoId';
}

/// `GET /api/videos/playlists/:playlistId`.
class PlaylistDetail {
  final String playlistId;
  final String title;
  final List<VideoItem> videos;
  final String source;

  /// False when only the latest videos are known (RSS feed, latest 15).
  final bool complete;

  const PlaylistDetail({
    required this.playlistId,
    required this.title,
    required this.videos,
    this.source = 'rss',
    this.complete = true,
  });

  factory PlaylistDetail.fromJson(Map<String, dynamic> j, String fallbackId) => PlaylistDetail(
        playlistId: _nonEmpty(j['playlistId']) ?? fallbackId,
        title: (j['title'] ?? '').toString(),
        videos: [
          for (final v in (j['videos'] as List? ?? const []))
            if (v is Map) VideoItem.fromJson(Map<String, dynamic>.from(v)),
        ].where((v) => v.videoId.isNotEmpty).toList(),
        source: (j['source'] ?? 'rss').toString(),
        complete: j['complete'] != false && j['complete'] != 'false',
      );

  String? get firstThumbnail => videos.isEmpty ? null : videos.first.thumbnail;
}

String? _nonEmpty(Object? v) {
  final s = v?.toString().trim() ?? '';
  return s.isEmpty ? null : s;
}

bool _truthy(Object? v) => v == true || v == 1 || v == 'true';

/// Lenient int parse (numbers, numeric strings); null when absent / not numeric.
int? _toInt(Object? v) {
  if (v is num) return v.toInt();
  if (v is String) return int.tryParse(v.trim()) ?? double.tryParse(v.trim())?.toInt();
  return null;
}

// ============================================================================
// Categories: English labels, icons and fallback gradients
// ============================================================================

class VideoCategoryStyle {
  final String label;
  final IconData icon;
  final List<Color> colors;
  const VideoCategoryStyle(this.label, this.icon, this.colors);

  LinearGradient get gradient =>
      LinearGradient(colors: colors, begin: Alignment.topLeft, end: Alignment.bottomRight);
}

class VideoCategories {
  VideoCategories._();

  static const shorts = 'Shorts';

  /// Display order of the rails (unknown categories go last).
  static const order = [
    'Episodes / Series',
    'Bhajan / Music',
    'Katha / Stories',
    'Darshan / Temples',
    'Shorts',
    'Other / Festival Special',
    'Samvad / Dialogues',
    'Lifestyle / Yoga',
  ];

  static const _styles = <String, VideoCategoryStyle>{
    'Episodes / Series':
        VideoCategoryStyle('Series', Icons.live_tv_rounded, [Color(0xFF2B1E6E), Color(0xFF1B1446)]),
    'Bhajan / Music':
        VideoCategoryStyle('Bhajans', Icons.music_note_rounded, [Color(0xFFFF8A2B), Color(0xFFE5560A)]),
    'Katha / Stories':
        VideoCategoryStyle('Katha', Icons.auto_stories_rounded, [Color(0xFF8E3B2F), Color(0xFF5C1F1A)]),
    'Darshan / Temples':
        VideoCategoryStyle('Darshan', Icons.temple_hindu_rounded, [Color(0xFFF5B83D), Color(0xFFC97A0A)]),
    'Shorts': VideoCategoryStyle('Shorts', Icons.bolt_rounded, [Color(0xFFE8457A), Color(0xFFB0244F)]),
    'Other / Festival Special':
        VideoCategoryStyle('Festivals', Icons.celebration_rounded, [Color(0xFFD9480F), Color(0xFF8C2A06)]),
    'Samvad / Dialogues':
        VideoCategoryStyle('Dialogues', Icons.forum_rounded, [Color(0xFF4F46E5), Color(0xFF2E2275)]),
    'Lifestyle / Yoga':
        VideoCategoryStyle('Yoga', Icons.self_improvement_rounded, [Color(0xFF16A34A), Color(0xFF0B6B30)]),
  };

  static VideoCategoryStyle style(String category) =>
      _styles[category] ??
      VideoCategoryStyle(
        category.split('/').first.trim().isEmpty ? 'Videos' : category.split('/').first.trim(),
        Icons.play_circle_outline_rounded,
        const [Color(0xFF2B1E6E), Color(0xFF110C30)],
      );

  static String label(String category) => style(category).label;

  static bool isShorts(String category) => category.trim().toLowerCase() == 'shorts';

  static int rank(String category) {
    final i = order.indexOf(category);
    return i < 0 ? order.length : i;
  }

  static List<String> sorted(Iterable<String> categories) {
    final list = categories.toSet().toList();
    list.sort((a, b) {
      final r = rank(a).compareTo(rank(b));
      return r != 0 ? r : a.compareTo(b);
    });
    return list;
  }

  static final _channelTag = RegExp(r'^(tilak|tilak\s+presents)$', caseSensitive: false);

  /// "Ramayan Maha Episodes | Complete Series | Tilak" -> "Ramayan Maha Episodes · Complete Series".
  static String cleanTitle(String raw) {
    final parts = raw
        .split('|')
        .map((p) => p.trim())
        .where((p) => p.isNotEmpty && !_channelTag.hasMatch(p))
        .toList();
    return parts.isEmpty ? raw.trim() : parts.join(' · ');
  }
}

// ============================================================================
// Service
// ============================================================================

/// Devotional video playlists and per-video coin rewards (/api/videos).
/// Registered in main.dart; read it with `context.read<VideoService>()`.
class VideoService extends ChangeNotifier {
  final BackendService backend;
  VideoService(this.backend) {
    _accountKey = _currentWatchedKey;
    backend.addListener(_onBackendChanged);
  }

  String? _accountKey;
  bool _disposed = false;

  /// A different account (or a logout) must not inherit the previous
  /// account's "watched / already paid" set.
  void _onBackendChanged() {
    final key = _currentWatchedKey;
    if (key == _accountKey) return;
    _accountKey = key;
    _watched.clear();
    _rewardInFlight.clear();
    _watchedKey = null;
    _watchedRestore = null;
    _lastBalance = null;
    _capDay = null;
    _capNoticeDay = null;
    // Cached details carried the old account's server-side `watched` list.
    _details.clear();
    unawaited(_ensureWatchedRestored());
    notifyListeners();
  }

  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    backend.removeListener(_onBackendChanged);
    super.dispose();
  }

  /// Featured playlists for the Home rail (Ramayan, Shree Krishna, Gayatri
  /// Mantra, Darshan...). Missing ids are skipped and the rail is topped up.
  static const featuredPlaylistIds = [
    'PLFPJRCFRDARQOx_u4wFgPS4hxdmbJJnIa', // Ramayan Maha Episodes
    'PLSMyO3eMGTtI', // Shree Krishna Maha Episodes
    'PLFPJRCFRDARR9b9Dmuj1u_89qV3WcLH5F', // Gayatri Mantra
    'PLFPJRCFRDARQgf5MljhsLSIAMuH_FuSAP', // Darshan Compilation
    'PLFPJRCFRDARSByM2MRBaRfPILhMy-cjEe', // Ramayan Bhajans
    'PLFPJRCFRDARR_OO52A6oAPH4tZC9Hk7ke', // Shree Krishna Bhajan Jukebox
    'PLFPJRCFRDARRcEU7fR0xA0ruOlv5-0DtS', // Shree Krishna Stories
    'PLFPJRCFRDARRaSeEyAgRdyz6raMUad-7R', // Famous Temples of Lord Ganesha
  ];

  static const _kWatchedPrefix = 'videos_watched_v1:';
  static const _maxConcurrentFetches = 4;

  List<VideoPlaylist> _playlists = const [];
  List<String> _categories = const [];
  bool _loading = false;
  bool _loaded = false;
  String? _error;
  Future<void>? _playlistsFuture;

  final Map<String, PlaylistDetail> _details = {};
  final Map<String, Future<PlaylistDetail>> _detailFutures = {};

  /// playlistId -> first-video thumbnail ('' = known to have none).
  final Map<String, String> _thumbs = {};

  final Set<String> _watched = {};
  final Set<String> _rewardInFlight = {};
  String? _watchedKey;
  Future<void>? _watchedRestore;

  int _activeFetches = 0;
  final Queue<Completer<void>> _fetchWaiters = Queue();

  int? _lastBalance;

  List<VideoPlaylist> get playlists => _playlists;
  List<String> get categories => _categories;
  bool get loading => _loading;
  bool get loaded => _loaded;
  String? get error => _error;

  /// Latest coin balance reported by `POST /coins/video` (null until a reward call).
  int? get lastBalance => _lastBalance;

  /// Coins are only paid to registered (logged-in) users.
  bool get canEarn => backend.isAuthenticated;

  Set<String> get watched => UnmodifiableSetView(_watched);
  bool isWatched(String videoId) => _watched.contains(videoId);

  VideoPlaylist? playlistById(String playlistId) {
    for (final p in _playlists) {
      if (p.playlistId == playlistId) return p;
    }
    return null;
  }

  List<VideoPlaylist> playlistsIn(String category) =>
      _playlists.where((p) => p.category == category).toList();

  /// Case-insensitive title search (works for Hindi and English titles).
  List<VideoPlaylist> search(String query, {String? category}) {
    final q = query.trim().toLowerCase();
    return _playlists.where((p) {
      if (category != null && p.category != category) return false;
      if (q.isEmpty) return true;
      return p.title.toLowerCase().contains(q) || VideoCategories.label(p.category).toLowerCase().contains(q);
    }).toList();
  }

  /// Up to [count] featured playlists for the Home rail.
  List<VideoPlaylist> featured({int count = 8}) {
    final out = <VideoPlaylist>[];
    for (final id in featuredPlaylistIds) {
      final p = playlistById(id);
      if (p != null) out.add(p);
    }
    // Top up with the first playlist of each non-Shorts category, then anything.
    for (final c in _categories) {
      if (out.length >= count) break;
      if (VideoCategories.isShorts(c)) continue;
      for (final p in playlistsIn(c)) {
        if (!out.contains(p)) {
          out.add(p);
          break;
        }
      }
    }
    for (final p in _playlists) {
      if (out.length >= count) break;
      if (!out.contains(p) && !p.isShorts) out.add(p);
    }
    return out.take(count).toList();
  }

  // ---------------------------------------------------------------------------
  // Playlists
  // ---------------------------------------------------------------------------

  /// Loads the playlist catalogue (once; [force] reloads).
  Future<void> loadPlaylists({bool force = false}) {
    if (!force && _loaded) return Future.value();
    return _playlistsFuture ??= _loadPlaylists().whenComplete(() => _playlistsFuture = null);
  }

  Future<void> _loadPlaylists() async {
    _loading = true;
    _error = null;
    notifyListeners();
    unawaited(_ensureWatchedRestored());
    try {
      final res = await backend.api('GET', '/videos/playlists');
      final list = [
        for (final p in (res['playlists'] as List? ?? const []))
          if (p is Map) VideoPlaylist.fromJson(Map<String, dynamic>.from(p)),
      ].where((p) => p.playlistId.isNotEmpty).toList();
      final cats = [
        for (final c in (res['categories'] as List? ?? const [])) c.toString(),
        ...list.map((p) => p.category),
      ];
      _playlists = list;
      _categories = VideoCategories.sorted(cats.where((c) => list.any((p) => p.category == c)));
      for (final p in list) {
        if (p.thumbnail != null) _thumbs[p.playlistId] = p.thumbnail!;
      }
      _loaded = true;
    } catch (e) {
      _error = e is BackendException ? e.message : 'Could not load videos. Please try again.';
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  /// Playlist detail already in memory, if any.
  PlaylistDetail? cachedDetail(String playlistId) => _details[playlistId];

  /// Loads (and caches in memory) a playlist's videos. Concurrent calls share
  /// one request. Throws [BackendException] on failure.
  Future<PlaylistDetail> playlistDetail(String playlistId, {bool force = false}) {
    if (!force) {
      final cached = _details[playlistId];
      if (cached != null) return Future.value(cached);
    }
    final pending = _detailFutures[playlistId];
    if (pending != null) return pending;
    // Block body: `remove` returns this very future, which whenComplete would await.
    final f = _fetchDetail(playlistId).whenComplete(() {
      _detailFutures.remove(playlistId);
    });
    _detailFutures[playlistId] = f;
    return f;
  }

  Future<PlaylistDetail> _fetchDetail(String playlistId) async {
    await _acquireSlot();
    try {
      await _ensureWatchedRestored();
      final account = _watchedKey;
      final res = await backend.api('GET', '/videos/playlists/${Uri.encodeComponent(playlistId)}');
      final detail = PlaylistDetail.fromJson(res, playlistId);
      _thumbs[playlistId] = detail.firstThumbnail ?? _thumbs[playlistId] ?? '';
      if (account != _watchedKey) {
        // The account changed mid-request: keep the videos, drop its watched list.
        notifyListeners();
        return detail;
      }
      _details[playlistId] = detail;
      final watched = res['watched'];
      if (watched is List && watched.isNotEmpty) {
        final before = _watched.length;
        _watched.addAll(watched.map((e) => e.toString()).where((e) => e.isNotEmpty));
        if (_watched.length != before) unawaited(_persistWatched());
      }
      notifyListeners();
      return detail;
    } finally {
      _releaseSlot();
    }
  }

  /// Thumbnail to show for a playlist card right now (null = not known yet,
  /// '' = known to have none: use the gradient fallback).
  String? thumbnailFor(String playlistId) => _thumbs[playlistId];

  /// Lazily resolves a playlist card's thumbnail (first video's image).
  /// Never throws; returns '' when the playlist can't be loaded.
  Future<String> loadThumbnail(String playlistId) async {
    final known = _thumbs[playlistId];
    if (known != null) return known;
    try {
      final d = await playlistDetail(playlistId);
      return d.firstThumbnail ?? '';
    } catch (_) {
      _thumbs[playlistId] = '';
      return '';
    }
  }

  Future<void> _acquireSlot() async {
    if (_activeFetches < _maxConcurrentFetches) {
      _activeFetches++;
      return;
    }
    final c = Completer<void>();
    _fetchWaiters.add(c);
    await c.future; // slot handed over by _releaseSlot
  }

  void _releaseSlot() {
    if (_fetchWaiters.isNotEmpty) {
      _fetchWaiters.removeFirst().complete();
    } else {
      _activeFetches--;
    }
  }

  // ---------------------------------------------------------------------------
  // Watched set + coins
  // ---------------------------------------------------------------------------

  String get _currentWatchedKey {
    final id = backend.user?['id'] ?? backend.user?['userId'];
    return '$_kWatchedPrefix${backend.isAuthenticated && id != null ? id : 'anon'}';
  }

  Future<void> _ensureWatchedRestored() {
    final key = _currentWatchedKey;
    if (_watchedKey == key && _watchedRestore != null) return _watchedRestore!;
    _watchedKey = key;
    _watched.clear();
    return _watchedRestore = () async {
      try {
        final prefs = await SharedPreferences.getInstance();
        final saved = prefs.getStringList(key) ?? const [];
        if (_watchedKey == key && saved.isNotEmpty) {
          _watched.addAll(saved);
          notifyListeners();
        }
      } catch (e) {
        debugPrint('VideoService: could not restore watched list: $e');
      }
    }();
  }

  Future<void> _persistWatched() async {
    final key = _watchedKey;
    if (key == null) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(key, _watched.toList());
    } catch (e) {
      debugPrint('VideoService: could not save watched list: $e');
    }
  }

  /// IST day on which the server said the daily video-coin cap was reached.
  String? _capDay;
  String? _capNoticeDay;

  /// True when today's video coins are used up (server cap, resets at IST midnight).
  bool get dailyCapReached => _capDay != null && _capDay == istDayKey();

  /// True once per IST day after the cap is hit: show the "come back
  /// tomorrow" note at most once a day.
  bool takeDailyCapNotice() {
    if (!dailyCapReached || _capNoticeDay == _capDay) return false;
    _capNoticeDay = _capDay;
    return true;
  }

  /// Pays 1 coin for a video the user hasn't been paid for yet.
  /// Returns the coins awarded (0 or 1). Guests / LOGIN_REQUIRED / errors -> 0.
  Future<int> rewardIfNew(String videoId, String title) async =>
      await claimVideoReward(videoId, title) ?? 0;

  /// Like [rewardIfNew], but returns null when the claim failed for a
  /// temporary reason (offline, timeout, server error) and may be retried.
  /// 0 means "nothing to pay" (guest, already paid, login required, bad id).
  Future<int?> claimVideoReward(String videoId, String title) async {
    if (videoId.isEmpty || !canEarn) return 0;
    await _ensureWatchedRestored();
    if (_watched.contains(videoId) || _rewardInFlight.contains(videoId)) return 0;
    if (dailyCapReached) return 0; // no more video coins today: don't even ask
    final account = _watchedKey;
    _rewardInFlight.add(videoId);
    try {
      final res = await backend.api('POST', '/coins/video', body: {'videoId': videoId, 'title': title});
      if (account != _watchedKey) return 0; // account switched mid-request
      final awarded = _toInt(res['awarded']) ?? 0;
      final balance = _toInt(res['balance']);
      if (balance != null) _lastBalance = balance;
      if (awarded <= 0 && _truthy(res['dailyCapReached'])) {
        // Not paid because of the daily cap: leave the video unclaimed so it
        // can still pay tomorrow, and stop asking for the rest of today.
        _capDay = istDayKey();
        notifyListeners();
        return 0;
      }
      // Paid now or earlier: either way it's watched for coin purposes.
      _watched.add(videoId);
      unawaited(_persistWatched());
      notifyListeners();
      return awarded > 0 ? awarded : 0;
    } on BackendException catch (e) {
      final code = e.statusCode;
      if (code != 401) debugPrint('VideoService: reward failed: ${e.message}');
      // 4xx (login required, bad id) won't succeed on retry; offline / 5xx might.
      return code != null && code >= 400 && code < 500 ? 0 : null;
    } catch (e) {
      debugPrint('VideoService: reward failed: $e');
      return null;
    } finally {
      _rewardInFlight.remove(videoId);
    }
  }
}
