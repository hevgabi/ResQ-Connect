import 'package:cloud_firestore/cloud_firestore.dart';

class AlertModel {
  final String id;
  final String title;
  final String message;
  final String severity; // info | warning | danger
  final String? type;
  final String? region; // null means nationwide
  final String? sourceUrl;
  final DateTime? createdAt;
  final DateTime? expiresAt;

  AlertModel({
    required this.id,
    required this.title,
    required this.message,
    required this.severity,
    this.type,
    this.region,
    this.sourceUrl,
    this.createdAt,
    this.expiresAt,
  });

  factory AlertModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return AlertModel(
      id: doc.id,
      title: data['title'] ?? '',
      message: data['message'] ?? '',
      severity: data['severity'] ?? 'info',
      type: data['type'],
      region: data['region'],
      sourceUrl: data['source_url'],
      createdAt: (data['created_at'] as Timestamp?)?.toDate(),
      expiresAt: (data['expires_at'] as Timestamp?)?.toDate(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'title': title,
      'message': message,
      'severity': severity,
      if (region != null) 'region': region,
      if (sourceUrl != null) 'source_url': sourceUrl,
      if (createdAt != null) 'created_at': Timestamp.fromDate(createdAt!),
      if (expiresAt != null) 'expires_at': Timestamp.fromDate(expiresAt!),
    };
  }
}
