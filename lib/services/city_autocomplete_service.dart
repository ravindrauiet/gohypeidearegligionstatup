import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class CitySuggestion {
  final String cityName;
  final String stateName;
  final String countryName;
  final String fullDisplayName;
  final double? latitude;
  final double? longitude;

  CitySuggestion({
    required this.cityName,
    required this.stateName,
    required this.countryName,
    required this.fullDisplayName,
    this.latitude,
    this.longitude,
  });

  factory CitySuggestion.fromNominatimJson(Map<String, dynamic> json) {
    final address = json['address'] ?? {};
    final postcode = address['postcode'] ?? '';
    final city = address['city'] ??
        address['town'] ??
        address['village'] ??
        address['suburb'] ??
        address['municipality'] ??
        address['county'] ??
        address['state_district'] ??
        json['display_name'].split(',')[0];

    final state = address['state'] ?? address['region'] ?? address['province'] ?? '';
    final countryCode = (address['country_code'] ?? '').toString().toLowerCase();
    final rawCountry = address['country']?.toString();

    String country;
    if (countryCode == 'np' || (rawCountry != null && rawCountry.toLowerCase().contains('nepal'))) {
      country = 'Nepal';
    } else if (countryCode == 'lk' || (rawCountry != null && rawCountry.toLowerCase().contains('sri lanka'))) {
      country = 'Sri Lanka';
    } else {
      country = 'India';
    }

    String displayName = '';
    if (postcode.toString().isNotEmpty) {
      displayName = '${postcode.toString().trim()} - $city';
    } else {
      displayName = '$city';
    }
    if (state.isNotEmpty && !displayName.toLowerCase().contains(state.toString().toLowerCase())) {
      displayName += ', $state';
    }
    displayName += ', $country';

    return CitySuggestion(
      cityName: city.toString(),
      stateName: state.toString(),
      countryName: country,
      fullDisplayName: displayName,
      latitude: double.tryParse(json['lat']?.toString() ?? ''),
      longitude: double.tryParse(json['lon']?.toString() ?? ''),
    );
  }
}

