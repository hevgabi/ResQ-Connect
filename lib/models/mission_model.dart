import 'package:cloud_firestore/cloud_firestore.dart';

class MissionModel {
  final String id;
  final String sosId;
  final String rescuerId;
  final String citizenId;
  final String status; // en_route | on_site | completed | cancelled
  final double citizenLatitude;
  final double citizenLongitude;
  final double? rescuerLatitude;
  final double? rescuerLongitude;
  final String? notes;
  final DateTime? createdAt;
  final DateTime? completedAt;

  MissionModel({
    required this.id,
    required this.sosId,
    required this.rescuerId,
    required this.citizenId,
    required this.status,
    required this.citizenLatitude,
    required this.citizenLongitude,
    this.rescuerLatitude,
    this.rescuerLongitude,
    this.notes,
    this.createdAt,
    this.completedAt,
  });

  factory MissionModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return MissionModel(
      id: doc.id,
      sosId: data['sos_id'] ?? '',
      rescuerId: data['rescuer_id'] ?? '',
      citizenId: data['citizen_id'] ?? '',
      status: data['status'] ?? 'en_route',
      citizenLatitude: (data['citizen_latitude'] as num?)?.toDouble() ?? 0.0,
      citizenLongitude: (data['citizen_longitude'] as num?)?.toDouble() ?? 0.0,
      rescuerLatitude: (data['rescuer_latitude'] as num?)?.toDouble(),
      rescuerLongitude: (data['rescuer_longitude'] as num?)?.toDouble(),
      notes: data['notes'],
      createdAt: (data['created_at'] as Timestamp?)?.toDate(),
      completedAt: (data['completed_at'] as Timestamp?)?.toDate(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'sos_id': sosId,
      'rescuer_id': rescuerId,
      'citizen_id': citizenId,
      'status': status,
      'citizen_latitude': citizenLatitude,
      'citizen_longitude': citizenLongitude,
      if (rescuerLatitude != null) 'rescuer_latitude': rescuerLatitude,
      if (rescuerLongitude != null) 'rescuer_longitude': rescuerLongitude,
      if (notes != null) 'notes': notes,
      if (createdAt != null) 'created_at': Timestamp.fromDate(createdAt!),
      if (completedAt != null) 'completed_at': Timestamp.fromDate(completedAt!),
    };
  }
}
