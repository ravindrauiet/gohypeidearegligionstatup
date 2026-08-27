import 'package:cloud_firestore/cloud_firestore.dart';

class AddressModel {
  final String id;
  final String type; // 'Home', 'Office', 'Other'
  final String fullName;
  final String phoneNumber;
  final String addressLine1;
  final String? addressLine2;
  final String city;
  final String state;
  final String pincode;
  final String country;
  final bool isDefault;
  final DateTime createdAt;

  AddressModel({
    required this.id,
    required this.type,
    required this.fullName,
    required this.phoneNumber,
    required this.addressLine1,
    this.addressLine2,
    required this.city,
    required this.state,
    required this.pincode,
    this.country = 'India',
    this.isDefault = false,
    required this.createdAt,
  });

  // Create from Map (e.g., from Firestore)
  factory AddressModel.fromMap(Map<String, dynamic> map) {
    DateTime parseCreatedAt(dynamic value) {
      if (value == null) return DateTime.now();
      
      if (value is DateTime) return value;
      
      if (value is Timestamp) return value.toDate();
      
      if (value is String) {
        try {
          return DateTime.parse(value);
        } catch (e) {
          return DateTime.now();
        }
      }
      
      return DateTime.now();
    }

    return AddressModel(
      id: map['id'] ?? '',
      type: map['type'] ?? 'Home',
      fullName: map['fullName'] ?? '',
      phoneNumber: map['phoneNumber'] ?? '',
      addressLine1: map['addressLine1'] ?? '',
      addressLine2: map['addressLine2'],
      city: map['city'] ?? '',
      state: map['state'] ?? '',
      pincode: map['pincode'] ?? '',
      country: map['country'] ?? 'India',
      isDefault: map['isDefault'] ?? false,
      createdAt: parseCreatedAt(map['createdAt']),
    );
  }

  // Convert to Map (e.g., for Firestore)
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'type': type,
      'fullName': fullName,
      'phoneNumber': phoneNumber,
      'addressLine1': addressLine1,
      'addressLine2': addressLine2,
      'city': city,
      'state': state,
      'pincode': pincode,
      'country': country,
      'isDefault': isDefault,
      'createdAt': createdAt.toIso8601String(),
    };
  }

  // Convert to Map for Firestore (with proper Timestamp)
  Map<String, dynamic> toFirestoreMap() {
    return {
      'id': id,
      'type': type,
      'fullName': fullName,
      'phoneNumber': phoneNumber,
      'addressLine1': addressLine1,
      'addressLine2': addressLine2,
      'city': city,
      'state': state,
      'pincode': pincode,
      'country': country,
      'isDefault': isDefault,
      'createdAt': Timestamp.fromDate(createdAt),
    };
  }

  // Create a copy with updated fields
  AddressModel copyWith({
    String? id,
    String? type,
    String? fullName,
    String? phoneNumber,
    String? addressLine1,
    String? addressLine2,
    String? city,
    String? state,
    String? pincode,
    String? country,
    bool? isDefault,
    DateTime? createdAt,
  }) {
    return AddressModel(
      id: id ?? this.id,
      type: type ?? this.type,
      fullName: fullName ?? this.fullName,
      phoneNumber: phoneNumber ?? this.phoneNumber,
      addressLine1: addressLine1 ?? this.addressLine1,
      addressLine2: addressLine2 ?? this.addressLine2,
      city: city ?? this.city,
      state: state ?? this.state,
      pincode: pincode ?? this.pincode,
      country: country ?? this.country,
      isDefault: isDefault ?? this.isDefault,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  // Get full address as a formatted string
  String get fullAddress {
    final parts = [
      addressLine1,
      if (addressLine2 != null && addressLine2!.isNotEmpty) addressLine2,
      city,
      state,
      pincode,
      if (country != 'India') country,
    ].where((part) => part != null && part.isNotEmpty).toList();
    
    return parts.join(', ');
  }

  // Get short address (city, state)
  String get shortAddress {
    return '$city, $state';
  }

  // Validate address
  bool get isValid {
    return fullName.isNotEmpty &&
           phoneNumber.isNotEmpty &&
           addressLine1.isNotEmpty &&
           city.isNotEmpty &&
           state.isNotEmpty &&
           pincode.isNotEmpty;
  }

  // Get display name for address type
  String get displayType {
    switch (type.toLowerCase()) {
      case 'home':
        return 'Home';
      case 'office':
        return 'Office';
      case 'other':
        return 'Other';
      default:
        return type;
    }
  }

  @override
  String toString() {
    return 'AddressModel(id: $id, type: $type, fullName: $fullName, city: $city, state: $state)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is AddressModel && other.id == id;
  }

  @override
  int get hashCode => id.hashCode;
}

