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
  final int? numberOfPeople; // Ang original na property sa database mo
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final String? localBloodType; // Internal storage para sa blood type field

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
    this.numberOfPeople,
    this.createdAt,
    this.updatedAt,
    this.localBloodType,
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // 🔥 EXTENDED GETTERS (DITO NATIN SINALO ANG MGA CODES NA SUMASABOG SA UI)
  // ═══════════════════════════════════════════════════════════════════════════

  /// FIXED: Sumasalo kapag tinawag ng map/queue screen card ang `sos.bloodType`
  String get bloodType => localBloodType ?? 'N/A';

  /// FIXED: Sumasalo kapag tinawag ng analytics/summary dashboard ang `sos.personsCount`
  int get personsCount => numberOfPeople ?? 1;

  factory SOSRequestModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};
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
      numberOfPeople: data['number_of_people'] as int?,
      createdAt: (data['created_at'] as Timestamp?)?.toDate(),
      updatedAt: (data['updated_at'] as Timestamp?)?.toDate(),
      localBloodType:
          data['blood_type'] ??
          data['bloodType'] ??
          'N/A', // Sinisigurong null-safe mula Firestore
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
      if (numberOfPeople != null) 'number_of_people': numberOfPeople,
      'blood_type':
          bloodType, // Sinisigurong naka-save din sa database structure
      if (createdAt != null) 'created_at': Timestamp.fromDate(createdAt!),
      if (updatedAt != null) 'updated_at': Timestamp.fromDate(updatedAt!),
    };
  }
}

// Alias so screens can use either name
typedef SosRequestModel = SOSRequestModel;