class CityAutocompleteService {
  // Built-in dataset strictly for India, Nepal, and Sri Lanka
  static final List<CitySuggestion> _southAsiaDataset = [
    // --- INDIA ---
    CitySuggestion(cityName: 'New Delhi', stateName: 'Delhi', countryName: 'India', fullDisplayName: 'New Delhi, Delhi, India', latitude: 28.6139, longitude: 77.209),
    CitySuggestion(cityName: 'Delhi', stateName: 'Delhi', countryName: 'India', fullDisplayName: 'Delhi, India', latitude: 28.7041, longitude: 77.1025),
    CitySuggestion(cityName: 'Mumbai', stateName: 'Maharashtra', countryName: 'India', fullDisplayName: 'Mumbai, Maharashtra, India', latitude: 19.076, longitude: 72.8777),
    CitySuggestion(cityName: 'Bengaluru', stateName: 'Karnataka', countryName: 'India', fullDisplayName: 'Bengaluru, Karnataka, India', latitude: 12.9716, longitude: 77.5946),
    CitySuggestion(cityName: 'Kolkata', stateName: 'West Bengal', countryName: 'India', fullDisplayName: 'Kolkata, West Bengal, India', latitude: 22.5726, longitude: 88.3639),
    CitySuggestion(cityName: 'Chennai', stateName: 'Tamil Nadu', countryName: 'India', fullDisplayName: 'Chennai, Tamil Nadu, India', latitude: 13.0827, longitude: 80.2707),
    CitySuggestion(cityName: 'Hyderabad', stateName: 'Telangana', countryName: 'India', fullDisplayName: 'Hyderabad, Telangana, India', latitude: 17.385, longitude: 78.4867),
    CitySuggestion(cityName: 'Pune', stateName: 'Maharashtra', countryName: 'India', fullDisplayName: 'Pune, Maharashtra, India', latitude: 18.5204, longitude: 73.8567),
    CitySuggestion(cityName: 'Ahmedabad', stateName: 'Gujarat', countryName: 'India', fullDisplayName: 'Ahmedabad, Gujarat, India', latitude: 23.0225, longitude: 72.5714),
    CitySuggestion(cityName: 'Jaipur', stateName: 'Rajasthan', countryName: 'India', fullDisplayName: 'Jaipur, Rajasthan, India', latitude: 26.9124, longitude: 75.7873),
    CitySuggestion(cityName: 'Lucknow', stateName: 'Uttar Pradesh', countryName: 'India', fullDisplayName: 'Lucknow, Uttar Pradesh, India', latitude: 26.8467, longitude: 80.9462),
    CitySuggestion(cityName: 'Chandigarh', stateName: 'Punjab & Haryana', countryName: 'India', fullDisplayName: 'Chandigarh, India', latitude: 30.7333, longitude: 76.7794),
    CitySuggestion(cityName: 'Patna', stateName: 'Bihar', countryName: 'India', fullDisplayName: 'Patna, Bihar, India', latitude: 25.5941, longitude: 85.1376),
    CitySuggestion(cityName: 'Bhopal', stateName: 'Madhya Pradesh', countryName: 'India', fullDisplayName: 'Bhopal, Madhya Pradesh, India', latitude: 23.2599, longitude: 77.4126),
    CitySuggestion(cityName: 'Surat', stateName: 'Gujarat', countryName: 'India', fullDisplayName: 'Surat, Gujarat, India', latitude: 21.1702, longitude: 72.8311),
    CitySuggestion(cityName: 'Indore', stateName: 'Madhya Pradesh', countryName: 'India', fullDisplayName: 'Indore, Madhya Pradesh, India', latitude: 22.7196, longitude: 75.8577),
    CitySuggestion(cityName: 'Varanasi', stateName: 'Uttar Pradesh', countryName: 'India', fullDisplayName: 'Varanasi, Uttar Pradesh, India', latitude: 25.3176, longitude: 82.9739),
    CitySuggestion(cityName: 'Ayodhya', stateName: 'Uttar Pradesh', countryName: 'India', fullDisplayName: 'Ayodhya, Uttar Pradesh, India', latitude: 26.7922, longitude: 82.1998),
    CitySuggestion(cityName: 'Noida', stateName: 'Uttar Pradesh', countryName: 'India', fullDisplayName: 'Noida, Uttar Pradesh, India', latitude: 28.5355, longitude: 77.391),
    CitySuggestion(cityName: 'Gurugram', stateName: 'Haryana', countryName: 'India', fullDisplayName: 'Gurugram, Haryana, India', latitude: 28.4595, longitude: 77.0266),
    CitySuggestion(cityName: 'Agra', stateName: 'Uttar Pradesh', countryName: 'India', fullDisplayName: 'Agra, Uttar Pradesh, India', latitude: 27.1767, longitude: 78.0081),
    CitySuggestion(cityName: 'Kanpur', stateName: 'Uttar Pradesh', countryName: 'India', fullDisplayName: 'Kanpur, Uttar Pradesh, India', latitude: 26.4499, longitude: 80.3319),
    CitySuggestion(cityName: 'Nagpur', stateName: 'Maharashtra', countryName: 'India', fullDisplayName: 'Nagpur, Maharashtra, India', latitude: 21.1458, longitude: 79.0882),
    CitySuggestion(cityName: 'Amritsar', stateName: 'Punjab', countryName: 'India', fullDisplayName: 'Amritsar, Punjab, India', latitude: 31.634, longitude: 74.8723),
    CitySuggestion(cityName: 'Dehradun', stateName: 'Uttarakhand', countryName: 'India', fullDisplayName: 'Dehradun, Uttarakhand, India', latitude: 30.3165, longitude: 78.0322),
    CitySuggestion(cityName: 'Haridwar', stateName: 'Uttarakhand', countryName: 'India', fullDisplayName: 'Haridwar, Uttarakhand, India', latitude: 29.9457, longitude: 78.1642),
    CitySuggestion(cityName: 'Rishikesh', stateName: 'Uttarakhand', countryName: 'India', fullDisplayName: 'Rishikesh, Uttarakhand, India', latitude: 30.0869, longitude: 78.2676),
    CitySuggestion(cityName: 'Ujjain', stateName: 'Madhya Pradesh', countryName: 'India', fullDisplayName: 'Ujjain, Madhya Pradesh, India', latitude: 23.1765, longitude: 75.7885),
    CitySuggestion(cityName: 'Ranchi', stateName: 'Jharkhand', countryName: 'India', fullDisplayName: 'Ranchi, Jharkhand, India', latitude: 23.3441, longitude: 85.3096),
    CitySuggestion(cityName: 'Guwahati', stateName: 'Assam', countryName: 'India', fullDisplayName: 'Guwahati, Assam, India', latitude: 26.1445, longitude: 91.7362),
    CitySuggestion(cityName: 'Bhubaneswar', stateName: 'Odisha', countryName: 'India', fullDisplayName: 'Bhubaneswar, Odisha, India', latitude: 20.2961, longitude: 85.8245),
    CitySuggestion(cityName: 'Kochi', stateName: 'Kerala', countryName: 'India', fullDisplayName: 'Kochi, Kerala, India', latitude: 9.9312, longitude: 76.2673),
    CitySuggestion(cityName: 'Thiruvananthapuram', stateName: 'Kerala', countryName: 'India', fullDisplayName: 'Thiruvananthapuram, Kerala, India', latitude: 8.5241, longitude: 76.9366),
    CitySuggestion(cityName: 'Coimbatore', stateName: 'Tamil Nadu', countryName: 'India', fullDisplayName: 'Coimbatore, Tamil Nadu, India', latitude: 11.0168, longitude: 76.9558),
    CitySuggestion(cityName: 'Madurai', stateName: 'Tamil Nadu', countryName: 'India', fullDisplayName: 'Madurai, Tamil Nadu, India', latitude: 9.9252, longitude: 78.1198),
    CitySuggestion(cityName: 'Vadodara', stateName: 'Gujarat', countryName: 'India', fullDisplayName: 'Vadodara, Gujarat, India', latitude: 22.3072, longitude: 73.1812),
    CitySuggestion(cityName: 'Ghaziabad', stateName: 'Uttar Pradesh', countryName: 'India', fullDisplayName: 'Ghaziabad, Uttar Pradesh, India', latitude: 28.6692, longitude: 77.4538),
    CitySuggestion(cityName: 'Ludhiana', stateName: 'Punjab', countryName: 'India', fullDisplayName: 'Ludhiana, Punjab, India', latitude: 30.901, longitude: 75.8573),
    CitySuggestion(cityName: 'Prayagraj', stateName: 'Uttar Pradesh', countryName: 'India', fullDisplayName: 'Prayagraj, Uttar Pradesh, India', latitude: 25.4358, longitude: 81.8463),
    CitySuggestion(cityName: 'Gorakhpur', stateName: 'Uttar Pradesh', countryName: 'India', fullDisplayName: 'Gorakhpur, Uttar Pradesh, India', latitude: 26.7606, longitude: 83.3732),
    CitySuggestion(cityName: 'Jodhpur', stateName: 'Rajasthan', countryName: 'India', fullDisplayName: 'Jodhpur, Rajasthan, India', latitude: 26.2389, longitude: 73.0243),
    CitySuggestion(cityName: 'Udaipur', stateName: 'Rajasthan', countryName: 'India', fullDisplayName: 'Udaipur, Rajasthan, India', latitude: 24.5854, longitude: 73.7125),
    CitySuggestion(cityName: 'Gwalior', stateName: 'Madhya Pradesh', countryName: 'India', fullDisplayName: 'Gwalior, Madhya Pradesh, India', latitude: 26.2183, longitude: 78.1828),
    CitySuggestion(cityName: 'Raipur', stateName: 'Chhattisgarh', countryName: 'India', fullDisplayName: 'Raipur, Chhattisgarh, India', latitude: 21.2514, longitude: 81.6296),
    CitySuggestion(cityName: 'Shimla', stateName: 'Himachal Pradesh', countryName: 'India', fullDisplayName: 'Shimla, Himachal Pradesh, India', latitude: 31.1048, longitude: 77.1734),
    CitySuggestion(cityName: 'Jammu', stateName: 'Jammu and Kashmir', countryName: 'India', fullDisplayName: 'Jammu, J&K, India', latitude: 32.7266, longitude: 74.857),
    CitySuggestion(cityName: 'Srinagar', stateName: 'Jammu and Kashmir', countryName: 'India', fullDisplayName: 'Srinagar, J&K, India', latitude: 34.0837, longitude: 74.7973),

    // --- NEPAL ---
    CitySuggestion(cityName: 'Kathmandu', stateName: 'Bagmati', countryName: 'Nepal', fullDisplayName: 'Kathmandu, Bagmati, Nepal', latitude: 27.7172, longitude: 85.3240),
    CitySuggestion(cityName: 'Pokhara', stateName: 'Gandaki', countryName: 'Nepal', fullDisplayName: 'Pokhara, Gandaki, Nepal', latitude: 28.2096, longitude: 83.9856),
    CitySuggestion(cityName: 'Lalitpur', stateName: 'Bagmati', countryName: 'Nepal', fullDisplayName: 'Lalitpur (Patan), Bagmati, Nepal', latitude: 27.6588, longitude: 85.3247),
    CitySuggestion(cityName: 'Biratnagar', stateName: 'Koshi', countryName: 'Nepal', fullDisplayName: 'Biratnagar, Koshi, Nepal', latitude: 26.4525, longitude: 87.2718),
    CitySuggestion(cityName: 'Bharatpur', stateName: 'Bagmati', countryName: 'Nepal', fullDisplayName: 'Bharatpur, Bagmati, Nepal', latitude: 27.6833, longitude: 84.4333),
    CitySuggestion(cityName: 'Janakpur', stateName: 'Madhesh', countryName: 'Nepal', fullDisplayName: 'Janakpur, Madhesh, Nepal', latitude: 26.7271, longitude: 85.9249),
    CitySuggestion(cityName: 'Birgunj', stateName: 'Madhesh', countryName: 'Nepal', fullDisplayName: 'Birgunj, Madhesh, Nepal', latitude: 27.0135, longitude: 84.8770),
    CitySuggestion(cityName: 'Dharan', stateName: 'Koshi', countryName: 'Nepal', fullDisplayName: 'Dharan, Koshi, Nepal', latitude: 26.8124, longitude: 87.2834),
    CitySuggestion(cityName: 'Butwal', stateName: 'Lumbini', countryName: 'Nepal', fullDisplayName: 'Butwal, Lumbini, Nepal', latitude: 27.7006, longitude: 83.4484),
    CitySuggestion(cityName: 'Bhaktapur', stateName: 'Bagmati', countryName: 'Nepal', fullDisplayName: 'Bhaktapur, Bagmati, Nepal', latitude: 27.6710, longitude: 85.4298),
    CitySuggestion(cityName: 'Hetauda', stateName: 'Bagmati', countryName: 'Nepal', fullDisplayName: 'Hetauda, Bagmati, Nepal', latitude: 27.4285, longitude: 85.0326),
    CitySuggestion(cityName: 'Nepalgunj', stateName: 'Lumbini', countryName: 'Nepal', fullDisplayName: 'Nepalgunj, Lumbini, Nepal', latitude: 28.0500, longitude: 81.6167),
    CitySuggestion(cityName: 'Dhangadhi', stateName: 'Sudurpashchim', countryName: 'Nepal', fullDisplayName: 'Dhangadhi, Sudurpashchim, Nepal', latitude: 28.6853, longitude: 80.5960),
    CitySuggestion(cityName: 'Lumbini', stateName: 'Lumbini', countryName: 'Nepal', fullDisplayName: 'Lumbini Sanskritik, Lumbini, Nepal', latitude: 27.4705, longitude: 83.2755),

    // --- SRI LANKA ---
    CitySuggestion(cityName: 'Colombo', stateName: 'Western Province', countryName: 'Sri Lanka', fullDisplayName: 'Colombo, Western Province, Sri Lanka', latitude: 6.9271, longitude: 79.8612),
    CitySuggestion(cityName: 'Kandy', stateName: 'Central Province', countryName: 'Sri Lanka', fullDisplayName: 'Kandy, Central Province, Sri Lanka', latitude: 7.2906, longitude: 80.6337),
    CitySuggestion(cityName: 'Galle', stateName: 'Southern Province', countryName: 'Sri Lanka', fullDisplayName: 'Galle, Southern Province, Sri Lanka', latitude: 6.0535, longitude: 80.2210),
    CitySuggestion(cityName: 'Jaffna', stateName: 'Northern Province', countryName: 'Sri Lanka', fullDisplayName: 'Jaffna, Northern Province, Sri Lanka', latitude: 9.6615, longitude: 80.0255),
    CitySuggestion(cityName: 'Negombo', stateName: 'Western Province', countryName: 'Sri Lanka', fullDisplayName: 'Negombo, Western Province, Sri Lanka', latitude: 7.2008, longitude: 79.8736),
    CitySuggestion(cityName: 'Batticaloa', stateName: 'Eastern Province', countryName: 'Sri Lanka', fullDisplayName: 'Batticaloa, Eastern Province, Sri Lanka', latitude: 7.7170, longitude: 81.7000),
    CitySuggestion(cityName: 'Trincomalee', stateName: 'Eastern Province', countryName: 'Sri Lanka', fullDisplayName: 'Trincomalee, Eastern Province, Sri Lanka', latitude: 8.5874, longitude: 81.2152),
    CitySuggestion(cityName: 'Anuradhapura', stateName: 'North Central', countryName: 'Sri Lanka', fullDisplayName: 'Anuradhapura, North Central, Sri Lanka', latitude: 8.3114, longitude: 80.4037),
    CitySuggestion(cityName: 'Matara', stateName: 'Southern Province', countryName: 'Sri Lanka', fullDisplayName: 'Matara, Southern Province, Sri Lanka', latitude: 5.9549, longitude: 80.5550),
    CitySuggestion(cityName: 'Gampaha', stateName: 'Western Province', countryName: 'Sri Lanka', fullDisplayName: 'Gampaha, Western Province, Sri Lanka', latitude: 7.0917, longitude: 79.9997),
    CitySuggestion(cityName: 'Kurunegala', stateName: 'North Western', countryName: 'Sri Lanka', fullDisplayName: 'Kurunegala, North Western, Sri Lanka', latitude: 7.4863, longitude: 80.3623),
    CitySuggestion(cityName: 'Ratnapura', stateName: 'Sabaragamuwa', countryName: 'Sri Lanka', fullDisplayName: 'Ratnapura, Sabaragamuwa, Sri Lanka', latitude: 6.6828, longitude: 80.4034),
    CitySuggestion(cityName: 'Nuwara Eliya', stateName: 'Central Province', countryName: 'Sri Lanka', fullDisplayName: 'Nuwara Eliya, Central Province, Sri Lanka', latitude: 6.9497, longitude: 80.7891),
  ];

