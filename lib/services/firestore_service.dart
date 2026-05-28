import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../models/alert_model.dart';
import '../models/user_model.dart';
import '../models/sos_request_model.dart';
import '../models/mission_model.dart';
import '../models/report_model.dart';
import '../models/evac_center_model.dart';
import '../models/team_model.dart';

/// Singleton Firestore service for ResQConnect.
/// All reads/writes go through this class — no Cloud Functions required.
class FirestoreService {
  // ─── Singleton ────────────────────────────────────────────────────────────
  FirestoreService._();
  static final FirestoreService instance = FirestoreService._();

  // ─── Firestore instance ───────────────────────────────────────────────────
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  // ─── Collection references ────────────────────────────────────────────────
  CollectionReference get _users => _db.collection('users');
  CollectionReference get _rescuers => _db.collection('rescuers');
  CollectionReference get _sosRequests => _db.collection('sos_requests');
  CollectionReference get _missions => _db.collection('missions');
  CollectionReference get _reports => _db.collection('reports');
  CollectionReference get _communityFeed => _db.collection('community_feed');
  CollectionReference get _alerts => _db.collection('alerts');
  CollectionReference get _evacCenters => _db.collection('evacuation_centers');
  CollectionReference get _teams => _db.collection('teams');
  CollectionReference get _teamInvites => _db.collection('team_invites');

  // ═══════════════════════════════════════════════════════════════════════════
  // STREAM METHODS  (use with StreamBuilder)
  // ═══════════════════════════════════════════════════════════════════════════

  /// Latest 5 alerts, newest first.
  Stream<List<AlertModel>> alertsStream() {
    return _alerts
        .orderBy('created_at', descending: true)
        .limit(5)
        .snapshots()
        .map(
          (snap) =>
              snap.docs.map((doc) => AlertModel.fromFirestore(doc)).toList(),
        );
  }

  /// All SOS requests with status == 'open', oldest first (FIFO dispatch).
  Stream<List<SOSRequestModel>> openSOSStream({String? excludeRescuerId}) {
    return _sosRequests
        .where('status', isEqualTo: 'open')
        .orderBy('created_at', descending: false)
        .snapshots()
        .map((snap) {
          final all = snap.docs
              .map((doc) => SOSRequestModel.fromFirestore(doc))
              .toList();

          if (excludeRescuerId == null) return all;

          return all.where((sos) {
            final deferredBy = (sos.deferredBy ?? []);
            return !deferredBy.contains(excludeRescuerId);
          }).toList();
        });
  }

  /// Reports awaiting moderation, oldest first.
  Stream<List<ReportModel>> pendingReportsStream() {
    return _reports
        .where('status', isEqualTo: 'pending')
        .orderBy('created_at', descending: false)
        .snapshots()
        .map(
          (snap) =>
              snap.docs.map((doc) => ReportModel.fromFirestore(doc)).toList(),
        );
  }

  /// Published reports, newest first (community feed source).
  Stream<List<ReportModel>> publishedReportsStream() {
    return _reports
        .where('status', isEqualTo: 'published')
        .orderBy('created_at', descending: true)
        .snapshots()
        .map(
          (snap) =>
              snap.docs.map((doc) => ReportModel.fromFirestore(doc)).toList(),
        );
  }

  /// Live updates for a single SOS request document.
  Stream<SOSRequestModel?> sosRequestStream(String sosId) {
    return _sosRequests.doc(sosId).snapshots().map((doc) {
      if (!doc.exists) return null;
      return SOSRequestModel.fromFirestore(doc);
    });
  }

  /// Live updates for a rescuer document as a raw map (null if doc missing).
  Stream<Map<String, dynamic>?> rescuerStream(String rescuerId) {
    return _rescuers.doc(rescuerId).snapshots().map((doc) {
      if (!doc.exists) return null;
      return {'id': doc.id, ...doc.data() as Map<String, dynamic>};
    });
  }

  /// All missions assigned to a specific rescuer.
  Stream<List<MissionModel>> rescuerMissionsStream(String rescuerId) {
    return _missions
        .where('rescuer_id', isEqualTo: rescuerId)
        .snapshots()
        .map(
          (snap) =>
              snap.docs.map((doc) => MissionModel.fromFirestore(doc)).toList(),
        );
  }

