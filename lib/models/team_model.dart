import 'package:cloud_firestore/cloud_firestore.dart';

class TeamModel {
  final String id;
  final String name;
  final String description;
  final String leaderId;
  final List<String> memberIds;
  final String status; // pending | active | rejected
  final DateTime? createdAt;
  final String? approvedBy;
  final DateTime? approvedAt;
  final String? rejectionReason;

  TeamModel({
    required this.id,
    required this.name,
    required this.description,
    required this.leaderId,
    required this.memberIds,
    required this.status,
    this.createdAt,
    this.approvedBy,
    this.approvedAt,
    this.rejectionReason,
  });

  factory TeamModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return TeamModel(
      id: doc.id,
      name: data['name'] ?? '',
      description: data['description'] ?? '',
      leaderId: data['leader_id'] ?? '',
      memberIds: List<String>.from(data['member_ids'] ?? []),
      status: data['status'] ?? 'pending',
      createdAt: (data['created_at'] as Timestamp?)?.toDate(),
      approvedBy: data['approved_by'],
      approvedAt: (data['approved_at'] as Timestamp?)?.toDate(),
      rejectionReason: data['rejection_reason'],
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'description': description,
      'leader_id': leaderId,
      'member_ids': memberIds,
      'status': status,
      if (createdAt != null) 'created_at': Timestamp.fromDate(createdAt!),
      if (approvedBy != null) 'approved_by': approvedBy,
      if (approvedAt != null) 'approved_at': Timestamp.fromDate(approvedAt!),
      if (rejectionReason != null) 'rejection_reason': rejectionReason,
    };
  }
}

class TeamInviteModel {
  final String id;
  final String teamId;
  final String teamName;
  final String inviteeId;
  final String inviterId;
  final String inviterName;
  final String status; // pending | accepted | declined
  final DateTime? createdAt;

  TeamInviteModel({
    required this.id,
    required this.teamId,
    required this.teamName,
    required this.inviteeId,
    required this.inviterId,
    required this.inviterName,
    required this.status,
    this.createdAt,
  });

  factory TeamInviteModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return TeamInviteModel(
      id: doc.id,
      teamId: data['team_id'] ?? '',
      teamName: data['team_name'] ?? '',
      inviteeId: data['invitee_id'] ?? '',
      inviterId: data['inviter_id'] ?? '',
      inviterName: data['inviter_name'] ?? '',
      status: data['status'] ?? 'pending',
      createdAt: (data['created_at'] as Timestamp?)?.toDate(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'team_id': teamId,
      'team_name': teamName,
      'invitee_id': inviteeId,
      'inviter_id': inviterId,
      'inviter_name': inviterName,
      'status': status,
      if (createdAt != null) 'created_at': Timestamp.fromDate(createdAt!),
    };
  }
}
