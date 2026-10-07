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
    
    final state = address['state'] ?? address['region'] ?? '';
    const country = 'India';

    String displayName = '';
    if (postcode.toString().isNotEmpty) {
      displayName = '${postcode.toString().trim()} - $city';
    } else {
      displayName = '$city';
    }
    if (state.isNotEmpty && !displayName.contains(state.toString())) {
      displayName += ', $state';
    }
    displayName += ', India';

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
  // Built-in dataset strictly for Indian states & cities
  static final List<CitySuggestion> _indianDataset = [
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
    CitySuggestion(cityName: 'Noida', stateName: 'Uttar Pradesh', countryName: 'India', fullDisplayName: 'Noida, Uttar Pradesh, India', latitude: 28.5355, longitude: 77.391),
    CitySuggestion(cityName: 'Gurugram', stateName: 'Haryana', countryName: 'India', fullDisplayName: 'Gurugram, Haryana, India', latitude: 28.4595, longitude: 77.0266),
    CitySuggestion(cityName: 'Agra', stateName: 'Uttar Pradesh', countryName: 'India', fullDisplayName: 'Agra, Uttar Pradesh, India', latitude: 27.1767, longitude: 78.0081),
    CitySuggestion(cityName: 'Kanpur', stateName: 'Uttar Pradesh', countryName: 'India', fullDisplayName: 'Kanpur, Uttar Pradesh, India', latitude: 26.4499, longitude: 80.3319),
    CitySuggestion(cityName: 'Nagpur', stateName: 'Maharashtra', countryName: 'India', fullDisplayName: 'Nagpur, Maharashtra, India', latitude: 21.1458, longitude: 79.0882),
    CitySuggestion(cityName: 'Amritsar', stateName: 'Punjab', countryName: 'India', fullDisplayName: 'Amritsar, Punjab, India', latitude: 31.634, longitude: 74.8723),
    CitySuggestion(cityName: 'Dehradun', stateName: 'Uttarakhand', countryName: 'India', fullDisplayName: 'Dehradun, Uttarakhand, India', latitude: 30.3165, longitude: 78.0322),
    CitySuggestion(cityName: 'Ranchi', stateName: 'Jharkhand', countryName: 'India', fullDisplayName: 'Ranchi, Jharkhand, India', latitude: 23.3441, longitude: 85.3096),
    CitySuggestion(cityName: 'Guwahati', stateName: 'Assam', countryName: 'India', fullDisplayName: 'Guwahati, Assam, India', latitude: 26.1445, longitude: 91.7362),
    CitySuggestion(cityName: 'Bhubaneswar', stateName: 'Odisha', countryName: 'India', fullDisplayName: 'Bhubaneswar, Odisha, India', latitude: 20.2961, longitude: 85.8245),
    CitySuggestion(cityName: 'Kochi', stateName: 'Kerala', countryName: 'India', fullDisplayName: 'Kochi, Kerala, India', latitude: 9.9312, longitude: 76.2673),
    CitySuggestion(cityName: 'Thiruvananthapuram', stateName: 'Kerala', countryName: 'India', fullDisplayName: 'Thiruvananthapuram, Kerala, India', latitude: 8.5241, longitude: 76.9366),
    CitySuggestion(cityName: 'Coimbatore', stateName: 'Tamil Nadu', countryName: 'India', fullDisplayName: 'Coimbatore, Tamil Nadu, India', latitude: 11.0168, longitude: 76.9558),
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
  ];

  /// Fetches EXACTLY 5 Indian city/state suggestions using 100% Free Nominatim API (countrycodes=in) & local Indian dataset
  static Future<List<CitySuggestion>> fetchCitySuggestions(String query) async {
    final cleanQuery = query.trim().toLowerCase();
    if (cleanQuery.isEmpty) return [];

    List<CitySuggestion> results = [];

    // 1. Instant local Indian dataset search
    final localMatches = _indianDataset.where((item) {
      return item.cityName.toLowerCase().contains(cleanQuery) ||
          item.stateName.toLowerCase().contains(cleanQuery) ||
          item.fullDisplayName.toLowerCase().contains(cleanQuery);
    }).toList();

    results.addAll(localMatches);

    // 2. Query Free OpenStreetMap Nominatim API restricted strictly to INDIA (`countrycodes=in`)
    try {
      final uri = Uri.parse(
        'https://nominatim.openstreetmap.org/search?q=${Uri.encodeComponent(query)}&countrycodes=in&format=json&addressdetails=1&limit=10',
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

    // Return EXACTLY up to 5 Indian suggestions
    return results.take(5).toList();
  }
}