  /// Latest 20 community feed items, newest first.
  Stream<List<Map<String, dynamic>>> communityFeedStream() {
    return _communityFeed
        .orderBy('published_at', descending: true)
        .limit(20)
        .snapshots()
        .map(
          (snap) => snap.docs
              .map(
                (doc) => {'id': doc.id, ...doc.data() as Map<String, dynamic>},
              )
              .toList(),
        );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // NEW — EVAC CENTERS STREAMS & WRITES
  // ═══════════════════════════════════════════════════════════════════════════

  /// Live stream of all evacuation centers, ordered by name.
  /// Use this in the admin Evac Centers screen instead of the one-time
  /// [getEvacCenters()] so the list updates in real time.
  Stream<List<EvacCenterModel>> evacCentersStream() {
    return _evacCenters
        .orderBy('name')
        .snapshots()
        .map(
          (snap) => snap.docs
              .map((doc) => EvacCenterModel.fromFirestore(doc))
              .toList(),
        );
  }

  /// Updates the status of an evac center.
  /// [status] must be one of: 'open' | 'full' | 'closed'
  /// Also keeps the legacy 'is_open' field in sync for citizen map screens.
  Future<void> updateEvacCenterStatus(String centerId, String status) async {
    assert(
      ['open', 'full', 'closed'].contains(status),
      'status must be open, full, or closed',
    );
    await _evacCenters.doc(centerId).update({
      'status': status,
      'is_open': status == 'open',
      'updated_at': FieldValue.serverTimestamp(),
    });
  }

  /// Adds a new evacuation center and returns its generated document ID.
  Future<String> addEvacCenter(Map<String, dynamic> data) async {
    final ref = await _evacCenters.add({
      ...data,
      // Always write both fields for backward compatibility
      'status': data['status'] ?? 'open',
      'is_open': (data['status'] ?? 'open') == 'open',
      'is_archived': false,
      'current_occupancy': 0,
      'created_at': FieldValue.serverTimestamp(),
      'updated_at': FieldValue.serverTimestamp(),
    });
    return ref.id;
  }

  /// Archives an evac center (sets is_archived: true).
  /// Preferred over hard-delete to preserve history.
  Future<void> archiveEvacCenter(String centerId) async {
    await _evacCenters.doc(centerId).update({
      'is_archived': true,
      'archived_at': FieldValue.serverTimestamp(),
    });
  }

  /// Permanently deletes an evac center document.
  /// Use [archiveEvacCenter] instead unless you are 100% sure.
  Future<void> deleteEvacCenter(String centerId) async {
    await _evacCenters.doc(centerId).delete();
  }

  /// Updates evac center occupancy count.
  Future<void> updateEvacCenterOccupancy(
    String centerId,
    int currentOccupancy,
  ) async {
    await _evacCenters.doc(centerId).update({
      'current_occupancy': currentOccupancy,
      'updated_at': FieldValue.serverTimestamp(),
    });
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // NEW — RESCUERS STREAM (ADMIN)
  // ═══════════════════════════════════════════════════════════════════════════

  /// Live stream of ALL rescuers joined with their user profile.
  /// Returns a list of raw maps combining both 'rescuers' and 'users' data.
  /// Each map contains all rescuer fields plus 'display_name', 'email',
  /// 'photo_url' from the users collection.
  Stream<List<Map<String, dynamic>>> allRescuersStream() {
    return _rescuers.snapshots().asyncMap((snap) async {
      final result = <Map<String, dynamic>>[];

      for (final doc in snap.docs) {
        final rescuerData = doc.data() as Map<String, dynamic>;

        // Fetch matching user profile for display name, email, photo
        Map<String, dynamic> userData = {};
        try {
          final userDoc = await _users.doc(doc.id).get();
          if (userDoc.exists) {
            userData = userDoc.data() as Map<String, dynamic>;
          }
        } catch (_) {
          // If user doc missing, continue with empty userData
        }

        result.add({
          'id': doc.id,
          ...rescuerData,
          // Overlay user profile fields (display_name wins over rescuer copy)
          'display_name':
              userData['display_name'] ??
              rescuerData['display_name'] ??
              'Unknown',
          'email': userData['email'] ?? rescuerData['email'] ?? '',
          'photo_url': userData['photo_url'] ?? rescuerData['photo_url'] ?? '',
          'phone': userData['phone'] ?? rescuerData['phone'] ?? '',
        });
      }

      return result;
    });
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // NEW — USER APPROVALS (ADMIN)
  // ═══════════════════════════════════════════════════════════════════════════

  /// Live stream of all users with approval_status == 'pending', newest first.
  /// Used in the admin Approvals tab.
  Stream<List<Map<String, dynamic>>> pendingUsersStream() {
    return _users
        .where('approval_status', isEqualTo: 'pending')
        .orderBy('created_at', descending: true)
        .snapshots()
        .map(
          (snap) => snap.docs
              .map(
                (doc) => {'uid': doc.id, ...doc.data() as Map<String, dynamic>},
              )
              .toList(),
        );
  }

  /// Approves a user registration.
  /// Sets approval_status to 'approved' and records the approving admin's ID.
  Future<void> approveUser(String uid, String adminId) async {
    await _users.doc(uid).update({
      'approval_status': 'approved',
      'is_active': true,
      'approved_by': adminId,
      'approved_at': FieldValue.serverTimestamp(),
    });
  }

  /// Rejects a user registration.
  /// Sets approval_status to 'rejected', records reason and the admin's ID.
  Future<void> rejectUser(
    String uid,
    String adminId, {
    String reason = '',
  }) async {
    await _users.doc(uid).update({
      'approval_status': 'rejected',
      'is_active': false,
      'rejected_by': adminId,
      'rejected_at': FieldValue.serverTimestamp(),
      'rejection_reason': reason,
    });
  }

  /// Checks if a newly registered user is a potential duplicate.
  /// Looks for existing APPROVED users with the same email or phone.
  /// Returns a list of matching user maps (empty = no duplicates found).
  Future<List<Map<String, dynamic>>> checkDuplicateUser({
    required String email,
    String? phone,
  }) async {
    final results = <Map<String, dynamic>>[];

    // Check by email
    try {
      final emailSnap = await _users
          .where('email', isEqualTo: email)
          .where('approval_status', isEqualTo: 'approved')
          .limit(1)
          .get();
      for (final doc in emailSnap.docs) {
        results.add({'uid': doc.id, ...doc.data() as Map<String, dynamic>});
      }
    } catch (_) {}

    // Check by phone if provided and no email match yet
    if (results.isEmpty && phone != null && phone.isNotEmpty) {
      try {
        final phoneSnap = await _users
            .where('phone', isEqualTo: phone)
            .where('approval_status', isEqualTo: 'approved')
            .limit(1)
            .get();
        for (final doc in phoneSnap.docs) {
          results.add({'uid': doc.id, ...doc.data() as Map<String, dynamic>});
        }
      } catch (_) {}
    }

    return results;
  }

  /// Live stream of count of pending approvals.
  /// Used in the admin overview KPI card and nav badge.
  Stream<int> pendingApprovalsCountStream() {
    return _users
        .where('approval_status', isEqualTo: 'pending')
        .snapshots()
        .map((snap) => snap.docs.length);
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // FUTURE METHODS  (one-time reads / writes)
  // ═══════════════════════════════════════════════════════════════════════════

  // ── Users ─────────────────────────────────────────────────────────────────

  /// Alias for getUser — returns users/{uid} data map
  Future<Map<String, dynamic>?> getUserDoc(String uid) => getUser(uid);

  Future<Map<String, dynamic>?> getUser(String uid) async {
    final doc = await _users.doc(uid).get();
    if (!doc.exists) return null;
    return {'uid': doc.id, ...doc.data() as Map<String, dynamic>};
  }

  Future<void> updateUser(String uid, Map<String, dynamic> data) async {
    await _users.doc(uid).set(data, SetOptions(merge: true));
  }

  // ── SOS Requests ──────────────────────────────────────────────────────────

  Future<String> createSOSRequest(Map<String, dynamic> data) async {
    final ref = await _sosRequests.add({
      ...data,
      'created_at': FieldValue.serverTimestamp(),
      'updated_at': FieldValue.serverTimestamp(),
    });
    return ref.id;
  }

  Future<void> updateSOSRequest(String sosId, Map<String, dynamic> data) async {
    await _sosRequests.doc(sosId).update({
      ...data,
      'updated_at': FieldValue.serverTimestamp(),
    });
  }

  Future<void> updateSosRequest(String sosId, Map<String, dynamic> data) async {
    await updateSOSRequest(sosId, data);
  }

  // ── Missions ──────────────────────────────────────────────────────────────

  Future<String> createMission(Map<String, dynamic> data) async {
    final ref = await _missions.add({
      ...data,
      'created_at': FieldValue.serverTimestamp(),
    });
    return ref.id;
  }

  Future<void> updateMission(
    String missionId,
    Map<String, dynamic> data,
  ) async {
    await _missions.doc(missionId).update(data);
  }

  // ── Reports ───────────────────────────────────────────────────────────────

  Future<String> createReport(Map<String, dynamic> data) async {
    final ref = await _reports.add({
      ...data,
      'status': 'pending',
      'created_at': FieldValue.serverTimestamp(),
    });
    return ref.id;
  }

  Future<void> updateReport(String reportId, Map<String, dynamic> data) async {
    await _reports.doc(reportId).update(data);
  }

  /// Rejects a report and sends a notification to the author.
  Future<void> rejectReport(
    String reportId,
    String moderatorId,
    String reason,
  ) async {
    await _reports.doc(reportId).update({
      'status': 'rejected',
      'rejection_reason': reason,
      'reviewed_by': moderatorId,
      'reviewed_at': FieldValue.serverTimestamp(),
      'notif_read': false,
    });

    final reportDoc = await _reports.doc(reportId).get();
    final reportData = reportDoc.data() as Map<String, dynamic>? ?? {};
    final authorId =
        (reportData['author_id'] ?? reportData['reporter_id'] ?? '') as String;
    final postTitle =
        (reportData['title'] ?? reportData['type'] ?? 'Your post') as String;
  }

  Future<void> publishReport(String reportId, String moderatorId) async {
    final now = FieldValue.serverTimestamp();

    await _reports.doc(reportId).update({
      'status': 'published',
      'moderator_id': moderatorId,
      'published_at': now,
      'notif_read': false,
    });

    final reportDoc = await _reports.doc(reportId).get();
    final reportData = reportDoc.data() as Map<String, dynamic>;

    final bodyText = (reportData['text'] ?? reportData['body'] ?? '') as String;
    final mediaUrls = List<String>.from(
      reportData['media_urls'] ?? reportData['photo_urls'] ?? [],
    );
    final authorName =
        (reportData['author_name'] ??
                reportData['reporter_name'] ??
                'Anonymous')
            as String;
    final authorId =
        (reportData['author_id'] ?? reportData['reporter_id'] ?? '') as String;
    final category =
        (reportData['category'] ?? reportData['type'] ?? 'General') as String;
    final source = (reportData['source'] ?? 'incident_report') as String;

    await _communityFeed.doc(reportId).set({
      'report_id': reportId,
      'source': source,
      'text': bodyText,
      'body': bodyText,
      'title': reportData['title'] ?? '',
      'category': category,
      'type': category,
      'media_urls': mediaUrls,
      'photo_urls': mediaUrls,
      'has_video': reportData['has_video'] ?? false,
      'latitude': reportData['latitude'],
      'longitude': reportData['longitude'],
      'address': reportData['address'],
      'author_name': authorName,
      'reporter_name': authorName,
      'author_id': authorId,
      'reporter_id': authorId,
      'ai_score': reportData['ai_score'],
      'moderator_id': moderatorId,
      'published_at': now,
      'likes': 0,
      'liked_by': [],
      'comments': 0,
    });
  }

  // ── Community Feed Writes ──────────────────────────────────────────────────

  Future<String> createCommunityPost(Map<String, dynamic> data) async {
    final authorId = data['author_id'] ?? '';
    final authorName = data['author_name'] ?? 'Anonymous';
    final bodyText = data['text'] ?? '';
    final mediaUrls = data['media_urls'] ?? [];
    final postType = data['type'] ?? 'General';

    final ref = await _reports.add({
      ...data,
      'reporter_id': authorId,
      'reporter_name': authorName,
      'body': bodyText,
      'photo_urls': mediaUrls,
      'category': postType,
      'title': 'Community Post',
      'latitude': data['latitude'] ?? 0.0,
      'longitude': data['longitude'] ?? 0.0,
      'status': 'pending',
      'source': 'citizen_post',
      'created_at': FieldValue.serverTimestamp(),
    });
    return ref.id;
  }

  // ── Evacuation Centers ────────────────────────────────────────────────────

  /// One-time fetch of all evac centers as raw maps.
  /// Prefer [evacCentersStream()] for live admin screens.
  Future<List<Map<String, dynamic>>> getEvacCenters() async {
    final snap = await _evacCenters.get();
    return snap.docs
        .map((doc) => {'id': doc.id, ...doc.data() as Map<String, dynamic>})
        .toList();
  }

  // ── Rescuers ──────────────────────────────────────────────────────────────

  Future<void> updateRescuerDuty(String uid, bool isOnDuty) async {
    await _rescuers.doc(uid).set({
      'is_on_duty': isOnDuty,
      'duty_updated_at': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> updateRescuerLocation(String uid, double lat, double lng) async {
    await _rescuers.doc(uid).set({
      'latitude': lat,
      'longitude': lng,
      'location_updated_at': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> updateUserLocation(String uid, double lat, double lng) async {
    await _users.doc(uid).set({
      'latitude': lat,
      'longitude': lng,
      'location_updated_at': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Stream<UserModel?> userStream(String uid) {
    return _users
        .doc(uid)
        .snapshots()
        .map((doc) {
          if (!doc.exists) return null;
          return UserModel.fromFirestore(doc);
        })
        .handleError((e) {
          debugPrint('userStream permission error (post-logout): $e');
        });
  }

  Future<UserModel?> getUserById(String uid) async {
    final doc = await _users.doc(uid).get();
    if (!doc.exists) return null;
    return UserModel.fromFirestore(doc);
  }

  Future<Map<String, dynamic>?> getRescuerById(String uid) async {
    final doc = await _rescuers.doc(uid).get();
    if (!doc.exists) return null;
    return {'id': doc.id, ...doc.data() as Map<String, dynamic>};
  }

  Future<void> updateUserField(String uid, String field, dynamic value) async {
    await _users.doc(uid).set({field: value}, SetOptions(merge: true));
  }

  Future<List<SOSRequestModel>> getRecentSosByUser(
    String uid, {
    int limit = 5,
  }) async {
    final snap = await _sosRequests
        .where('citizen_id', isEqualTo: uid)
        .orderBy('created_at', descending: true)
        .limit(limit)
        .get();
    return snap.docs.map((doc) => SOSRequestModel.fromFirestore(doc)).toList();
  }

  Future<List<ReportModel>> getRecentReportsByUser(
    String uid, {
    int limit = 5,
  }) async {
    final snap = await _reports
        .where('reporter_id', isEqualTo: uid)
        .orderBy('created_at', descending: true)
        .limit(limit)
        .get();
    return snap.docs.map((doc) => ReportModel.fromFirestore(doc)).toList();
  }

  Future<List<ReportModel>> getPostsByUser(String uid, {int limit = 10}) async {
    final byAuthor = await _reports
        .where('author_id', isEqualTo: uid)
        .orderBy('created_at', descending: true)
        .limit(limit)
        .get();
    final byReporter = await _reports
        .where('reporter_id', isEqualTo: uid)
        .orderBy('created_at', descending: true)
        .limit(limit)
        .get();

    final seen = <String>{};
    final merged = <ReportModel>[];
    for (final doc in [...byAuthor.docs, ...byReporter.docs]) {
      if (seen.add(doc.id)) {
        merged.add(ReportModel.fromFirestore(doc));
      }
    }
    merged.sort((a, b) {
      final aTime = a.createdAt ?? DateTime(2000);
      final bTime = b.createdAt ?? DateTime(2000);
      return bTime.compareTo(aTime);
    });
    return merged.take(limit).toList();
  }

  /// Stream of citizen community posts by a specific user (source='citizen_post').
  Stream<List<Map<String, dynamic>>> userCommunityPostsStream(String uid) {
    return _reports
        .where('author_id', isEqualTo: uid)
        .where('source', isEqualTo: 'citizen_post')
        .where('status', whereIn: ['pending', 'published'])
        .orderBy('created_at', descending: true)
        .snapshots()
        .map(
          (snap) => snap.docs
              .map(
                (doc) => {'id': doc.id, ...doc.data() as Map<String, dynamic>},
              )
              .toList(),
        );
  }

  /// Stream of incident reports by a specific user (source='incident_report').
  Stream<List<ReportModel>> userReportsStream(String uid) {
    return _reports
        .where('reporter_id', isEqualTo: uid)
        .where('source', isEqualTo: 'incident_report')
        .where('status', whereIn: ['pending', 'published'])
        .orderBy('created_at', descending: true)
        .snapshots()
        .map(
          (snap) =>
              snap.docs.map((doc) => ReportModel.fromFirestore(doc)).toList(),
        );
  }

  Future<void> deleteCommunityPost(String postId) async {
    try {
      final commentsSnap = await _communityFeed
          .doc(postId)
          .collection('comments')
          .get();
      for (final doc in commentsSnap.docs) {
        await doc.reference.delete();
      }
      await _communityFeed.doc(postId).delete();
    } catch (_) {}
    await _reports.doc(postId).delete();
  }

  Future<void> deleteReport(String reportId) async {
    try {
      final commentsSnap = await _communityFeed
          .doc(reportId)
          .collection('comments')
          .get();
      for (final doc in commentsSnap.docs) {
        await doc.reference.delete();
      }
      await _communityFeed.doc(reportId).delete();
    } catch (_) {}
    await _reports.doc(reportId).delete();
  }

  Future<Set<String>> getSeenAlertIds(String uid) async {
    final doc = await _users.doc(uid).get();
    if (!doc.exists) return {};
    final data = doc.data() as Map<String, dynamic>;
    final list = data['seen_alert_ids'] as List<dynamic>? ?? [];
    return list.map((e) => e.toString()).toSet();
  }

  Future<void> markAlertsAsSeen(String uid, List<String> alertIds) async {
    await _users.doc(uid).set({
      'seen_alert_ids': alertIds,
    }, SetOptions(merge: true));
  }

  Stream<List<Map<String, dynamic>>> citizenNotificationsStream(String uid) {
    return _reports
        .where('author_id', isEqualTo: uid)
        .where('status', whereIn: ['published', 'rejected'])
        .where('notif_read', isEqualTo: false)
        .orderBy('created_at', descending: true)
        .limit(20)
        .snapshots()
        .map(
          (snap) => snap.docs.map((doc) {
            final data = doc.data() as Map<String, dynamic>;
            return {'id': doc.id, ...data};
          }).toList(),
        );
  }

  Future<List<Map<String, dynamic>>> fetchUnreadNotificationsFromServer(
    String uid,
  ) async {
    final snap = await _reports
        .where('author_id', isEqualTo: uid)
        .where('notif_read', isEqualTo: false)
        .where('status', whereIn: ['published', 'rejected'])
        .orderBy('created_at', descending: true)
        .limit(20)
        .get(const GetOptions(source: Source.server));
    return snap.docs.map((doc) {
      final data = doc.data() as Map<String, dynamic>;
      return {'id': doc.id, ...data};
    }).toList();
  }

  Future<void> markReportNotifRead(String reportId) async {
    await _reports.doc(reportId).update({'notif_read': true});
  }

  Stream<List<Map<String, dynamic>>> citizenSosNotificationsStream(String uid) {
    return _sosRequests
        .where('citizen_id', isEqualTo: uid)
        .where('status', whereIn: ['assigned', 'resolved', 'cancelled'])
        .where('sos_notif_read', isEqualTo: false)
        .orderBy('updated_at', descending: true)
        .limit(20)
        .snapshots()
        .map((snap) {
          return snap.docs.map((doc) {
            final data = doc.data() as Map<String, dynamic>;
            return {'id': doc.id, ...data};
          }).toList();
        });
  }

  Future<void> markSosNotifRead(String sosId) async {
    await _sosRequests.doc(sosId).update({'sos_notif_read': true});
  }

  Stream<List<Map<String, dynamic>>> citizenPendingPostsStream(String uid) {
    return _reports
        .where('author_id', isEqualTo: uid)
        .where('status', isEqualTo: 'pending')
        .orderBy('created_at', descending: true)
        .limit(10)
        .snapshots()
        .map((snap) {
          return snap.docs.map((doc) {
            final data = doc.data() as Map<String, dynamic>;
            return {'id': doc.id, ...data};
          }).toList();
        });
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // ENGAGEMENT NOTIFICATIONS
  // ═══════════════════════════════════════════════════════════════════════════

  Future<void> writeEngagementNotif({
    required String postOwnerUid,
    required String actorUid,
    required String actorName,
    required String postId,
    required String postSnippet,
    required String type,
    String? commentText,
  }) async {
    if (actorUid == postOwnerUid) return;

    if (type == 'like') {
      final existing = await _users
          .doc(postOwnerUid)
          .collection('notifications')
          .where('type', isEqualTo: 'like')
          .where('actor_uid', isEqualTo: actorUid)
          .where('post_id', isEqualTo: postId)
          .limit(1)
          .get();
      if (existing.docs.isNotEmpty) return;
    }

    await _users.doc(postOwnerUid).collection('notifications').add({
      'type': type,
      'actor_uid': actorUid,
      'actor_name': actorName,
      'post_id': postId,
      'post_snippet': postSnippet,
      if (commentText != null) 'comment_text': commentText,
      'created_at': FieldValue.serverTimestamp(),
      'is_read': false,
    });
  }

  Future<void> deleteEngagementLikeNotif({
    required String postOwnerUid,
    required String actorUid,
    required String postId,
  }) async {
    if (actorUid == postOwnerUid) return;

    final snap = await _users
        .doc(postOwnerUid)
        .collection('notifications')
        .where('type', isEqualTo: 'like')
        .where('actor_uid', isEqualTo: actorUid)
        .where('post_id', isEqualTo: postId)
        .limit(1)
        .get();

    for (final doc in snap.docs) {
      await doc.reference.delete();
    }
  }

  Stream<List<Map<String, dynamic>>> engagementNotificationsStream(String uid) {
    return _users
        .doc(uid)
        .collection('notifications')
        .orderBy('created_at', descending: true)
        .limit(50)
        .snapshots()
        .map(
          (snap) => snap.docs.map((doc) {
            final data = doc.data();
            return {'id': doc.id, ...data};
          }).toList(),
        );
  }

  Stream<int> unreadEngagementCountStream(String uid) {
    return _users
        .doc(uid)
        .collection('notifications')
        .where('is_read', isEqualTo: false)
        .snapshots()
        .map((snap) => snap.docs.length);
  }

  Future<void> markEngagementNotifsRead(String uid) async {
    final snap = await _users
        .doc(uid)
        .collection('notifications')
        .where('is_read', isEqualTo: false)
        .get();
    if (snap.docs.isEmpty) return;
    final batch = _db.batch();
    for (final doc in snap.docs) {
      batch.update(doc.reference, {'is_read': true});
    }
    await batch.commit();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // EXTENDED HELPERS
  // ═══════════════════════════════════════════════════════════════════════════

  Future<void> updateRescuer(String uid, Map<String, dynamic> data) async {
    await _rescuers.doc(uid).update(data);
  }

  Future<MissionModel?> getMissionById(String missionId) async {
    final doc = await _missions.doc(missionId).get();
    if (!doc.exists) return null;
    return MissionModel.fromFirestore(doc);
  }

  Future<SOSRequestModel?> getSOSRequestById(String sosId) async {
    final doc = await _sosRequests.doc(sosId).get();
    if (!doc.exists) return null;
    return SOSRequestModel.fromFirestore(doc);
  }

  Future<SOSRequestModel?> getSosRequestById(String sosId) async {
    return getSOSRequestById(sosId);
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // SPOTTED EMERGENCIES
  // ═══════════════════════════════════════════════════════════════════════════

  CollectionReference get _spottedEmergencies =>
      _db.collection('spotted_emergencies');

  Stream<List<Map<String, dynamic>>> spottedEmergenciesStream({
    String? status,
  }) {
    Query query = _spottedEmergencies.orderBy('created_at', descending: true);
    if (status != null) {
      query = query.where('status', isEqualTo: status);
    }
    return query.snapshots().map(
      (snap) => snap.docs
          .map((doc) => {'id': doc.id, ...doc.data() as Map<String, dynamic>})
          .toList(),
    );
  }

  Stream<int> pendingSpottedEmergenciesCountStream() {
    return _spottedEmergencies
        .where('status', isEqualTo: 'pending')
        .snapshots()
        .map((snap) => snap.docs.length);
  }

  Future<void> dismissSpottedEmergency(String docId) async {
    await _spottedEmergencies.doc(docId).update({
      'status': 'dismissed',
      'dismissed_at': FieldValue.serverTimestamp(),
    });
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // TEAMS
  // ═══════════════════════════════════════════════════════════════════════════

  /// Stream of all teams — for admin management.
  Stream<List<TeamModel>> allTeamsStream() {
    return _teams
        .orderBy('created_at', descending: true)
        .snapshots()
        .map(
          (snap) =>
              snap.docs.map((doc) => TeamModel.fromFirestore(doc)).toList(),
        );
  }

  /// Stream of pending teams — for admin approval badge.
  Stream<int> pendingTeamsCountStream() {
    return _teams
        .where('status', isEqualTo: 'pending')
        .snapshots()
        .map((snap) => snap.docs.length);
  }

  /// Stream of a rescuer's team (null if not in any active team).
  /// Single where clause only to avoid composite index requirement.
  Stream<TeamModel?> rescuerTeamStream(String rescuerId) {
    return _teams
        .where('member_ids', arrayContains: rescuerId)
        .snapshots()
        .map((snap) {
          final active = snap.docs.where((doc) {
            final d = doc.data() as Map<String, dynamic>;
            return d['status'] == 'active';
          }).toList();
          if (active.isEmpty) return null;
          return TeamModel.fromFirestore(active.first);
        });
  }

  /// Stream of a rescuer's pending team (submitted but not yet approved).
  /// Single where clause only to avoid composite index requirement.
  Stream<TeamModel?> rescuerPendingTeamStream(String rescuerId) {
    return _teams
        .where('member_ids', arrayContains: rescuerId)
        .snapshots()
        .map((snap) {
          final pending = snap.docs.where((doc) {
            final d = doc.data() as Map<String, dynamic>;
            return d['status'] == 'pending';
          }).toList();
          if (pending.isEmpty) return null;
          return TeamModel.fromFirestore(pending.first);
        });
  }

  /// Stream of pending invites for an invitee.
  /// No orderBy — avoids composite index requirement. Sorted in Dart instead.
  Stream<List<TeamInviteModel>> rescuerPendingInvitesStream(String rescuerId) {
    return _teamInvites
        .where('invitee_id', isEqualTo: rescuerId)
        .where('status', isEqualTo: 'pending')
        .snapshots()
        .map((snap) {
          final list = snap.docs
              .map((doc) => TeamInviteModel.fromFirestore(doc))
              .toList();
          list.sort((a, b) {
            final aTime = a.createdAt ?? DateTime(2000);
            final bTime = b.createdAt ?? DateTime(2000);
            return bTime.compareTo(aTime);
          });
          return list;
        });
  }

  /// Stream of all invites for a specific team.
  /// No orderBy — avoids composite index requirement. Sorted in Dart instead.
  Stream<List<TeamInviteModel>> teamInvitesStream(String teamId) {
    return _teamInvites
        .where('team_id', isEqualTo: teamId)
        .snapshots()
        .map((snap) {
          final list = snap.docs
              .map((doc) => TeamInviteModel.fromFirestore(doc))
              .toList();
          list.sort((a, b) {
            final aTime = a.createdAt ?? DateTime(2000);
            final bTime = b.createdAt ?? DateTime(2000);
            return bTime.compareTo(aTime);
          });
          return list;
        });
  }

  /// Creates a new team (status: pending) and returns the team ID.
  /// Also stores team_id on the leader's own user doc for reliable stream lookup.
  Future<String> createTeam({
    required String name,
    required String description,
    required String leaderId,
    Map<String, dynamic>? leaderRequirements,
  }) async {
    final ref = await _teams.add({
      'name': name,
      'description': description,
      'leader_id': leaderId,
      'member_ids': [leaderId],
      'status': 'pending',
      'created_at': FieldValue.serverTimestamp(),
      if (leaderRequirements != null && leaderRequirements.isNotEmpty)
        'leader_requirements': leaderRequirements,
    });
    // Store team_id on the leader's own user doc — used by _teamStream
    await _users.doc(leaderId).set({
      'team_id': ref.id,
      'team_joined_at': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    return ref.id;
  }

  /// Sends an invite from a team leader to a rescuer.
  Future<void> sendTeamInvite({
    required String teamId,
    required String teamName,
    required String inviterId,
    required String inviterName,
    required String inviteeId,
  }) async {
    // Check no duplicate pending invite
    final existing = await _teamInvites
        .where('team_id', isEqualTo: teamId)
        .where('invitee_id', isEqualTo: inviteeId)
        .where('status', isEqualTo: 'pending')
        .limit(1)
        .get();
    if (existing.docs.isNotEmpty) return;

    await _teamInvites.add({
      'team_id': teamId,
      'team_name': teamName,
      'invitee_id': inviteeId,
      'inviter_id': inviterId,
      'inviter_name': inviterName,
      'status': 'pending',
      'created_at': FieldValue.serverTimestamp(),
    });
  }

  /// Accepts an invite: adds rescuer to team member_ids, marks invite accepted.
  /// Also stores team_id on the user's own document as a fallback for
  /// Firestore rules that may block direct team document updates.
  Future<void> acceptTeamInvite(
    String inviteId,
    String teamId,
    String rescuerId,
  ) async {
    // 1. Mark the invite as accepted (rescuer owns their invite record)
    await _teamInvites.doc(inviteId).update({'status': 'accepted'});

    // 2. Store team_id on the rescuer's own user doc (rescuer can always
    //    write to their own user document, no rules issue)
    await _users.doc(rescuerId).set({
      'team_id': teamId,
      'team_joined_at': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    // 3. Also try to update team member_ids — may fail if rules block it,
    //    but the team screen stream will still find the team via team_id above.
    try {
      await _teams.doc(teamId).update({
        'member_ids': FieldValue.arrayUnion([rescuerId]),
      });
    } catch (e) {
      debugPrint('acceptTeamInvite: could not update team member_ids: $e');
      // Not fatal — the leader's side will see the accepted invite and
      // can manually add the member, or security rules need updating.
    }
  }

  /// Declines an invite.
  Future<void> declineTeamInvite(String inviteId) async {
    await _teamInvites.doc(inviteId).update({'status': 'declined'});
  }

  /// Submits a team to admin for approval.
  Future<void> submitTeamForApproval(String teamId) async {
    await _teams.doc(teamId).update({'status': 'pending'});
  }

  /// Admin approves a team.
  Future<void> approveTeam(String teamId, String adminId) async {
    await _teams.doc(teamId).update({
      'status': 'active',
      'approved_by': adminId,
      'approved_at': FieldValue.serverTimestamp(),
      'rejection_reason': null,
    });
  }

  /// Admin rejects a team.
  Future<void> rejectTeam(String teamId, String adminId, String reason) async {
    await _teams.doc(teamId).update({
      'status': 'rejected',
      'rejected_by': adminId,
      'rejected_at': FieldValue.serverTimestamp(),
      'rejection_reason': reason,
    });
  }

  /// Leader requests to disband their active team. Sets disband_status=pending
  /// so the admin can review it before the team is actually deactivated.
  Future<void> requestDisbandTeam({
    required String teamId,
    required String reason,
  }) async {
    await _teams.doc(teamId).update({
      'disband_status': 'pending',
      'disband_reason': reason,
      'disband_requested_at': FieldValue.serverTimestamp(),
      // Clear any previous rejection so the UI shows the fresh request
      'disband_rejected_by': null,
      'disband_rejection_reason': null,
    });
  }

  /// Admin approves the disband request: sets team status to 'disbanded'
  /// and clears the disband_status flag.
  Future<void> approveDisbandTeam(String teamId, String adminId) async {
    await _teams.doc(teamId).update({
      'status': 'disbanded',
      'disband_status': 'approved',
      'disband_approved_by': adminId,
      'disband_approved_at': FieldValue.serverTimestamp(),
    });
  }

  /// Admin rejects the disband request: clears disband_status and saves reason.
  Future<void> rejectDisbandTeam(
    String teamId,
    String adminId,
    String reason,
  ) async {
    await _teams.doc(teamId).update({
      'disband_status': 'rejected',
      'disband_rejected_by': adminId,
      'disband_rejection_reason': reason,
      'disband_requested_at': null,
    });
  }

  /// Gets all approved rescuers (for invite search).
  Future<List<Map<String, dynamic>>> getApprovedRescuers() async {
    final snap = await _users.where('role', isEqualTo: 'rescuer').get();
    return snap.docs
        .map((doc) => {'uid': doc.id, ...doc.data() as Map<String, dynamic>})
        .where((u) => u['approval_status'] == 'approved')
        .toList();
  }

  /// Stream of mission statuses for team members — for situational awareness.
  Stream<Map<String, String?>> teamMemberMissionStatusStream(
    List<String> memberIds,
  ) {
    if (memberIds.isEmpty) {
      return Stream.value({});
    }
    return _missions
        .where('rescuer_id', whereIn: memberIds)
        .where('status', whereIn: ['en_route', 'on_site'])
        .snapshots()
        .map((snap) {
          final map = <String, String?>{};
          for (final id in memberIds) {
            map[id] = null;
          }
          for (final doc in snap.docs) {
            final data = doc.data() as Map<String, dynamic>;
            final rid = data['rescuer_id'] as String? ?? '';
            if (map.containsKey(rid)) {
              map[rid] = data['status'] as String?;
            }
          }
          return map;
        });
  }

  /// Stream of the active mission assigned to the team leader.
  Stream<MissionModel?> teamLeaderActiveMissionStream(String leaderId) {
    return _missions
        .where('rescuer_id', isEqualTo: leaderId)
        .where('status', whereIn: ['en_route', 'on_site'])
        .limit(1)
        .snapshots()
        .map((snap) {
          if (snap.docs.isEmpty) return null;
          return MissionModel.fromFirestore(snap.docs.first);
        });
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // MODERATOR STATISTICS
  // ═══════════════════════════════════════════════════════════════════════════

  Stream<Map<String, dynamic>> moderatorStatsStream(String moderatorId) {
    final reviewedStream = _reports
        .where('moderator_id', isEqualTo: moderatorId)
        .limit(50)
        .snapshots();

    return reviewedStream.asyncMap((reviewedSnap) async {
      final pendingSnap = await _reports
          .where('status', isEqualTo: 'pending')
          .count()
          .get();
      final pendingCount = pendingSnap.count ?? 0;

      final reviewed = reviewedSnap.docs;

      int published = 0;
      int rejected = 0;
      int highConfidence = 0;
      int mediumConfidence = 0;
      int lowConfidence = 0;
      double totalReviewMinutes = 0;
      int reviewedWithTime = 0;

      final recentActivity = <Map<String, dynamic>>[];

      for (final doc in reviewed) {
        final data = doc.data() as Map<String, dynamic>;
        final status = data['status'] as String? ?? '';
        final aiScore = data['ai_score'] as int? ?? 0;
        final createdAt = data['created_at'] as Timestamp?;
        final publishedAt = data['published_at'] as Timestamp?;

        if (status == 'published') published++;
        if (status == 'rejected') rejected++;

        if (status == 'published') {
          if (aiScore >= 75) {
            highConfidence++;
          } else if (aiScore >= 40) {
            mediumConfidence++;
          } else {
            lowConfidence++;
          }
        }

        if (createdAt != null && publishedAt != null) {
          final diffMinutes =
              publishedAt.toDate().difference(createdAt.toDate()).inSeconds /
              60.0;
          if (diffMinutes >= 0) {
            totalReviewMinutes += diffMinutes;
            reviewedWithTime++;
          }
        }

        if (recentActivity.length < 10) {
          recentActivity.add({
            'id': doc.id,
            'category': data['category'] ?? 'other',
            'status': status,
            'published_at': publishedAt,
          });
        }
      }

      final avgReviewMinutes = reviewedWithTime > 0
          ? totalReviewMinutes / reviewedWithTime
          : 0.0;

      return {
        'published': published,
        'rejected': rejected,
        'pending': pendingCount,
        'avgReviewMinutes': avgReviewMinutes,
        'highConfidence': highConfidence,
        'mediumConfidence': mediumConfidence,
        'lowConfidence': lowConfidence,
        'recentActivity': recentActivity,
      };
    });
  }
}