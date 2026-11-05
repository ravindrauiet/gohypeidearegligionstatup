import 'dart:async';

import 'package:flutter/foundation.dart';

import 'backend_service.dart';

/// One row of the in-app notification inbox (`GET /notifications`).
///
/// Parsing is defensive: ids are strings on the backend ("n:34", "b:12") but
/// numbers are tolerated, `data` values are stringified, and odd/missing keys
/// never throw.
@immutable
class InboxNotification {
  final String id;
  final String type;
  final String title;
  final String body;
  final Map<String, dynamic> data;
  final bool read;
  final DateTime? createdAt;

  /// Pagination cursor for `before=`; the backend may send one per item,
  /// otherwise the id is used.
  final String cursor;

  const InboxNotification({
    required this.id,
    required this.type,
    required this.title,
    this.body = '',
    this.data = const {},
    this.read = false,
    this.createdAt,
    String? cursor,
  }) : cursor = cursor ?? id;

  /// Payload for [NotificationRouter.open]: the row's `data` plus its `type`.
  Map<String, dynamic> get routeData => {...data, 'type': type};

  InboxNotification copyWith({bool? read}) => InboxNotification(
        id: id,
        type: type,
        title: title,
        body: body,
        data: data,
        read: read ?? this.read,
        createdAt: createdAt,
        cursor: cursor,
      );

  static String _s(dynamic v) => v == null ? '' : v.toString().trim();

  static bool _b(dynamic v) {
    if (v is bool) return v;
    if (v is num) return v != 0;
    final s = _s(v).toLowerCase();
    return s == 'true' || s == '1';
  }

  /// Returns null for rows without an id.
  static InboxNotification? tryParse(dynamic raw) {
    if (raw is! Map) return null;
    final id = _s(raw['id']);
    if (id.isEmpty) return null;
    final rawData = raw['data'];
    final data = <String, dynamic>{};
    if (rawData is Map) {
      rawData.forEach((k, v) {
        if (v != null) data[k.toString()] = v is String ? v : v.toString();
      });
    }
    var type = _s(raw['type']);
    if (type.isEmpty) type = _s(data['type']);
    if (type.isEmpty) type = 'inbox';
    final cursor = _s(raw['cursor']);
    final created = raw['createdAt'] ?? raw['created_at'];
    return InboxNotification(
      id: id,
      type: type,
      title: _s(raw['title']),
      body: _s(raw['body']),
      data: data,
      read: _b(raw['read'] ?? raw['isRead'] ?? raw['is_read']),
      createdAt: created == null ? null : DateTime.tryParse(created.toString())?.toLocal(),
      cursor: cursor.isEmpty ? null : cursor,
    );
  }
}

/// In-app notification inbox + unread badge.
///
/// Registered users only: for guests / signed-out sessions everything stays
/// empty and no request is made. Cached state is dropped as soon as the
/// signed-in account changes (log in / log out / switch).
class NotificationInboxService extends ChangeNotifier {
  final BackendService backend;

  NotificationInboxService(this.backend) {
    _accountKey = _currentKey;
    backend.addListener(_onBackendChanged);
  }

  static const int pageSize = 30;

  /// [refreshUnread] calls closer together than this are skipped (unless forced).
  static const Duration unreadMinGap = Duration(seconds: 20);

  @visibleForTesting
  DateTime Function() clock = DateTime.now;

  bool _disposed = false;
  late String _accountKey;

  /// Bumped on every reset so late responses for an old account are ignored.
  int _generation = 0;

  List<InboxNotification> _items = const [];
  int _unread = 0;
  bool _loading = false;
  bool _loadingMore = false;
  bool _loaded = false;
  bool _hasMore = false;
  String? _error;
  String? _loadMoreError;

  Future<void>? _refreshFuture;
  Future<void>? _unreadFuture;
  DateTime? _lastUnreadAt;

