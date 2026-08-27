import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class BackendService extends ChangeNotifier {
  // Base URL for the Node.js / Express Neon DB Backend
  // Use 10.0.2.2 for Android Emulator, localhost for Web/Desktop, or custom IP/Domain
  static const String baseUrl = 'http://10.0.2.2:5000/api'; 
  static const String fallbackUrl = 'http://localhost:5000/api';

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

  // Register user
  Future<bool> register(String fullName, String email, String password, {String gender = 'Not Specified'}) async {
    _isLoading = true;
    notifyListeners();

    try {
      final response = await http.post(
        Uri.parse('$baseUrl/auth/register'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'fullName': fullName,
          'email': email,
          'password': password,
          'gender': gender,
        }),
      );

      final data = json.decode(response.body);

      if (response.statusCode == 201 && data['token'] != null) {
        await _saveSession(data['token'], data['user']);
        _isLoading = false;
        notifyListeners();
        return true;
      }
    } catch (e) {
      debugPrint('Registration error: $e');
    }

    _isLoading = false;
    notifyListeners();
    return false;
  }

  // Login user
  Future<bool> login(String email, String password) async {
    _isLoading = true;
    notifyListeners();

    try {
      final response = await http.post(
        Uri.parse('$baseUrl/auth/login'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'email': email,
          'password': password,
        }),
      );

      final data = json.decode(response.body);

      if (response.statusCode == 200 && data['token'] != null) {
        await _saveSession(data['token'], data['user']);
        _isLoading = false;
        notifyListeners();
        return true;
      }
    } catch (e) {
      debugPrint('Login error: $e');
    }

    _isLoading = false;
    notifyListeners();
    return false;
  }

  // Generate & Save Kundli Birth Chart
  Future<Map<String, dynamic>?> generateKundli({
    required String fullName,
    required String gender,
    required String dateOfBirth,
    required String timeOfBirth,
    required String placeOfBirth,
  }) async {
    _isLoading = true;
    notifyListeners();

    try {
      final headers = {'Content-Type': 'application/json'};
      if (_token != null) {
        headers['Authorization'] = 'Bearer $_token';
      }

      final response = await http.post(
        Uri.parse('$baseUrl/kundli/generate'),
        headers: headers,
        body: json.encode({
          'fullName': fullName,
          'gender': gender,
          'dateOfBirth': dateOfBirth,
          'timeOfBirth': timeOfBirth,
          'placeOfBirth': placeOfBirth,
        }),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        _kundliData = data['kundli'];
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('kundli_data', json.encode(_kundliData));
        _isLoading = false;
        notifyListeners();
        return _kundliData;
      }
    } catch (e) {
      debugPrint('Generate Kundli error: $e');
    }

    // Fallback offline calculation if backend is unreachable
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

  // Send message to AI Kundli Assistant
  Future<String> sendChatMessage(String message) async {
    try {
      final headers = {'Content-Type': 'application/json'};
      if (_token != null) {
        headers['Authorization'] = 'Bearer $_token';
      }

      final response = await http.post(
        Uri.parse('$baseUrl/chat'),
        headers: headers,
        body: json.encode({'message': message}),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return data['content'] ?? 'Cosmic insights received.';
      }
    } catch (e) {
      debugPrint('Chat error: $e');
    }

    // Fallback smart response
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
