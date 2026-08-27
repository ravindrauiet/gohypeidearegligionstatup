class UserModel {
  final String uid;
  final String name;
  final String email;
  final String? phone;
  final String? address;
  final String? photoURL;
  final String role;
  final String status;
  final DateTime createdAt;
  final DateTime? updatedAt;
  final List<String> orders;
  final List<String> bookings;
  final List<String> addresses;

  UserModel({
    required this.uid,
    required this.name,
    required this.email,
    this.phone,
    this.address,
    this.photoURL,
    this.role = 'user',
    this.status = 'active',
    required this.createdAt,
    this.updatedAt,
    this.orders = const [],
    this.bookings = const [],
    this.addresses = const [],
  });

  factory UserModel.fromMap(Map<String, dynamic> map, String uid) {
    return UserModel(
      uid: uid,
      name: map['name'] ?? '',
      email: map['email'] ?? '',
      phone: map['phone'],
      address: map['address'],
      photoURL: map['photoURL'],
      role: map['role'] ?? 'user',
      status: map['status'] ?? 'active',
      createdAt: map['createdAt']?.toDate() ?? DateTime.now(),
      updatedAt: map['updatedAt']?.toDate(),
      orders: List<String>.from(map['orders'] ?? []),
      bookings: List<String>.from(map['bookings'] ?? []),
      addresses: List<String>.from(map['addresses'] ?? []),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'email': email,
      'phone': phone,
      'address': address,
      'photoURL': photoURL,
      'role': role,
      'status': status,
      'createdAt': createdAt,
      'updatedAt': updatedAt,
      'orders': orders,
      'bookings': bookings,
      'addresses': addresses,
    };
  }

  UserModel copyWith({
    String? uid,
    String? name,
    String? email,
    String? phone,
    String? address,
    String? photoURL,
    String? role,
    String? status,
    DateTime? createdAt,
    DateTime? updatedAt,
    List<String>? orders,
    List<String>? bookings,
    List<String>? addresses,
  }) {
    return UserModel(
      uid: uid ?? this.uid,
      name: name ?? this.name,
      email: email ?? this.email,
      phone: phone ?? this.phone,
      address: address ?? this.address,
      photoURL: photoURL ?? this.photoURL,
      role: role ?? this.role,
      status: status ?? this.status,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      orders: orders ?? this.orders,
      bookings: bookings ?? this.bookings,
      addresses: addresses ?? this.addresses,
    );
  }

  bool get isAdmin => role == 'admin';
  bool get isActive => status == 'active';
}



