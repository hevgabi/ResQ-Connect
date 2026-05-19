import 'package:cloud_firestore/cloud_firestore.dart';

class UserModel {
  final String uid;
  final String name;
  final String email;
  final String role; // citizen | rescuer | moderator | admin
  final String? photoUrl;
  final String? phone;
  final DateTime? createdAt;

  // Extended fields used in citizen/rescuer profile screens
  final String? firstName;
  final String? lastName;
  final String? bloodType;
  final String? allergies;

  UserModel({
    required this.uid,
    required this.name,
    required this.email,
    required this.role,
    this.photoUrl,
    this.phone,
    this.createdAt,
    this.firstName,
    this.lastName,
    this.bloodType,
    this.allergies,
  });

  /// Convenience getter: returns displayName or falls back to full name or email.
  String? get displayName {
    final full = '${firstName ?? ''} ${lastName ?? ''}'.trim();
    if (full.isNotEmpty) return full;
    if (name.isNotEmpty) return name;
    return null;
  }

  factory UserModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return UserModel(
      uid: doc.id,
      name: '${data['first_name'] ?? ''} ${data['last_name'] ?? ''}'.trim(),
      email: data['email'] ?? '',
      role: data['role'] ?? 'citizen',
      photoUrl: data['photo_url'],
      phone: data['phone'],
      createdAt: (data['created_at'] as Timestamp?)?.toDate(),
      firstName: data['first_name'],
      lastName: data['last_name'],
      bloodType: data['blood_type'],
      allergies: data['allergies'],
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'email': email,
      'role': role,
      if (photoUrl != null) 'photo_url': photoUrl,
      if (phone != null) 'phone': phone,
      if (createdAt != null) 'created_at': Timestamp.fromDate(createdAt!),
      if (firstName != null) 'first_name': firstName,
      if (lastName != null) 'last_name': lastName,
      if (bloodType != null) 'blood_type': bloodType,
      if (allergies != null) 'allergies': allergies,
    };
  }
}
