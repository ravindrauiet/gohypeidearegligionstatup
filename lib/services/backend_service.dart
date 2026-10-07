import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// Error raised by BackendService methods that cannot express failure via a
/// nullable return value (e.g. methods returning a non-null List).
class BackendException implements Exception {
  final String message;
  final int? statusCode;

  const BackendException(this.message, {this.statusCode});

  @override
  String toString() => message;
}

class _ForecastCacheEntry {
  final Map<String, dynamic> data;
  final DateTime at;
  const _ForecastCacheEntry(this.data, this.at);
}

/// Result of a single HTTP call to the backend.
class _ApiResult {
  final int? statusCode;
  final dynamic data;
  final String? error;
  final Map<String, String> headers;

  const _ApiResult({this.statusCode, this.data, this.error, this.headers = const {}});

  bool get ok => statusCode != null && statusCode! >= 200 && statusCode! < 300;
  bool get reachedServer => statusCode != null;

  Map<String, dynamic>? get map => data is Map ? Map<String, dynamic>.from(data as Map) : null;
}

class BackendService extends ChangeNotifier {
  /// Override with `--dart-define=API_BASE_URL=http://10.0.2.2:5000/api` (no trailing slash).
  static const String _configuredBaseUrl = String.fromEnvironment('API_BASE_URL');

  // Candidate base URLs (production first, then local development servers).
  static const List<String> candidateUrls = [
    'https://gohypeidearegligionstatup.vercel.app/api',
    'http://localhost:5000/api',
    'http://127.0.0.1:5000/api',
    'http://10.0.2.2:5000/api',
  ];

  static const Duration _defaultTimeout = Duration(seconds: 15);
  static const Duration _aiTimeout = Duration(seconds: 90);
  static const Duration _forecastTimeout = Duration(seconds: 45);
  static const Duration _forecastCacheTtl = Duration(minutes: 10);

  // SharedPreferences keys owned by this service
  static const String _kAuthToken = 'auth_token';
  static const String _kUserData = 'user_data';
  static const String _kKundliData = 'kundli_data';
  static const String _kGuestToken = 'guest_token';
  static const String _kPanditToken = 'pandit_token';
  static const String _kPanditProfile = 'pandit_profile';

  String _currentBaseUrl =
      _configuredBaseUrl.isNotEmpty ? _configuredBaseUrl : candidateUrls.first;
  String get currentBaseUrl => _currentBaseUrl;

  String? _token;
  String? _guestToken;
  Map<String, dynamic>? _user;
  Map<String, dynamic>? _kundliData;
  bool _isLoading = false;
  String? _lastError;

  String? get token => _token;
  Map<String, dynamic>? get user => _user;
  Map<String, dynamic>? get kundliData => _kundliData;
  bool get isLoading => _isLoading;
  bool get isAuthenticated => _token != null && _token!.isNotEmpty;
  bool get isGuestSession => !isAuthenticated && _guestToken != null;

  /// Human-readable message describing the most recent failed request (null after a success).
  String? get lastError => _lastError;

  String? _lastErrorCode;

  /// Machine-readable `code` from the most recent failed response body
  /// (e.g. `NO_KUNDLI`), or null after a success / when none was sent.
  String? get lastErrorCode => _lastErrorCode;

  final Completer<void> _readyCompleter = Completer<void>();

  /// Completes once the persisted session has been restored (and, when a user token
  /// exists without a cached Kundli, after one attempt to fetch it from the server).
  Future<void> get ready => _readyCompleter.future;

  BackendService() {
    _init();
  }

  Future<void> _init() async {
    try {
      await _loadStoredSession();
      if (isAuthenticated && _kundliData == null) {
        await refreshUserSession(timeout: const Duration(seconds: 6));
      }
    } catch (e) {
      debugPrint('Session restore failed: $e');
    } finally {
      if (!_readyCompleter.isCompleted) _readyCompleter.complete();
    }
    if (_panditToken != null) {
      unawaited(refreshPanditProfile());
    }
  }

  // ---------------------------------------------------------------------------
  // Persistence helpers
  // ---------------------------------------------------------------------------