  List<InboxNotification> get items => _items;
  int get unread => _unread;
  bool get loading => _loading;
  bool get loadingMore => _loadingMore;

  /// True after the first page arrived for the current account.
  bool get loaded => _loaded;
  bool get hasMore => _hasMore;

  /// Error of the last [refresh] (null after a success).
  String? get error => _error;

  /// Error of the last [loadMore] (null after a success).
  String? get loadMoreError => _loadMoreError;

  /// Only registered users have an inbox.
  bool get signedIn => backend.isAuthenticated;

  String get _currentKey => backend.isAuthenticated ? '${backend.user?['id'] ?? backend.token}' : '';

  void _onBackendChanged() {
    if (_disposed || _accountKey == _currentKey) return;
    // Defer: BackendService may notify while widgets are building.
    scheduleMicrotask(() {
      if (_disposed || !_resetIfAccountChanged()) return;
      notifyListeners();
      if (signedIn) unawaited(refreshUnread(force: true));
    });
  }

  bool _resetIfAccountChanged() {
    final key = _currentKey;
    if (key == _accountKey) return false;
    _accountKey = key;
    _generation++;
    _items = const [];
    _unread = 0;
    _loading = false;
    _loadingMore = false;
    _loaded = false;
    _hasMore = false;
    _error = null;
    _loadMoreError = null;
    _refreshFuture = null;
    _unreadFuture = null;
    _lastUnreadAt = null;
    return true;
  }

  static int? _int(dynamic v) {
    if (v is int) return v;
    if (v is num) return v.round();
    return v == null ? null : num.tryParse(v.toString())?.round();
  }

  static String errorText(Object e) {
    if (e is BackendException) {
      if (e.statusCode == 401 || e.statusCode == 403) return 'Please sign in to see your notifications.';
      if (e.statusCode != null && e.statusCode! >= 500) {
        return 'Our server ran into a problem. Please try again shortly.';
      }
      if (e.message.trim().isNotEmpty) return e.message;
    }
    return 'Could not reach the server. Please check your connection.';
  }

  List<InboxNotification> _parseItems(dynamic raw) {
    if (raw is! List) return const [];
    return raw.map(InboxNotification.tryParse).whereType<InboxNotification>().toList();
  }

  void _applyUnread(dynamic v) {
    final n = _int(v);
    if (n != null) _unread = n < 0 ? 0 : n;
  }

  /// Reloads the first page (pull-to-refresh / screen open). Never throws;
  /// failures land in [error]. Concurrent calls share one request.
  Future<void> refresh() {
    if (_disposed) return Future.value();
    _resetIfAccountChanged();
    if (!signedIn) return Future.value();
    final inFlight = _refreshFuture;
    if (inFlight != null) return inFlight;
    final gen = _generation;
    _loading = true;
    _error = null;
    notifyListeners();
    return _refreshFuture = () async {
      try {
        final res = await backend.api('GET', '/notifications?limit=$pageSize');
        if (gen != _generation || _disposed) return;
        _items = _parseItems(res['items']);
        _hasMore = res['hasMore'] == true;
        _applyUnread(res['unread']);
        _lastUnreadAt = clock();
        _loaded = true;
        _loadMoreError = null;
      } catch (e) {
        if (gen != _generation || _disposed) return;
        _error = errorText(e);
      } finally {
        if (gen == _generation) {
          _loading = false;
          _refreshFuture = null;
          notifyListeners();
        }
      }
    }();
  }

