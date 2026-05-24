import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../models/alert_model.dart';
import '../models/user_model.dart';
import '../models/sos_request_model.dart';
import '../models/mission_model.dart';
import '../models/report_model.dart';
import '../models/evac_center_model.dart';

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
        .orderBy('created_at', descending: true)
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
        .map((snap) => snap.docs
        .map((doc) => EvacCenterModel.fromFirestore(doc))
        .toList());
  }

  /// Updates the status of an evac center.
  /// [status] must be one of: 'open' | 'full' | 'closed'
  /// Also keeps the legacy 'is_open' field in sync for citizen map screens.
  Future<void> updateEvacCenterStatus(
      String centerId,
      String status,
      ) async {
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
          'display_name': userData['display_name'] ??
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

  /// Live stream of all users with status == 'pending', newest first.
  /// Used in the admin Approvals tab.
  Stream<List<Map<String, dynamic>>> pendingUsersStream() {
    return _users
        .where('status', isEqualTo: 'pending')
        .orderBy('created_at', descending: true)
        .snapshots()
        .map((snap) => snap.docs
        .map((doc) => {
      'uid': doc.id,
      ...doc.data() as Map<String, dynamic>,
    })
        .toList());
  }

  /// Approves a user registration.
  /// Sets status to 'approved' and records the approving admin's ID.
  Future<void> approveUser(String uid, String adminId) async {
    await _users.doc(uid).update({
      'status': 'approved',
      'approved_by': adminId,
      'approved_at': FieldValue.serverTimestamp(),
    });
  }

  /// Rejects a user registration.
  /// Sets status to 'rejected', records reason and the admin's ID.
  Future<void> rejectUser(
      String uid,
      String adminId, {
        String reason = '',
      }) async {
    await _users.doc(uid).update({
      'status': 'rejected',
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
          .where('status', isEqualTo: 'approved')
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
            .where('status', isEqualTo: 'approved')
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
        .where('status', isEqualTo: 'pending')
        .snapshots()
        .map((snap) => snap.docs.length);
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // FUTURE METHODS  (one-time reads / writes)
  // ═══════════════════════════════════════════════════════════════════════════

  // ── Users ─────────────────────────────────────────────────────────────────

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

  Future<void> publishReport(String reportId, String moderatorId) async {
    final now = FieldValue.serverTimestamp();

    await _reports.doc(reportId).update({
      'status': 'published',
      'moderator_id': moderatorId,
      'published_at': now,
    });

    final reportDoc = await _reports.doc(reportId).get();
    final reportData = reportDoc.data() as Map<String, dynamic>;

    await _communityFeed.doc(reportId).set({
      'report_id': reportId,
      'title': reportData['title'],
      'body': reportData['body'],
      'category': reportData['category'],
      'latitude': reportData['latitude'],
      'longitude': reportData['longitude'],
      'address': reportData['address'],
      'photo_urls': reportData['photo_urls'] ?? [],
      'ai_score': reportData['ai_score'],
      'reporter_name': reportData['reporter_name'],
      'moderator_id': moderatorId,
      'published_at': now,
    });
  }

  // ── Community Feed Writes ──────────────────────────────────────────────────

  /// Directly creates a post on the public community feed.
  /// Invoked by citizens when submitting announcements or safe updates.
  Future<String> createCommunityPost(Map<String, dynamic> data) async {
    final ref = await _communityFeed.add({
      ...data,
      'published_at': FieldValue.serverTimestamp(),
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
    }).handleError((e) {
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