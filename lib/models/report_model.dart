import 'package:cloud_firestore/cloud_firestore.dart';

class ReportModel {
  final String id;
  final String reporterId;
  final String reporterName;
  final String title;
  final String body;
  final String category; // flood | fire | earthquake | landslide | other
  final String status; // pending | published | rejected
  final double latitude;
  final double longitude;
  final String? address;
  final List<String> photoUrls;
  final int? aiScore; // client-side computed severity score 0–100
  final String? moderatorId;
  final String? rejectionReason;
  final DateTime? createdAt;
  final DateTime? publishedAt;

  ReportModel({
    required this.id,
    required this.reporterId,
    required this.reporterName,
    required this.title,
    required this.body,
    required this.category,
    required this.status,
    required this.latitude,
    required this.longitude,
    this.address,
    this.photoUrls = const [],
    this.aiScore,
    this.moderatorId,
    this.rejectionReason,
    this.createdAt,
    this.publishedAt,
  });

  factory ReportModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return ReportModel(
      id: doc.id,
      reporterId: data['reporter_id'] ?? '',
      reporterName: data['reporter_name'] ?? '',
      title: data['title'] ?? '',
      body: data['body'] ?? '',
      category: data['category'] ?? 'other',
      status: data['status'] ?? 'pending',
      latitude: (data['latitude'] as num?)?.toDouble() ?? 0.0,
      longitude: (data['longitude'] as num?)?.toDouble() ?? 0.0,
      address: data['address'],
      photoUrls: List<String>.from(data['photo_urls'] ?? []),
      aiScore: data['ai_score'],
      moderatorId: data['moderator_id'],
      rejectionReason: data['rejection_reason'],
      createdAt: (data['created_at'] as Timestamp?)?.toDate(),
      publishedAt: (data['published_at'] as Timestamp?)?.toDate(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'reporter_id': reporterId,
      'reporter_name': reporterName,
      'title': title,
      'body': body,
      'category': category,
      'status': status,
      'latitude': latitude,
      'longitude': longitude,
      if (address != null) 'address': address,
      'photo_urls': photoUrls,
      if (aiScore != null) 'ai_score': aiScore,
      if (moderatorId != null) 'moderator_id': moderatorId,
      if (rejectionReason != null) 'rejection_reason': rejectionReason,
      if (createdAt != null) 'created_at': Timestamp.fromDate(createdAt!),
      if (publishedAt != null) 'published_at': Timestamp.fromDate(publishedAt!),
    };
  }
}
