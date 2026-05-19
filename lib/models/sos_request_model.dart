import 'package:cloud_firestore/cloud_firestore.dart';

class SOSRequestModel {
  final String id;
  final String citizenId;
  final String citizenName;
  final double latitude;
  final double longitude;
  final String? address;
  final String status; // open | assigned | resolved | cancelled
  final String? description;
  final String? photoUrl;
  final int? aiScore; // client-side computed urgency score 0–100
  final String? assignedRescuerId;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  SOSRequestModel({
    required this.id,
    required this.citizenId,
    required this.citizenName,
    required this.latitude,
    required this.longitude,
    this.address,
    required this.status,
    this.description,
    this.photoUrl,
    this.aiScore,
    this.assignedRescuerId,
    this.createdAt,
    this.updatedAt,
  });

  factory SOSRequestModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return SOSRequestModel(
      id: doc.id,
      citizenId: data['citizen_id'] ?? '',
      citizenName: data['citizen_name'] ?? '',
      latitude: (data['latitude'] as num?)?.toDouble() ?? 0.0,
      longitude: (data['longitude'] as num?)?.toDouble() ?? 0.0,
      address: data['address'],
      status: data['status'] ?? 'open',
      description: data['description'],
      photoUrl: data['photo_url'],
      aiScore: data['ai_score'],
      assignedRescuerId: data['assigned_rescuer_id'],
      createdAt: (data['created_at'] as Timestamp?)?.toDate(),
      updatedAt: (data['updated_at'] as Timestamp?)?.toDate(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'citizen_id': citizenId,
      'citizen_name': citizenName,
      'latitude': latitude,
      'longitude': longitude,
      if (address != null) 'address': address,
      'status': status,
      if (description != null) 'description': description,
      if (photoUrl != null) 'photo_url': photoUrl,
      if (aiScore != null) 'ai_score': aiScore,
      if (assignedRescuerId != null) 'assigned_rescuer_id': assignedRescuerId,
      if (createdAt != null) 'created_at': Timestamp.fromDate(createdAt!),
      if (updatedAt != null) 'updated_at': Timestamp.fromDate(updatedAt!),
    };
  }
}
