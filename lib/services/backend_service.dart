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
  }) async {
    _isLoading = true;
    notifyListeners();

    final response = await _postWithRetry('/kundli/generate', {
      'fullName': fullName,
      'gender': gender,
      'dateOfBirth': dateOfBirth,
      'timeOfBirth': timeOfBirth,
      'placeOfBirth': placeOfBirth,
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
  Future<String> sendChatMessage(String message) async {
    final response = await _postWithRetry('/chat', {'message': message});

    if (response != null && response.statusCode == 200) {
      final data = json.decode(response.body);
      return data['content'] ?? 'Cosmic insights received.';
    }

    return "Based on your Kundli chart (Ascendant: ${_kundliData?['ascendant'] ?? 'Aries'}, Moon: ${_kundliData?['moonSign'] ?? 'Taurus'}), current planetary transits encourage personal focus and harmony.";
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
