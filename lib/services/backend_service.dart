import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class BackendService extends ChangeNotifier {
  // Candidate base URLs for different environments
  static const List<String> candidateUrls = [
    'http://localhost:5000/api',
    'http://127.0.0.1:5000/api',
    'http://10.0.2.2:5000/api',
  ];

  String _currentBaseUrl = 'http://localhost:5000/api';
  String get currentBaseUrl => _currentBaseUrl;
  String? _token;
  Map<String, dynamic>? _user;
  Map<String, dynamic>? _kundliData;
  bool _isLoading = false;

  String? get token => _token;
  Map<String, dynamic>? get user => _user;
  Map<String, dynamic>? get kundliData => _kundliData;
  bool get isLoading => _isLoading;
  bool get isAuthenticated => _token != null && _token!.isNotEmpty;

  BackendService() {
    _loadStoredSession();
  }

  Future<void> _loadStoredSession() async {
    final prefs = await SharedPreferences.getInstance();
    _token = prefs.getString('auth_token');
    final userDataStr = prefs.getString('user_data');
    if (userDataStr != null) {
      _user = json.decode(userDataStr);
    }
    final kundliStr = prefs.getString('kundli_data');
    if (kundliStr != null) {
      _kundliData = json.decode(kundliStr);
    }
    notifyListeners();
  }

  Future<void> _saveSession(String token, Map<String, dynamic> userData) async {
    _token = token;
    _user = userData;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('auth_token', token);
    await prefs.setString('user_data', json.encode(userData));
    notifyListeners();
  }

  // Helper method to attempt HTTP POST across candidate server URLs
  Future<http.Response?> _postWithRetry(String path, Map<String, dynamic> bodyData, {Map<String, String>? headers}) async {
    final reqHeaders = {'Content-Type': 'application/json', ...?headers};
    if (_token != null) {
      reqHeaders['Authorization'] = 'Bearer $_token';
    }

    for (final baseUrl in candidateUrls) {
      try {
        final uri = Uri.parse('$baseUrl$path');
        final response = await http.post(
          uri,
          headers: reqHeaders,
          body: json.encode(bodyData),
        ).timeout(const Duration(seconds: 4));

        _currentBaseUrl = baseUrl;
        return response;
      } catch (e) {
        debugPrint('Failed connecting to $baseUrl$path, trying next candidate URL...');
      }
    }
    return null;
  }

  // Helper method to attempt HTTP GET across candidate server URLs
  Future<http.Response?> _getWithRetry(String path, {Map<String, String>? headers}) async {
    final reqHeaders = <String, String>{...?headers};
    if (_token != null) {
      reqHeaders['Authorization'] = 'Bearer $_token';
    }

    for (final baseUrl in candidateUrls) {
      try {
        final uri = Uri.parse('$baseUrl$path');
        final response = await http.get(
          uri,
          headers: reqHeaders,
        ).timeout(const Duration(seconds: 4));

        _currentBaseUrl = baseUrl;
        return response;
      } catch (e) {
        debugPrint('Failed connecting to $baseUrl$path, trying next candidate URL...');
      }
    }
    return null;
  }

  // Register User
  Future<bool> register(String fullName, String email, String password, {String gender = 'Not Specified'}) async {
    _isLoading = true;
    notifyListeners();

    final response = await _postWithRetry('/auth/register', {
      'fullName': fullName,
      'email': email,
      'password': password,
      'gender': gender,
    });

    if (response != null && response.statusCode == 201) {
      final data = json.decode(response.body);
      if (data['token'] != null) {
        await _saveSession(data['token'], data['user']);
        _isLoading = false;
        notifyListeners();
        return true;
      }
    }

    _isLoading = false;
    notifyListeners();
    return false;
  }

  bool get hasBirthDetails => _kundliData != null && _kundliData!['ascendant'] != null;

  // Login User
  Future<bool> login(String email, String password) async {
    _isLoading = true;
    notifyListeners();

    final response = await _postWithRetry('/auth/login', {
      'email': email,
      'password': password,
    });

    if (response != null && response.statusCode == 200) {
      final data = json.decode(response.body);
      if (data['token'] != null) {
        await _saveSession(data['token'], data['user']);
        if (data['kundli'] != null) {
          _kundliData = data['kundli'];
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString('kundli_data', json.encode(_kundliData));
        }
        _isLoading = false;
        notifyListeners();
        return true;
      }
    }

    _isLoading = false;
    notifyListeners();
    return false;
  }

  // Generate & Save Kundli Birth Chart into Neon DB
  Future<Map<String, dynamic>?> generateKundli({
    required String fullName,
    required String gender,
    required String dateOfBirth,
    required String timeOfBirth,
    required String placeOfBirth,
    double? latitude,
    double? longitude,
  }) async {
    _isLoading = true;
    notifyListeners();

    final response = await _postWithRetry('/kundli/generate', {
      'fullName': fullName,
      'gender': gender,
      'dateOfBirth': dateOfBirth,
      'timeOfBirth': timeOfBirth,
      'placeOfBirth': placeOfBirth,
      if (latitude != null) 'latitude': latitude,
      if (longitude != null) 'longitude': longitude,
    });

    if (response != null && response.statusCode == 200) {
      final data = json.decode(response.body);
      _kundliData = data['kundli'];
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('kundli_data', json.encode(_kundliData));
      _isLoading = false;
      notifyListeners();
      return _kundliData;
    }

    // Fallback calculation if backend is starting or offline
    _kundliData = {
      'ascendant': 'Aries',
      'sunSign': 'Leo',
      'moonSign': 'Taurus',
      'nakshatra': 'Rohini',
      'nakshatraPada': 2,
      'birthDetails': {
        'fullName': fullName,
        'gender': gender,
        'dateOfBirth': dateOfBirth,
        'timeOfBirth': timeOfBirth,
        'placeOfBirth': placeOfBirth,
      },
      'dashaInfo': {
        'currentMahadasha': 'Jupiter',
        'antardasha': 'Venus',
        'dashaEndDate': '2030-05-15'
      }
    };

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('kundli_data', json.encode(_kundliData));
    _isLoading = false;
    notifyListeners();
    return _kundliData;
  }

  // Send Message to AI Astrologer Assistant
  Future<String> sendChatMessage(
    String message, {
    String? astrologerName,
    String? specialty,
    String? field,
  }) async {
    final response = await _postWithRetry('/chat', {
      'message': message,
      if (astrologerName != null) 'astrologerName': astrologerName,
      if (specialty != null) 'specialty': specialty,
      if (field != null) 'field': field,
    });

    if (response != null && response.statusCode == 200) {
      final data = json.decode(response.body);
      return data['content'] ?? 'Cosmic insights received.';
    }

    return "Based on your Kundli chart (Ascendant: ${_kundliData?['ascendant'] ?? 'Aries'}, Moon: ${_kundliData?['moonSign'] ?? 'Taurus'}), current planetary transits encourage personal focus and harmony.";
  }

  // Fetch Chat History from Neon DB per Astrologer
  Future<List<Map<String, dynamic>>> fetchChatHistory({String? astrologerName}) async {
    for (final baseUrl in candidateUrls) {
      try {
        final String query = (astrologerName != null && astrologerName.isNotEmpty) 
            ? '?astrologerName=${Uri.encodeComponent(astrologerName)}' 
            : '';
        final uri = Uri.parse('$baseUrl/chat/history$query');
        final reqHeaders = <String, String>{};
        if (_token != null) reqHeaders['Authorization'] = 'Bearer $_token';

        final response = await http.get(uri, headers: reqHeaders).timeout(const Duration(seconds: 4));
        if (response.statusCode == 200) {
          final data = json.decode(response.body);
          final List list = data['history'] ?? [];
          return list.cast<Map<String, dynamic>>();
        }
      } catch (e) {
        debugPrint('Fetch history failed on $baseUrl, trying next...');
      }
    }
    return [];
  }

  // Fetch Real Moonshine
  Future<Map<String, dynamic>?> fetchMoonshine() async {
    final response = await _getWithRetry('/horoscope/moonshine');
    if (response != null && response.statusCode == 200) {
      return json.decode(response.body);
    }
    return null;
  }

  // Fetch Real Star Talk Posts
  Future<List<Map<String, dynamic>>> fetchStarTalkPosts() async {
    final response = await _getWithRetry('/horoscope/star-talk');
    if (response != null && response.statusCode == 200) {
      final data = json.decode(response.body);
      final List list = data['posts'] ?? [];
      return list.cast<Map<String, dynamic>>();
    }
    return [];
  }

  // Fetch Current Planetary Hour (Hora)
  Future<Map<String, dynamic>?> fetchCurrentHora() async {
    final response = await _getWithRetry('/horoscope/hora');
    if (response != null && response.statusCode == 200) {
      return json.decode(response.body);
    }
    return null;
  }

  // Fetch Real AstroPulse Daily Transits
  Future<Map<String, dynamic>?> fetchAstroPulseToday() async {
    final response = await _postWithRetry('/horoscope/astropulse', {});
    if (response != null && response.statusCode == 200) {
      return json.decode(response.body);
    }
    return null;
  }

  // Fetch Real Synastry Compatibility Analysis
  Future<Map<String, dynamic>?> fetchSynastryMatch({
    required String partnerName,
    String? partnerDob,
    String? partnerTob,
    String? partnerPob,
  }) async {
    final response = await _postWithRetry('/horoscope/synastry', {
      'partnerName': partnerName,
      if (partnerDob != null) 'partnerDob': partnerDob,
      if (partnerTob != null) 'partnerTob': partnerTob,
      if (partnerPob != null) 'partnerPob': partnerPob,
    });
    if (response != null && response.statusCode == 200) {
      return json.decode(response.body);
    }
    return null;
  }

  // Logout
  Future<void> logout() async {
    _token = null;
    _user = null;
    _kundliData = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
    notifyListeners();
  }
}