  /// Fetches city/state suggestions strictly restricted to India, Nepal, and Sri Lanka (countrycodes=in,np,lk)
  static Future<List<CitySuggestion>> fetchCitySuggestions(String query) async {
    final cleanQuery = query.trim().toLowerCase();
    if (cleanQuery.isEmpty) return [];

    List<CitySuggestion> results = [];

    // 1. Instant local South Asia dataset search
    final localMatches = _southAsiaDataset.where((item) {
      return item.cityName.toLowerCase().contains(cleanQuery) ||
          item.stateName.toLowerCase().contains(cleanQuery) ||
          item.countryName.toLowerCase().contains(cleanQuery) ||
          item.fullDisplayName.toLowerCase().contains(cleanQuery);
    }).toList();

    results.addAll(localMatches);

    // 2. Query Free OpenStreetMap Nominatim API restricted strictly to INDIA, NEPAL, and SRI LANKA (`countrycodes=in,np,lk`)
    try {
      final uri = Uri.parse(
        'https://nominatim.openstreetmap.org/search?q=${Uri.encodeComponent(query)}&countrycodes=in,np,lk&format=json&addressdetails=1&limit=10',
      );

      final response = await http.get(
        uri,
        headers: {
          'User-Agent': 'CosmicGuide-FlutterApp/1.0',
        },
      ).timeout(const Duration(seconds: 3));

      if (response.statusCode == 200) {
        final List data = json.decode(response.body);
        final apiSuggestions = data.map((json) => CitySuggestion.fromNominatimJson(json)).toList();

        // Merge API suggestions avoiding duplicates
        for (var suggestion in apiSuggestions) {
          if (!results.any((r) => r.fullDisplayName.toLowerCase() == suggestion.fullDisplayName.toLowerCase())) {
            results.add(suggestion);
          }
        }
      }
    } catch (e) {
      debugPrint('Nominatim API search error: $e');
    }

    // Return up to 6 suggestions for India, Nepal & Sri Lanka
    return results.take(6).toList();
  }
}