  /// Appends the next page (infinite scroll). No-op while loading, when
  /// there is nothing more, or for guests. Never throws.
  Future<void> loadMore() async {
    if (_disposed || !signedIn || !_loaded || !_hasMore || _loading || _loadingMore || _items.isEmpty) return;
    final gen = _generation;
    final before = _items.last.cursor;
    _loadingMore = true;
    _loadMoreError = null;
    notifyListeners();
    try {
      final res = await backend.api(
          'GET', '/notifications?before=${Uri.encodeQueryComponent(before)}&limit=$pageSize');
      if (gen != _generation || _disposed) return;
      final seen = _items.map((n) => n.id).toSet();
      final more = _parseItems(res['items']).where((n) => seen.add(n.id)).toList();
      _items = [..._items, ...more];
      // Stop if the server says so, or if it keeps returning nothing new.
      _hasMore = res['hasMore'] == true && more.isNotEmpty;
      _applyUnread(res['unread']);
    } catch (e) {
      if (gen != _generation || _disposed) return;
      _loadMoreError = errorText(e);
    } finally {
      if (gen == _generation) {
        _loadingMore = false;
        notifyListeners();
      }
    }
  }

  /// Marks one notification read (optimistic; reverted on failure).
  /// Returns true on success (or when it was already read).
  Future<bool> markRead(String id) async {
    if (_disposed || !signedIn) return false;
    final index = _items.indexWhere((n) => n.id == id);
    if (index < 0 || _items[index].read) return index >= 0;
    final gen = _generation;
    _setRead({id}, true);
    if (_unread > 0) _unread--;
    notifyListeners();
    try {
      final res = await backend.api('POST', '/notifications/read', body: {
        'ids': [id]
      });
      if (gen != _generation || _disposed) return false;
      _applyUnread(res['unread']);
      notifyListeners();
      return true;
    } catch (_) {
      if (gen != _generation || _disposed) return false;
      _setRead({id}, false);
      _unread++;
      notifyListeners();
      return false;
    }
  }

  /// Marks everything read (optimistic; reverted on failure). Returns true on success.
  Future<bool> markAllRead() async {
    if (_disposed || !signedIn) return false;
    final gen = _generation;
    final previouslyUnread = _items.where((n) => !n.read).map((n) => n.id).toSet();
    final previousCount = _unread;
    _setRead(previouslyUnread, true);
    _unread = 0;
    notifyListeners();
    try {
      final res = await backend.api('POST', '/notifications/read', body: {'all': true});
      if (gen != _generation || _disposed) return false;
      _applyUnread(res['unread']);
      notifyListeners();
      return true;
    } catch (_) {
      if (gen != _generation || _disposed) return false;
      _setRead(previouslyUnread, false);
      _unread = previousCount;
      notifyListeners();
      return false;
    }
  }

  void _setRead(Set<String> ids, bool read) {
    if (ids.isEmpty) return;
    _items = [for (final n in _items) ids.contains(n.id) ? n.copyWith(read: read) : n];
  }

  /// Refreshes the badge count (`GET /notifications/unread-count`). Cheap:
  /// skipped for guests, de-duplicated while in flight and throttled to one
  /// call per [unreadMinGap] unless [force]. Never throws.
  Future<void> refreshUnread({bool force = false}) {
    if (_disposed) return Future.value();
    _resetIfAccountChanged();
    if (!signedIn) return Future.value();
    final inFlight = _unreadFuture;
    if (inFlight != null) return inFlight;
    final now = clock();
    final last = _lastUnreadAt;
    if (!force && last != null && now.difference(last) < unreadMinGap) return Future.value();
    _lastUnreadAt = now;
    final gen = _generation;
    return _unreadFuture = () async {
      try {
        final res = await backend.api('GET', '/notifications/unread-count');
        if (gen != _generation || _disposed) return;
        final before = _unread;
        _applyUnread(res['unread']);
        if (_unread != before) notifyListeners();
      } catch (_) {
        // Badge is best-effort; keep the last known count.
      } finally {
        if (gen == _generation) _unreadFuture = null;
      }
    }();
  }

  /// Call when a push arrives while the app is open: bumps the badge now and
  /// makes the next inbox open reload.
  void onPushReceived() {
    if (_disposed || !signedIn) return;
    unawaited(refreshUnread(force: true));
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
}