  static Map<String, dynamic>? _decodeMap(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = json.decode(raw);
      return decoded is Map ? Map<String, dynamic>.from(decoded) : null;
    } catch (_) {
      return null;
    }
  }

  static Map<String, dynamic>? _asMap(dynamic v) =>
      v is Map ? Map<String, dynamic>.from(v) : null;

  static List<Map<String, dynamic>> _asMapList(dynamic v) {
    if (v is! List) return [];
    return v.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
  }

  Future<void> _loadStoredSession() async {
    final prefs = await SharedPreferences.getInstance();
    _token = prefs.getString(_kAuthToken);
    if (_token != null && _token!.isEmpty) _token = null;
    _guestToken = prefs.getString(_kGuestToken);
    _user = _decodeMap(prefs.getString(_kUserData));
    _kundliData = _decodeMap(prefs.getString(_kKundliData));
    _panditToken = prefs.getString(_kPanditToken);
    _panditProfile = _decodeMap(prefs.getString(_kPanditProfile));
    if (_panditToken == null) _panditProfile = null;
    notifyListeners();
  }

  Future<void> _saveSession(String token, Map<String, dynamic>? userData) async {
    clearForecastCache();
    _token = token;
    _user = userData;
    _guestToken = null; // a real account supersedes any guest session
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kAuthToken, token);
    if (userData != null) {
      await prefs.setString(_kUserData, json.encode(userData));
    } else {
      await prefs.remove(_kUserData);
    }
    await prefs.remove(_kGuestToken);
    notifyListeners();
  }

  Future<void> _setKundli(Map<String, dynamic>? kundli) async {
    // A new / regenerated chart makes every cached forecast stale.
    if (_kundliIdentity(kundli) != _kundliIdentity(_kundliData)) clearForecastCache();
    _kundliData = kundli;
    final prefs = await SharedPreferences.getInstance();
    if (kundli != null) {
      await prefs.setString(_kKundliData, json.encode(kundli));
    } else {
      await prefs.remove(_kKundliData);
    }
  }

  Future<void> _storeGuestToken(String guestToken) async {
    if (isAuthenticated) return;
    _guestToken = guestToken;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kGuestToken, guestToken);
  }

  Future<void> _clearUserSession({bool notify = true}) async {
    clearForecastCache();
    _token = null;
    _guestToken = null;
    _user = null;
    _kundliData = null;
    _familyMembers = [];
    _selectedFamilyMember = null;
    _walletBalance = 0.0;
    final prefs = await SharedPreferences.getInstance();
    for (final key in [_kAuthToken, _kUserData, _kKundliData, _kGuestToken]) {
      await prefs.remove(key);
    }
    if (notify) notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // HTTP core
  // ---------------------------------------------------------------------------

  List<String> get _baseUrlOrder {
    if (_configuredBaseUrl.isNotEmpty) return [_configuredBaseUrl];
    return [_currentBaseUrl, ...candidateUrls.where((u) => u != _currentBaseUrl)];
  }

  static String _messageFrom(dynamic data, int status) {
    if (data is Map) {
      final msg = data['message'] ?? data['error'];
      if (msg is String && msg.trim().isNotEmpty) return msg;
    }
    if (status == 401) return 'Please log in to continue.';
    if (status == 403) return 'You are not allowed to perform this action.';
    if (status == 404) return 'The requested item was not found.';
    if (status >= 500) return 'The server ran into a problem. Please try again shortly.';
    return 'Request failed (HTTP $status).';
  }

  /// Sends a request. Fails over to the next candidate base URL ONLY when the
  /// server could not be reached; a timeout after the request was sent is not
  /// retried (it may already have been processed, e.g. a saved chat message).
  Future<_ApiResult> _request(
    String method,
    String path, {
    Map<String, dynamic>? body,
    Duration timeout = _defaultTimeout,
    bool usePanditToken = false,
    bool allowGuestRetry = true,
  }) async {
    final headers = <String, String>{'Accept': 'application/json'};
    if (body != null) headers['Content-Type'] = 'application/json';
    final authToken = usePanditToken ? _panditToken : (_token ?? _guestToken);
    if (authToken != null && authToken.isNotEmpty) {
      headers['Authorization'] = 'Bearer $authToken';
    }
    final encodedBody = body != null ? json.encode(body) : null;

    String? connectionError;
    for (final baseUrl in _baseUrlOrder) {
      final uri = Uri.parse('$baseUrl$path');
      http.Response response;
      try {
        switch (method) {
          case 'GET':
            response = await http.get(uri, headers: headers).timeout(timeout);
            break;
          case 'DELETE':
            response = await http.delete(uri, headers: headers).timeout(timeout);
            break;
          case 'PUT':
            response = await http.put(uri, headers: headers, body: encodedBody).timeout(timeout);
            break;
          default:
            response = await http.post(uri, headers: headers, body: encodedBody).timeout(timeout);
        }
      } on TimeoutException {
        _lastError = 'The server is taking too long to respond. Please try again.';
        _lastErrorCode = null;
        debugPrint('Request timed out: $method $uri');
        return _ApiResult(error: _lastError);
      } on http.ClientException catch (e) {
        connectionError = e.message;
        debugPrint('Cannot reach $uri (${e.message}); trying next server...');
        continue;
      } catch (e) {
        connectionError = e.toString();
        debugPrint('Request error for $uri: $e; trying next server...');
        continue;
      }

      _currentBaseUrl = baseUrl;

      dynamic data;
      if (response.body.isNotEmpty) {
        try {
          data = json.decode(utf8.decode(response.bodyBytes));
        } catch (_) {
          data = null;
        }
      }

      final guestHeader = response.headers['x-guest-token'];
      if (guestHeader != null && guestHeader.isNotEmpty) {
        await _storeGuestToken(guestHeader);
      }

      final status = response.statusCode;
      if (status >= 200 && status < 300) {
        _lastError = null;
        _lastErrorCode = null;
        return _ApiResult(statusCode: status, data: data, headers: response.headers);
      }

      // Expired / invalid credentials
      final tokenRejected = status == 401 &&
          data is Map &&
          data['error'] is String &&
          (data['error'] as String).toLowerCase().contains('token');
      if (tokenRejected && authToken != null) {
        if (usePanditToken) {
          await _clearPanditSession();
        } else if (authToken == _token) {
          await _clearUserSession();
          _lastError = 'Your session has expired. Please log in again.';
          return _ApiResult(statusCode: status, data: data, error: _lastError);
        } else if (authToken == _guestToken && allowGuestRetry) {
          // Stale guest session: drop it and retry once with a fresh guest session
          _guestToken = null;
          final prefs = await SharedPreferences.getInstance();
          await prefs.remove(_kGuestToken);
          return _request(method, path,
              body: body, timeout: timeout, usePanditToken: usePanditToken, allowGuestRetry: false);
        }
      }

      _lastError = _messageFrom(data, status);
      _lastErrorCode = (data is Map && data['code'] is String) ? data['code'] as String : null;
      return _ApiResult(statusCode: status, data: data, error: _lastError, headers: response.headers);
    }

    _lastError = 'Unable to connect to the server. Please check your internet connection.';
    _lastErrorCode = null;
    debugPrint('All backend URLs failed for $method $path: $connectionError');
    return _ApiResult(error: _lastError);
  }

  Future<_ApiResult> _get(String path, {Duration timeout = _defaultTimeout, bool usePanditToken = false}) =>
      _request('GET', path, timeout: timeout, usePanditToken: usePanditToken);

  Future<_ApiResult> _post(String path, Map<String, dynamic> body,
          {Duration timeout = _defaultTimeout, bool usePanditToken = false}) =>
      _request('POST', path, body: body, timeout: timeout, usePanditToken: usePanditToken);

  void _setLoading(bool value) {
    _isLoading = value;
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // Auth
  // ---------------------------------------------------------------------------

  Future<void> _applyAuthResponse(Map<String, dynamic> data) async {
    await _saveSession(data['token'] as String, _asMap(data['user']));
    // Always replace the cached chart: a different account must not inherit it.
    await _setKundli(_asMap(data['kundli']));
    _familyMembers = [];
    _selectedFamilyMember = null;
  }

  /// Registers a user. Returns false on failure; see [lastError] for the reason.
  Future<bool> register(String fullName, String email, String password, {String gender = 'Not Specified'}) async {
    _setLoading(true);
    try {
      final res = await _post('/auth/register', {
        'fullName': fullName,
        'email': email,
        'password': password,
        'gender': gender,
      });
      final data = res.map;
      if (res.ok && data != null && data['token'] is String) {
        await _applyAuthResponse(data);
        return true;
      }
      _lastError ??= 'Registration failed. Please try again.';
      return false;
    } finally {
      _setLoading(false);
    }
  }

  bool get hasBirthDetails => _kundliData != null && _kundliData!['ascendant'] != null;

  /// Logs in (unknown emails are registered automatically by the backend).
  /// Returns false on failure; see [lastError] for the reason.
  Future<bool> login(String email, String password) async {
    _setLoading(true);
    try {
      final res = await _post('/auth/login', {
        'email': email,
        'password': password,
      });
      final data = res.map;
      if (res.ok && data != null && data['token'] is String) {
        await _applyAuthResponse(data);
        return true;
      }
      _lastError ??= 'Login failed. Please try again.';
      return false;
    } finally {
      _setLoading(false);
    }
  }

  /// Re-fetches the signed-in user's profile and saved Kundli (GET /auth/me).
  Future<bool> refreshUserSession({Duration timeout = _defaultTimeout}) async {
    if (!isAuthenticated) return false;
    final res = await _get('/auth/me', timeout: timeout);
    final data = res.map;
    if (!res.ok || data == null) return false;
    final user = _asMap(data['user']);
    if (user != null) {
      _user = user;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kUserData, json.encode(user));
    }
    await _setKundli(_asMap(data['kundli']));
    final wb = user?['walletBalance'];
    if (wb is num) _walletBalance = wb.toDouble();
    notifyListeners();
    return true;
  }

  /// Fetches the user's saved Kundli (GET /kundli). Returns null if none / on failure.
  Future<Map<String, dynamic>?> fetchMyKundli() async {
    if (!isAuthenticated && _guestToken == null) return null;
    final res = await _get('/kundli');
    final kundli = res.ok ? _asMap(res.map?['kundli']) : null;
    if (kundli != null) {
      await _setKundli(kundli);
      notifyListeners();
    }
    return kundli;
  }

  /// Logs out the user AND any Pandit session. Only session keys are removed
  /// from SharedPreferences (app flags such as onboarding_seen are kept).
  Future<void> logout() async {
    await _clearPanditSession(notify: false);
    await _clearUserSession(notify: false);
    _lastError = null;
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // Kundli
  // ---------------------------------------------------------------------------

  /// Generates & saves the user's Kundli. Returns null on failure (see [lastError]);
  /// nothing is cached in that case.
  ///
  /// Leave [timezone] null: the backend derives it from the birth place
  /// coordinates. Pass [birthTimeKnown] false when [timeOfBirth] is only a
  /// guess, so the chart is flagged and its Lagna is not shown as exact.
  Future<Map<String, dynamic>?> generateKundli({
    required String fullName,
    required String gender,
    required String dateOfBirth,
    required String timeOfBirth,
    required String placeOfBirth,
    double? latitude,
    double? longitude,
    String? timezone,
    bool birthTimeKnown = true,
  }) async {
    _setLoading(true);
    try {
      final res = await _post(
        '/kundli/generate',
        {
          'fullName': fullName,
          'gender': gender,
          'dateOfBirth': dateOfBirth,
          'timeOfBirth': timeOfBirth,
          'placeOfBirth': placeOfBirth,
          if (latitude != null) 'latitude': latitude,
          if (longitude != null) 'longitude': longitude,
          if (timezone != null) 'timezone': timezone,
          'birthTimeKnown': birthTimeKnown,
        },
        timeout: _aiTimeout,
      );
      final kundli = res.ok ? _asMap(res.map?['kundli']) : null;
      if (kundli == null) {
        _lastError ??= 'Could not generate your Kundli. Please try again.';
        return null;
      }
      await _setKundli(kundli);
      return kundli;
    } finally {
      _setLoading(false);
    }
  }

  /// AI interpretation for a computed Kundli. Returns null on failure.
  Future<String?> fetchAIKundliReport(Map<String, dynamic> kundli, {Map<String, dynamic>? birthDetails}) async {
    final res = await _post(
      '/kundli/ai-report',
      {
        'kundli': kundli,
        if (birthDetails != null) 'birthDetails': birthDetails,
      },
      timeout: _aiTimeout,
    );
    final report = res.ok ? (res.map?['aiReport']) : null;
    return report is String ? report : null;
  }

  // ---------------------------------------------------------------------------
  // AI chat
  // ---------------------------------------------------------------------------

  /// Sends a message to the AI astrologer. Returns the reply, or null on failure
  /// (see [lastError]).
  Future<String?> sendChatMessage(
    String message, {
    String? astrologerName,
    String? specialty,
    String? field,
  }) async {
    final res = await _post(
      '/chat',
      {
        'message': message,
        if (astrologerName != null) 'astrologerName': astrologerName,
        if (specialty != null) 'specialty': specialty,
        if (field != null) 'field': field,
      },
      timeout: _aiTimeout,
    );
    final content = res.ok ? (res.map?['content']) : null;
    if (content is String && content.trim().isNotEmpty) return content;
    _lastError ??= 'The astrologer could not respond right now. Please try again.';
    return null;
  }

  /// Chat history for an astrologer. Throws [BackendException] on failure.
  Future<List<Map<String, dynamic>>> fetchChatHistory({String? astrologerName}) async {
    final query = (astrologerName != null && astrologerName.isNotEmpty)
        ? '?astrologerName=${Uri.encodeQueryComponent(astrologerName)}'
        : '';
    final res = await _get('/chat/history$query');
    if (!res.ok) throw BackendException(res.error ?? 'Failed to load chat history', statusCode: res.statusCode);
    return _asMapList(res.map?['history']);
  }

  // ---------------------------------------------------------------------------
  // Horoscope / Panchang
  // ---------------------------------------------------------------------------

  Future<Map<String, dynamic>?> fetchMoonshine() async {
    final res = await _get('/horoscope/moonshine');
    return res.ok ? res.map : null;
  }

  Future<List<Map<String, dynamic>>> fetchStarTalkPosts() async {
    final res = await _get('/horoscope/star-talk');
    return res.ok ? _asMapList(res.map?['posts']) : [];
  }

  /// Current planetary hour (Hora) for New Delhi by default.
  Future<Map<String, dynamic>?> fetchCurrentHora({double? latitude, double? longitude, String? timezone}) async {
    final q = _locationQuery(latitude, longitude, timezone);
    final res = await _get('/horoscope/hora$q');
    return res.ok ? res.map : null;
  }

  Future<Map<String, dynamic>?> fetchAstroPulseToday() async {
    final res = await _post('/horoscope/astropulse', {}, timeout: const Duration(seconds: 45));
    return res.ok ? res.map : null;
  }

  /// Today's Panchang & Muhurats (New Delhi / IST unless a location is given).
  Future<Map<String, dynamic>?> fetchPanchangToday({DateTime? date, double? latitude, double? longitude, String? timezone}) async {
    var q = _locationQuery(latitude, longitude, timezone);
    if (date != null) {
      final d = '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
      q = '${q.isEmpty ? '?' : '$q&'}date=$d';
    }
    final res = await _get('/horoscope/panchang$q');
    return res.ok ? res.map : null;
  }

  static String _locationQuery(double? lat, double? lng, String? tz) {
    final params = <String>[
      if (lat != null) 'lat=$lat',
      if (lng != null) 'lng=$lng',
      if (tz != null) 'tz=${Uri.encodeQueryComponent(tz)}',
    ];
    return params.isEmpty ? '' : '?${params.join('&')}';
  }

  /// Ashtakoot Guna Milan between the user's saved chart and a partner.
  /// Returns null on failure (e.g. the user has no Kundli yet; see [lastError]).
  Future<Map<String, dynamic>?> fetchSynastryMatch({
    required String partnerName,
    String? partnerGender,
    String? partnerDob,
    String? partnerTob,
    String? partnerPob,
    double? partnerLatitude,
    double? partnerLongitude,
    String? partnerTimezone,
  }) async {
    final res = await _post(
      '/horoscope/synastry',
      {
        'partnerName': partnerName,
        if (partnerGender != null) 'partnerGender': partnerGender,
        if (partnerDob != null) 'partnerDob': partnerDob,
        if (partnerTob != null) 'partnerTob': partnerTob,
        if (partnerPob != null) 'partnerPob': partnerPob,
        if (partnerLatitude != null) 'partnerLatitude': partnerLatitude,
        if (partnerLongitude != null) 'partnerLongitude': partnerLongitude,
        if (partnerTimezone != null) 'partnerTimezone': partnerTimezone,
      },
      timeout: _aiTimeout,
    );
    return res.ok ? res.map : null;
  }

  // ---------------------------------------------------------------------------
  // Family Kundlis
  // ---------------------------------------------------------------------------

  List<Map<String, dynamic>> _familyMembers = [];
  Map<String, dynamic>? _selectedFamilyMember;

  List<Map<String, dynamic>> get familyMembers => _familyMembers;
  Map<String, dynamic>? get selectedFamilyMember => _selectedFamilyMember;

  void selectFamilyMember(Map<String, dynamic>? member) {
    if (member?['id'] != _selectedFamilyMember?['id']) clearForecastCache();
    _selectedFamilyMember = member;
    notifyListeners();
  }

  /// Refreshes [familyMembers]. Returns null on failure (cached list is kept).
  Future<List<Map<String, dynamic>>?> fetchFamilyKundlis() async {
    final res = await _get('/kundli/family/list');
    if (!res.ok) return null;
    _familyMembers = _asMapList(res.map?['familyMembers']);
    final selectedId = _selectedFamilyMember?['id'];
    if (selectedId != null) {
      final match = _familyMembers.where((m) => m['id'] == selectedId);
      _selectedFamilyMember = match.isEmpty ? null : match.first;
    }
    notifyListeners();
    return _familyMembers;
  }

  /// Adds a family member (chart computed server-side). Returns the member or null on failure.
  Future<Map<String, dynamic>?> addFamilyKundli({
    required String relationship,
    required String fullName,
    required String dateOfBirth,
    required String timeOfBirth,
    required String placeOfBirth,
    String gender = 'Not Specified',
    double? latitude,
    double? longitude,
    String? timezone,
    bool birthTimeKnown = true,
  }) async {
    final res = await _post(
      '/kundli/family/add',
      {
        'relationship': relationship,
        'fullName': fullName,
        'gender': gender,
        'dateOfBirth': dateOfBirth,
        'timeOfBirth': timeOfBirth,
        'placeOfBirth': placeOfBirth,
        if (latitude != null) 'latitude': latitude,
        if (longitude != null) 'longitude': longitude,
        if (timezone != null) 'timezone': timezone,
        'birthTimeKnown': birthTimeKnown,
      },
      timeout: _aiTimeout,
    );
    final member = res.ok ? _asMap(res.map?['familyMember']) : null;
    if (member != null) await fetchFamilyKundlis();
    return member;
  }

  /// Updates a family member (only non-null fields are sent). Returns the member or null.
  Future<Map<String, dynamic>?> updateFamilyKundli(
    int id, {
    String? relationship,
    String? fullName,
    String? gender,
    String? dateOfBirth,
    String? timeOfBirth,
    String? placeOfBirth,
    double? latitude,
    double? longitude,
    String? timezone,
    bool? birthTimeKnown,
  }) async {
    final res = await _request(
      'PUT',
      '/kundli/family/$id',
      body: {
        if (relationship != null) 'relationship': relationship,
        if (fullName != null) 'fullName': fullName,
        if (gender != null) 'gender': gender,
        if (dateOfBirth != null) 'dateOfBirth': dateOfBirth,
        if (timeOfBirth != null) 'timeOfBirth': timeOfBirth,
        if (placeOfBirth != null) 'placeOfBirth': placeOfBirth,
        if (latitude != null) 'latitude': latitude,
        if (longitude != null) 'longitude': longitude,
        if (timezone != null) 'timezone': timezone,
        if (birthTimeKnown != null) 'birthTimeKnown': birthTimeKnown,
      },
      timeout: _aiTimeout,
    );
    final member = res.ok ? _asMap(res.map?['familyMember']) : null;
    if (member != null) {
      _invalidateForecastProfile(id);
      await fetchFamilyKundlis();
    }
    return member;
  }

  Future<bool> deleteFamilyKundli(int id) async {
    final res = await _request('DELETE', '/kundli/family/$id');
    if (!res.ok) return false;
    _invalidateForecastProfile(id);
    if (_selectedFamilyMember?['id'] == id) _selectedFamilyMember = null;
    await fetchFamilyKundlis();
    return true;
  }

  // ---------------------------------------------------------------------------
  // Personal forecast (day / week / month / life timeline)
  // ---------------------------------------------------------------------------

  final Map<String, _ForecastCacheEntry> _forecastCache = {};

  static String _kundliIdentity(Map<String, dynamic>? k) {
    if (k == null) return '';
    final b = _asMap(k['birthDetails']) ?? const {};
    return '${k['ascendant']}|${k['moonSign']}|${b['dateOfBirth']}|${b['timeOfBirth']}|${b['placeOfBirth']}';
  }

  static String _ymd(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  static DateTime _mondayOf(DateTime d) =>
      DateTime(d.year, d.month, d.day).subtract(Duration(days: d.weekday - DateTime.monday));

  /// Drops every cached forecast (logout, profile switch, chart regeneration).
  void clearForecastCache() => _forecastCache.clear();

  void _invalidateForecastProfile(int familyId) =>
      _forecastCache.removeWhere((key, _) => key.endsWith('|fam:$familyId'));

  /// Shared GET for the forecast endpoints. Returns the payload or null (see
  /// [lastError]); [lastErrorCode] is `NO_KUNDLI` when the profile has no chart.
  /// Only "current" periods are cached ([cacheable]) for [_forecastCacheTtl].
  Future<Map<String, dynamic>?> _fetchForecast(
    String type,
    String period,
    Map<String, String> query, {
    int? familyId,
    required bool cacheable,
    bool forceRefresh = false,
  }) async {
    final key = '$type|$period|${familyId == null ? 'self' : 'fam:$familyId'}';
    if (cacheable && !forceRefresh) {
      final hit = _forecastCache[key];
      if (hit != null && DateTime.now().difference(hit.at) < _forecastCacheTtl) {
        _lastError = null;
        _lastErrorCode = null;
        return hit.data;
      }
    }
    final params = {...query, if (familyId != null) 'familyId': '$familyId'};
    final q = params.isEmpty
        ? ''
        : '?${params.entries.map((e) => '${e.key}=${Uri.encodeQueryComponent(e.value)}').join('&')}';
    final res = await _get('/forecast/$type$q', timeout: _forecastTimeout);
    final data = res.ok ? res.map : null;
    if (data == null) {
      if (res.ok) {
        _lastError = 'Received an unexpected response. Please try again.';
        _lastErrorCode = null;
      } else if (res.statusCode == 409 && _lastErrorCode == null) {
        _lastErrorCode = 'NO_KUNDLI';
      }
      _lastError ??= 'Could not load your forecast. Please try again.';
      return null;
    }
    if (cacheable) _forecastCache[key] = _ForecastCacheEntry(data, DateTime.now());
    return data;
  }

  /// Personal forecast for one day (default today). Null on failure.
  Future<Map<String, dynamic>?> fetchDayForecast({DateTime? date, int? familyId, bool forceRefresh = false}) {
    final today = _ymd(DateTime.now());
    final d = date != null ? _ymd(date) : today;
    return _fetchForecast('day', d, {if (date != null) 'date': d},
        familyId: familyId, cacheable: d == today, forceRefresh: forceRefresh);
  }

  /// Personal forecast for the Monday-based week containing [weekStart] (default this week).
  Future<Map<String, dynamic>?> fetchWeekForecast({DateTime? weekStart, int? familyId, bool forceRefresh = false}) {
    final current = _ymd(_mondayOf(DateTime.now()));
    final w = weekStart != null ? _ymd(_mondayOf(weekStart)) : current;
    return _fetchForecast('week', w, {if (weekStart != null) 'start': w},
        familyId: familyId, cacheable: w == current, forceRefresh: forceRefresh);
  }

  /// Personal forecast for a calendar month (default this month).
  Future<Map<String, dynamic>?> fetchMonthForecast({DateTime? month, int? familyId, bool forceRefresh = false}) {
    String ym(DateTime d) => '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}';
    final current = ym(DateTime.now());
    final m = month != null ? ym(month) : current;
    return _fetchForecast('month', m, {if (month != null) 'month': m},
        familyId: familyId, cacheable: m == current, forceRefresh: forceRefresh);
  }

  /// Major life periods (Sade Sati, slow transits, dashas). Server defaults:
  /// from today − 2y, 6 years. Only the default window is cached.
  Future<Map<String, dynamic>?> fetchLifeTimeline({
    int? familyId,
    DateTime? from,
    int? years,
    bool forceRefresh = false,
  }) {
    final isDefault = from == null && years == null;
    return _fetchForecast(
      'timeline',
      isDefault ? 'default:${_ymd(DateTime.now())}' : '${from == null ? '' : _ymd(from)}:${years ?? ''}',
      {
        if (from != null) 'from': _ymd(from),
        if (years != null) 'years': '${years.clamp(1, 30)}',
      },
      familyId: familyId,
      cacheable: isDefault,
      forceRefresh: forceRefresh,
    );
  }

  // ---------------------------------------------------------------------------
  // Pandit account (uses the separate Pandit token)
  // ---------------------------------------------------------------------------

  String? _panditToken;
  Map<String, dynamic>? _panditProfile;
  Map<String, dynamic>? get panditProfile => _panditProfile;
  Map<String, dynamic>? get currentPandit => _panditProfile;
  bool get isPanditLoggedIn => _panditToken != null && _panditToken!.isNotEmpty;

  Future<void> _savePanditSession(String token, Map<String, dynamic>? profile) async {
    _panditToken = token;
    _panditProfile = profile;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kPanditToken, token);
    if (profile != null) {
      await prefs.setString(_kPanditProfile, json.encode(profile));
    }
    notifyListeners();
  }

  Future<void> _savePanditProfile(Map<String, dynamic>? profile) async {
    if (profile == null) return;
    _panditProfile = profile;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kPanditProfile, json.encode(profile));
    notifyListeners();
  }

  Future<void> _clearPanditSession({bool notify = true}) async {
    _panditToken = null;
    _panditProfile = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kPanditToken);
    await prefs.remove(_kPanditProfile);
    if (notify) notifyListeners();
  }

  /// Returns the Pandit profile, or null on failure (see [lastError]).
  Future<Map<String, dynamic>?> loginPandit({
    required String email,
    required String password,
  }) async {
    final res = await _post('/pandit/login', {
      'email': email,
      'password': password,
    });
    final data = res.map;
    if (res.ok && data != null && data['token'] is String) {
      await _savePanditSession(data['token'] as String, _asMap(data['pandit']));
      return _panditProfile;
    }
    _lastError ??= 'Pandit login failed. Please try again.';
    return null;
  }

  /// Returns the new Pandit profile; on a known failure returns
  /// `{'error': CODE, 'message': text}` (e.g. PANDIT_ALREADY_EXISTS, INVALID_PASSWORD);
  /// returns null when the server could not be reached.
  Future<Map<String, dynamic>?> registerPanditAccount({
    required String email,
    required String password,
    required String fullName,
    required String specialty,
    required String field,
    required int experienceYears,
    required String languages,
    required double ratePerMin,
    required String bio,
    String? avatarUrl,
  }) async {
    final res = await _post('/pandit/register', {
      'email': email,
      'password': password,
      'fullName': fullName,
      'specialty': specialty,
      'field': field,
      'experienceYears': experienceYears,
      'languages': languages,
      'ratePerMin': ratePerMin,
      'bio': bio,
      if (avatarUrl != null) 'avatarUrl': avatarUrl,
    });
    final data = res.map;
    if (res.ok && data != null && data['token'] is String) {
      await _savePanditSession(data['token'] as String, _asMap(data['pandit']));
      return _panditProfile;
    }
    if (res.reachedServer) {
      return {
        'error': (data?['error'] ?? 'REGISTRATION_FAILED').toString(),
        'message': res.error ?? 'Registration failed.',
      };
    }
    return null;
  }

  /// Reloads the Pandit profile (GET /pandit/me). Returns null on failure.
  Future<Map<String, dynamic>?> refreshPanditProfile() async {
    if (!isPanditLoggedIn) return null;
    final res = await _get('/pandit/me', usePanditToken: true);
    if (res.statusCode == 403 || res.statusCode == 404) {
      await _clearPanditSession();
      return null;
    }
    final profile = res.ok ? _asMap(res.map?['pandit']) : null;
    if (profile != null) await _savePanditProfile(profile);
    return profile;
  }

  Future<void> logoutPandit() async {
    await _clearPanditSession();
  }

  /// Registered human Pandits. Throws [BackendException] on failure.
  Future<List<Map<String, dynamic>>> fetchPanditsList() async {
    final res = await _get('/pandit/list');
    if (!res.ok) throw BackendException(res.error ?? 'Failed to load Pandits', statusCode: res.statusCode);
    return _asMapList(res.map?['pandits']);
  }

  /// Pandit toggles Online/Busy status (requires Pandit login).
  Future<bool> togglePanditStatus({bool? isOnline, bool? isBusy}) async {
    if (!isPanditLoggedIn) {
      _lastError = 'Please log in as a Pandit first.';
      return false;
    }
    final res = await _post(
      '/pandit/toggle-status',
      {
        if (isOnline != null) 'isOnline': isOnline,
        if (isBusy != null) 'isBusy': isBusy,
      },
      usePanditToken: true,
    );
    final profile = res.ok ? _asMap(res.map?['pandit']) : null;
    if (profile == null) return false;
    await _savePanditProfile(profile);
    return true;
  }

  // ---------------------------------------------------------------------------
  // Consultations
  // ---------------------------------------------------------------------------

  /// Seeker requests a consultation. Returns the response map
  /// (`status`: active | waiting) or, for a known refusal, a map with `error`
  /// (INSUFFICIENT_BALANCE, PANDIT_OFFLINE, ...) and `message`; null if unreachable.
  Future<Map<String, dynamic>?> requestConsultation({
    required dynamic panditId,
    String? userName,
  }) async {
    final res = await _post('/pandit/request', {
      'panditId': panditId is String ? int.tryParse(panditId) ?? panditId : panditId,
      'userName': userName ??
          _kundliData?['birthDetails']?['fullName'] ??
          _user?['fullName'] ??
          'Seeker',
    });
    if (res.ok) return res.map;
    return res.reachedServer ? (res.map ?? {'error': res.error, 'message': res.error}) : null;
  }

  /// With [panditId]: the Pandit's own queue (requires Pandit login).
  /// Without: the seeker's current consultation status.
  Future<Map<String, dynamic>?> fetchQueueStatus({dynamic panditId}) async {
    final path = panditId != null ? '/pandit/queue-status?panditId=$panditId' : '/pandit/queue-status';
    final res = await _get(path, usePanditToken: panditId != null);
    return res.ok ? res.map : null;
  }

  /// Pandit completes the active session (billed server-side) and starts the next one.
  Future<Map<String, dynamic>?> nextConsultation(dynamic panditId) async {
    final res = await _post('/pandit/next', {'panditId': panditId}, usePanditToken: true);
    return res.ok ? res.map : null;
  }

  /// Seeker leaves the waiting queue or ends their live consultation.
  /// [sessionId] defaults to the seeker's current session. Returns the response or null.
  Future<Map<String, dynamic>?> cancelConsultation({int? sessionId}) async {
    final res = await _post('/pandit/cancel', {if (sessionId != null) 'sessionId': sessionId});
    if (res.ok) {
      final billing = _asMap(res.map?['billing']);
      final bal = billing?['seekerBalance'];
      if (bal is num) {
        _walletBalance = bal.toDouble();
        notifyListeners();
      }
    }
    return res.ok ? res.map : null;
  }

  /// Either participant ends a session; unbilled minutes are charged server-side.
  /// Set [asPandit] when called from the Pandit side.
  Future<Map<String, dynamic>?> endConsultationSession(int sessionId, {bool asPandit = false}) async {
    final res = await _post('/pandit/session/$sessionId/end', {}, usePanditToken: asPandit);
    if (res.ok && !asPandit) {
      final bal = _asMap(res.map?['billing'])?['seekerBalance'];
      if (bal is num) {
        _walletBalance = bal.toDouble();
        notifyListeners();
      }
    }
    return res.ok ? res.map : null;
  }

  /// Messages of a consultation session newer than [afterId].
  /// Returns `{sessionStatus, role, messages: [{id, sessionId, senderRole, content, isPrescription, createdAt}]}` or null.
  Future<Map<String, dynamic>?> fetchSessionMessages(int sessionId, {int afterId = 0, bool asPandit = false}) async {
    final res = await _get('/pandit/session/$sessionId/messages?afterId=$afterId', usePanditToken: asPandit);
    return res.ok ? res.map : null;
  }

  /// Sends a message in an active consultation session. Returns the saved message or null.
  Future<Map<String, dynamic>?> sendSessionMessage(int sessionId, String content, {bool asPandit = false}) async {
    final res = await _post('/pandit/session/$sessionId/messages', {'content': content}, usePanditToken: asPandit);
    return res.ok ? _asMap(res.map?['message']) : null;
  }

  /// Pandit records a prescription for a session (also posted into the session chat).
  Future<Map<String, dynamic>?> submitPrescription({
    required int sessionId,
    String? gemstone,
    String? mantra,
    String? remedy,
  }) async {
    final res = await _post(
      '/pandit/prescription',
      {
        'sessionId': sessionId,
        if (gemstone != null) 'gemstone': gemstone,
        if (mantra != null) 'mantra': mantra,
        if (remedy != null) 'remedy': remedy,
      },
      usePanditToken: true,
    );
    return res.ok ? _asMap(res.map?['prescription']) : null;
  }

  /// Seeker's Kundli for the Pandit consulting them (or the seeker themself).
  /// Returns null if not permitted / no chart (see [lastError]).
  Future<Map<String, dynamic>?> fetchUserKundliForPandit(dynamic userId) async {
    final res = await _get('/pandit/user-kundli/$userId', usePanditToken: isPanditLoggedIn);
    return res.ok ? res.map : null;
  }

  // ---------------------------------------------------------------------------
  // Wallet
  // ---------------------------------------------------------------------------

  double _walletBalance = 0.0;
  double get walletBalance => _walletBalance;

  /// Returns the current balance, or null on failure (cached [walletBalance] unchanged).
  Future<double?> fetchWalletBalance() async {
    final res = await _get('/pandit/wallet/balance');
    final value = res.ok ? (res.map?['walletBalance']) : null;
    if (value is! num) return null;
    _walletBalance = value.toDouble();
    notifyListeners();
    return _walletBalance;
  }

  Future<double?> rechargeWallet(double amount) async {
    final res = await _post('/pandit/wallet/recharge', {'amount': amount});
    final value = res.ok ? (res.map?['walletBalance']) : null;
    if (value is! num) return null;
    _walletBalance = value.toDouble();
    notifyListeners();
    return _walletBalance;
  }

  /// Wallet ledger: `[{id, type, amount, description, createdAt, panditId, panditName, direction}]`.
  /// Set [asPandit] to include payouts credited to the logged-in Pandit. Returns null on failure.
  Future<List<Map<String, dynamic>>?> fetchWalletTransactions({bool asPandit = false}) async {
    final res = await _get('/pandit/wallet/transactions', usePanditToken: asPandit);
    return res.ok ? _asMapList(res.map?['transactions']) : null;
  }

  // ---------------------------------------------------------------------------
  // Reviews, history, remedies, billing
  // ---------------------------------------------------------------------------

  Future<bool> submitPanditReview({
    required dynamic panditId,
    required double rating,
    required String reviewText,
  }) async {
    final res = await _post('/pandit/rate', {
      'panditId': panditId is String ? int.tryParse(panditId) ?? panditId : panditId,
      'rating': rating,
      'reviewText': reviewText,
      'userName': _kundliData?['birthDetails']?['fullName'] ?? _user?['fullName'] ?? 'Seeker',
    });
    return res.ok;
  }

  Future<Map<String, dynamic>?> fetchConsultationHistory() async {
    final res = await _get('/pandit/history');
    return res.ok ? res.map : null;
  }

  Future<Map<String, dynamic>?> fetchGemstoneRecommendations() async {
    final res = await _get('/pandit/remedies/recommendations');
    return res.ok ? res.map : null;
  }

  /// Bills one minute of the active session at the Pandit's server-side rate.
  /// [ratePerMin] is ignored by the server (kept for compatibility).
  /// Returns the response map (with `error: INSUFFICIENT_BALANCE` when the seeker
  /// cannot pay), an error map for other refusals, or null if unreachable.
  Future<Map<String, dynamic>?> deductConsultationMinute({
    required dynamic panditId,
    double ratePerMin = 5.0,
  }) async {
    final res = await _post(
      '/pandit/consultation/deduct-minute',
      {'panditId': panditId, 'ratePerMin': ratePerMin},
      usePanditToken: isPanditLoggedIn,
    );
    final data = res.map;
    if (data == null) return null;
    if (data['chargedSelf'] == true && data['walletBalance'] is num) {
      _walletBalance = (data['walletBalance'] as num).toDouble();
      notifyListeners();
    }
    return data;
  }
}
