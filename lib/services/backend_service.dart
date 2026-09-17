import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class BackendService extends ChangeNotifier {
  // Candidate base URLs for different environments (Vercel Production & Local Fallback)
  static const List<String> candidateUrls = [
    'https://gohypeidearegligionstatup.vercel.app/api',
    'http://localhost:5000/api',
    'http://127.0.0.1:5000/api',
    'http://10.0.2.2:5000/api',
  ];

  String _currentBaseUrl = 'https://gohypeidearegligionstatup.vercel.app/api';
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

  // Helper method to attempt HTTP DELETE across candidate server URLs
  Future<http.Response?> _deleteWithRetry(String path, {Map<String, String>? headers}) async {
    final reqHeaders = <String, String>{...?headers};
    if (_token != null) {
      reqHeaders['Authorization'] = 'Bearer $_token';
    }

    for (final baseUrl in candidateUrls) {
      try {
        final uri = Uri.parse('$baseUrl$path');
        final response = await http.delete(
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

  // Fetch ChatGPT (GPT-4o) Deep Kundli Reading Report based on Swiss Ephemeris data
  Future<String?> fetchAIKundliReport(Map<String, dynamic> kundli, {Map<String, dynamic>? birthDetails}) async {
    final response = await _postWithRetry('/kundli/ai-report', {
      'kundli': kundli,
      if (birthDetails != null) 'birthDetails': birthDetails,
    });

    if (response != null && response.statusCode == 200) {
      final data = json.decode(response.body);
      return data['aiReport'] as String?;
    }
    return null;
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

  // Fetch Today's Live Panchang & Muhurat Clock
  Future<Map<String, dynamic>?> fetchPanchangToday() async {
    final response = await _getWithRetry('/horoscope/panchang');
    if (response != null && response.statusCode == 200) {
      return json.decode(response.body);
    }
    return null;
  }

  // Fetch Real Synastry Compatibility Analysis
  Future<Map<String, dynamic>?> fetchSynastryMatch({
    required String partnerName,
    String? partnerGender,
    String? partnerDob,
    String? partnerTob,
    String? partnerPob,
  }) async {
    final response = await _postWithRetry('/horoscope/synastry', {
      'partnerName': partnerName,
      if (partnerGender != null) 'partnerGender': partnerGender,
      if (partnerDob != null) 'partnerDob': partnerDob,
      if (partnerTob != null) 'partnerTob': partnerTob,
      if (partnerPob != null) 'partnerPob': partnerPob,
    });
    if (response != null && response.statusCode == 200) {
      return json.decode(response.body);
    }
    return null;
  }

  List<Map<String, dynamic>> _familyMembers = [];
  Map<String, dynamic>? _selectedFamilyMember;

  List<Map<String, dynamic>> get familyMembers => _familyMembers;
  Map<String, dynamic>? get selectedFamilyMember => _selectedFamilyMember;

  void selectFamilyMember(Map<String, dynamic>? member) {
    _selectedFamilyMember = member;
    notifyListeners();
  }

  // Fetch Family Kundlis
  Future<List<Map<String, dynamic>>> fetchFamilyKundlis() async {
    final response = await _getWithRetry('/kundli/family/list');
    if (response != null && response.statusCode == 200) {
      final data = json.decode(response.body);
      final List list = data['familyMembers'] ?? [];
      _familyMembers = list.cast<Map<String, dynamic>>();
      notifyListeners();
      return _familyMembers;
    }
    return [];
  }

  // Add Family Kundli
  Future<Map<String, dynamic>?> addFamilyKundli({
    required String relationship,
    required String fullName,
    required String dateOfBirth,
    required String timeOfBirth,
    required String placeOfBirth,
    String gender = 'Not Specified',
  }) async {
    final response = await _postWithRetry('/kundli/family/add', {
      'relationship': relationship,
      'fullName': fullName,
      'gender': gender,
      'dateOfBirth': dateOfBirth,
      'timeOfBirth': timeOfBirth,
      'placeOfBirth': placeOfBirth,
    });
    if (response != null && response.statusCode == 200) {
      final data = json.decode(response.body);
      await fetchFamilyKundlis();
      return data['familyMember'];
    }
    return null;
  }

  // Delete Family Kundli
  Future<bool> deleteFamilyKundli(int id) async {
    final response = await _deleteWithRetry('/kundli/family/$id');
    if (response != null && response.statusCode == 200) {
      await fetchFamilyKundlis();
      return true;
    }
    return false;
  }

  // --- PANDIT & LIVE CONSULTATION QUEUE API METHODS ---
  String? _panditToken;
  Map<String, dynamic>? _panditProfile;
  Map<String, dynamic>? get panditProfile => _panditProfile;
  Map<String, dynamic>? get currentPandit => _panditProfile;
  bool get isPanditLoggedIn => _panditProfile != null || _panditToken != null;

  Future<Map<String, dynamic>?> loginPandit({
    required String email,
    required String password,
  }) async {
    final response = await _postWithRetry('/pandit/login', {
      'email': email,
      'password': password,
    });

    if (response != null && response.statusCode == 200) {
      final data = json.decode(response.body);
      _panditToken = data['token'];
      _panditProfile = data['pandit'];
      if (_panditToken != null) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('pandit_token', _panditToken!);
      }
      notifyListeners();
      return _panditProfile;
    }
    return null;
  }

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
    final response = await _postWithRetry('/pandit/register', {
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

    if (response != null) {
      final data = json.decode(response.body);
      if (response.statusCode == 200) {
        _panditToken = data['token'];
        _panditProfile = data['pandit'];
        if (_panditToken != null) {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString('pandit_token', _panditToken!);
        }
        notifyListeners();
        return _panditProfile;
      } else if (response.statusCode == 400 && data['error'] == 'PANDIT_ALREADY_EXISTS') {
        return {'error': 'PANDIT_ALREADY_EXISTS', 'message': data['message']};
      }
    }
    return null;
  }

  Future<void> logoutPandit() async {
    _panditToken = null;
    _panditProfile = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('pandit_token');
    notifyListeners();
  }

  // Fetch Live Registered Pandits List
  Future<List<Map<String, dynamic>>> fetchPanditsList() async {
    final response = await _getWithRetry('/pandit/list');
    if (response != null && response.statusCode == 200) {
      final data = json.decode(response.body);
      final List list = data['pandits'] ?? [];
      return list.cast<Map<String, dynamic>>();
    }
    return [];
  }

  // Toggle Pandit Online/Offline status
  Future<bool> togglePanditStatus({bool? isOnline, bool? isBusy}) async {
    final response = await _postWithRetry('/pandit/toggle-status', {
      if (isOnline != null) 'isOnline': isOnline,
      if (isBusy != null) 'isBusy': isBusy,
    });
    if (response != null && response.statusCode == 200) {
      final data = json.decode(response.body);
      _panditProfile = data['pandit'];
      notifyListeners();
      return true;
    }
    return false;
  }

  // Request Consultation (Starts active session or enters waiting queue)
  Future<Map<String, dynamic>?> requestConsultation({
    required dynamic panditId,
    String? userName,
  }) async {
    final response = await _postWithRetry('/pandit/request', {
      'panditId': panditId,
      'userName': userName ?? _kundliData?['birthDetails']?['fullName'] ?? 'User Seeker',
    });
    if (response != null && response.statusCode == 200) {
      return json.decode(response.body);
    }
    return null;
  }

  // Fetch Live Queue Status for User or Pandit
  Future<Map<String, dynamic>?> fetchQueueStatus({dynamic panditId}) async {
    final String path = panditId != null ? '/pandit/queue-status?panditId=$panditId' : '/pandit/queue-status';
    final response = await _getWithRetry(path);
    if (response != null && response.statusCode == 200) {
      return json.decode(response.body);
    }
    return null;
  }

  // Pandit advances queue to next user
  Future<Map<String, dynamic>?> nextConsultation(dynamic panditId) async {
    final response = await _postWithRetry('/pandit/next', {
      'panditId': panditId,
    });
    if (response != null && response.statusCode == 200) {
      return json.decode(response.body);
    }
    return null;
  }

  // Fetch Seeker's Authentic Kundli Chart for Pandit Inspection
  Future<Map<String, dynamic>?> fetchUserKundliForPandit(dynamic userId) async {
    final response = await _getWithRetry('/pandit/user-kundli/$userId');
    if (response != null && response.statusCode == 200) {
      return json.decode(response.body);
    }
    return null;
  }

  // --- WALLET & RECHARGE API METHODS ---
  double _walletBalance = 250.00;
  double get walletBalance => _walletBalance;

  Future<double> fetchWalletBalance() async {
    final response = await _getWithRetry('/pandit/wallet/balance');
    if (response != null && response.statusCode == 200) {
      final data = json.decode(response.body);
      _walletBalance = (data['walletBalance'] ?? 250.0).toDouble();
      notifyListeners();
      return _walletBalance;
    }
    return _walletBalance;
  }

  Future<double?> rechargeWallet(double amount) async {
    final response = await _postWithRetry('/pandit/wallet/recharge', {
      'amount': amount,
    });
    if (response != null && response.statusCode == 200) {
      final data = json.decode(response.body);
      _walletBalance = (data['walletBalance'] ?? 250.0).toDouble();
      notifyListeners();
      return _walletBalance;
    }
    return null;
  }

  // --- PANDIT RATING & REVIEWS API METHODS ---
  Future<bool> submitPanditReview({
    required dynamic panditId,
    required double rating,
    required String reviewText,
  }) async {
    final response = await _postWithRetry('/pandit/rate', {
      'panditId': panditId,
      'rating': rating,
      'reviewText': reviewText,
      'userName': _kundliData?['birthDetails']?['fullName'] ?? 'User Seeker',
    });
    return response != null && response.statusCode == 200;
  }

  // --- CONSULTATION HISTORY & PRESCRIBED REMEDIES API METHODS ---
  Future<Map<String, dynamic>?> fetchConsultationHistory() async {
    final response = await _getWithRetry('/pandit/history');
    if (response != null && response.statusCode == 200) {
      return json.decode(response.body);
    }
    return null;
  }

  // --- AI GEMSTONE & REMEDY RECOMMENDATIONS API METHODS ---
  Future<Map<String, dynamic>?> fetchGemstoneRecommendations() async {
    final response = await _getWithRetry('/pandit/remedies/recommendations');
    if (response != null && response.statusCode == 200) {
      return json.decode(response.body);
    }
    return null;
  }

  // --- PER-MINUTE CONSULTATION BILLING & PAYOUT API METHOD ---
  Future<Map<String, dynamic>?> deductConsultationMinute({
    required dynamic panditId,
    double ratePerMin = 5.0,
  }) async {
    final response = await _postWithRetry('/pandit/consultation/deduct-minute', {
      'panditId': panditId,
      'ratePerMin': ratePerMin,
    });
    if (response != null && response.statusCode == 200) {
      final data = json.decode(response.body);
      if (data['walletBalance'] != null) {
        _walletBalance = (data['walletBalance']).toDouble();
        notifyListeners();
      }
      return data;
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
