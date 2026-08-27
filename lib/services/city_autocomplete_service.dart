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
    final city = address['city'] ??
        address['town'] ??
        address['village'] ??
        address['municipality'] ??
        address['county'] ??
        address['state_district'] ??
        json['display_name'].split(',')[0];
    
    final state = address['state'] ?? address['region'] ?? '';
    const country = 'India';

    String displayName = '$city';
    if (state.isNotEmpty) displayName += ', $state';
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
    CitySuggestion(cityName: 'New Delhi', stateName: 'Delhi', countryName: 'India', fullDisplayName: 'New Delhi, Delhi, India'),
    CitySuggestion(cityName: 'Delhi', stateName: 'Delhi', countryName: 'India', fullDisplayName: 'Delhi, India'),
    CitySuggestion(cityName: 'Mumbai', stateName: 'Maharashtra', countryName: 'India', fullDisplayName: 'Mumbai, Maharashtra, India'),
    CitySuggestion(cityName: 'Bengaluru', stateName: 'Karnataka', countryName: 'India', fullDisplayName: 'Bengaluru, Karnataka, India'),
    CitySuggestion(cityName: 'Kolkata', stateName: 'West Bengal', countryName: 'India', fullDisplayName: 'Kolkata, West Bengal, India'),
    CitySuggestion(cityName: 'Chennai', stateName: 'Tamil Nadu', countryName: 'India', fullDisplayName: 'Chennai, Tamil Nadu, India'),
    CitySuggestion(cityName: 'Hyderabad', stateName: 'Telangana', countryName: 'India', fullDisplayName: 'Hyderabad, Telangana, India'),
    CitySuggestion(cityName: 'Pune', stateName: 'Maharashtra', countryName: 'India', fullDisplayName: 'Pune, Maharashtra, India'),
    CitySuggestion(cityName: 'Ahmedabad', stateName: 'Gujarat', countryName: 'India', fullDisplayName: 'Ahmedabad, Gujarat, India'),
    CitySuggestion(cityName: 'Jaipur', stateName: 'Rajasthan', countryName: 'India', fullDisplayName: 'Jaipur, Rajasthan, India'),
    CitySuggestion(cityName: 'Lucknow', stateName: 'Uttar Pradesh', countryName: 'India', fullDisplayName: 'Lucknow, Uttar Pradesh, India'),
    CitySuggestion(cityName: 'Chandigarh', stateName: 'Punjab & Haryana', countryName: 'India', fullDisplayName: 'Chandigarh, India'),
    CitySuggestion(cityName: 'Patna', stateName: 'Bihar', countryName: 'India', fullDisplayName: 'Patna, Bihar, India'),
    CitySuggestion(cityName: 'Bhopal', stateName: 'Madhya Pradesh', countryName: 'India', fullDisplayName: 'Bhopal, Madhya Pradesh, India'),
    CitySuggestion(cityName: 'Surat', stateName: 'Gujarat', countryName: 'India', fullDisplayName: 'Surat, Gujarat, India'),
    CitySuggestion(cityName: 'Indore', stateName: 'Madhya Pradesh', countryName: 'India', fullDisplayName: 'Indore, Madhya Pradesh, India'),
    CitySuggestion(cityName: 'Varanasi', stateName: 'Uttar Pradesh', countryName: 'India', fullDisplayName: 'Varanasi, Uttar Pradesh, India'),
    CitySuggestion(cityName: 'Noida', stateName: 'Uttar Pradesh', countryName: 'India', fullDisplayName: 'Noida, Uttar Pradesh, India'),
    CitySuggestion(cityName: 'Gurugram', stateName: 'Haryana', countryName: 'India', fullDisplayName: 'Gurugram, Haryana, India'),
    CitySuggestion(cityName: 'Agra', stateName: 'Uttar Pradesh', countryName: 'India', fullDisplayName: 'Agra, Uttar Pradesh, India'),
    CitySuggestion(cityName: 'Kanpur', stateName: 'Uttar Pradesh', countryName: 'India', fullDisplayName: 'Kanpur, Uttar Pradesh, India'),
    CitySuggestion(cityName: 'Nagpur', stateName: 'Maharashtra', countryName: 'India', fullDisplayName: 'Nagpur, Maharashtra, India'),
    CitySuggestion(cityName: 'Amritsar', stateName: 'Punjab', countryName: 'India', fullDisplayName: 'Amritsar, Punjab, India'),
    CitySuggestion(cityName: 'Dehradun', stateName: 'Uttarakhand', countryName: 'India', fullDisplayName: 'Dehradun, Uttarakhand, India'),
    CitySuggestion(cityName: 'Ranchi', stateName: 'Jharkhand', countryName: 'India', fullDisplayName: 'Ranchi, Jharkhand, India'),
    CitySuggestion(cityName: 'Guwahati', stateName: 'Assam', countryName: 'India', fullDisplayName: 'Guwahati, Assam, India'),
    CitySuggestion(cityName: 'Bhubaneswar', stateName: 'Odisha', countryName: 'India', fullDisplayName: 'Bhubaneswar, Odisha, India'),
    CitySuggestion(cityName: 'Kochi', stateName: 'Kerala', countryName: 'India', fullDisplayName: 'Kochi, Kerala, India'),
    CitySuggestion(cityName: 'Thiruvananthapuram', stateName: 'Kerala', countryName: 'India', fullDisplayName: 'Thiruvananthapuram, Kerala, India'),
    CitySuggestion(cityName: 'Coimbatore', stateName: 'Tamil Nadu', countryName: 'India', fullDisplayName: 'Coimbatore, Tamil Nadu, India'),
    CitySuggestion(cityName: 'Vadodara', stateName: 'Gujarat', countryName: 'India', fullDisplayName: 'Vadodara, Gujarat, India'),
    CitySuggestion(cityName: 'Ghaziabad', stateName: 'Uttar Pradesh', countryName: 'India', fullDisplayName: 'Ghaziabad, Uttar Pradesh, India'),
    CitySuggestion(cityName: 'Ludhiana', stateName: 'Punjab', countryName: 'India', fullDisplayName: 'Ludhiana, Punjab, India'),
    CitySuggestion(cityName: 'Prayagraj', stateName: 'Uttar Pradesh', countryName: 'India', fullDisplayName: 'Prayagraj, Uttar Pradesh, India'),
    CitySuggestion(cityName: 'Gorakhpur', stateName: 'Uttar Pradesh', countryName: 'India', fullDisplayName: 'Gorakhpur, Uttar Pradesh, India'),
    CitySuggestion(cityName: 'Jodhpur', stateName: 'Rajasthan', countryName: 'India', fullDisplayName: 'Jodhpur, Rajasthan, India'),
    CitySuggestion(cityName: 'Udaipur', stateName: 'Rajasthan', countryName: 'India', fullDisplayName: 'Udaipur, Rajasthan, India'),
    CitySuggestion(cityName: 'Gwalior', stateName: 'Madhya Pradesh', countryName: 'India', fullDisplayName: 'Gwalior, Madhya Pradesh, India'),
    CitySuggestion(cityName: 'Raipur', stateName: 'Chhattisgarh', countryName: 'India', fullDisplayName: 'Raipur, Chhattisgarh, India'),
    CitySuggestion(cityName: 'Shimla', stateName: 'Himachal Pradesh', countryName: 'India', fullDisplayName: 'Shimla, Himachal Pradesh, India'),
    CitySuggestion(cityName: 'Jammu', stateName: 'Jammu and Kashmir', countryName: 'India', fullDisplayName: 'Jammu, J&K, India'),
    CitySuggestion(cityName: 'Srinagar', stateName: 'Jammu and Kashmir', countryName: 'India', fullDisplayName: 'Srinagar, J&K, India'),
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
          'User-Agent': 'AstroAI-FlutterApp/1.0',
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
