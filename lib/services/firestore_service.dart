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
  Stream<List<SOSRequestModel>> openSOSStream() {
    return _sosRequests
        .where('status', isEqualTo: 'open')
        .orderBy('created_at', descending: false)
        .snapshots()
        .map(
          (snap) => snap.docs
              .map((doc) => SOSRequestModel.fromFirestore(doc))
              .toList(),
        );
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
  /// Returns raw maps so callers can render mixed content types.
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
  // FUTURE METHODS  (one-time reads / writes)
  // ═══════════════════════════════════════════════════════════════════════════

  // ── Users ─────────────────────────────────────────────────────────────────

  /// Fetch a user's Firestore profile. Returns null if the document doesn't exist.
  Future<Map<String, dynamic>?> getUser(String uid) async {
    final doc = await _users.doc(uid).get();
    if (!doc.exists) return null;
    return {'uid': doc.id, ...doc.data() as Map<String, dynamic>};
  }

  /// Merge [data] into the user document (creates the doc if missing).
  Future<void> updateUser(String uid, Map<String, dynamic> data) async {
    await _users.doc(uid).set(data, SetOptions(merge: true));
  }

  // ── SOS Requests ──────────────────────────────────────────────────────────

  /// Creates a new SOS request and returns its generated document ID.
  Future<String> createSOSRequest(Map<String, dynamic> data) async {
    final ref = await _sosRequests.add({
      ...data,
      'created_at': FieldValue.serverTimestamp(),
      'updated_at': FieldValue.serverTimestamp(),
    });
    return ref.id;
  }

  /// Merges [data] into an existing SOS request and stamps updated_at.
  Future<void> updateSOSRequest(String sosId, Map<String, dynamic> data) async {
    await _sosRequests.doc(sosId).update({
      ...data,
      'updated_at': FieldValue.serverTimestamp(),
    });
  }

  /// Fallback method naming to handle lower-case screen callers dynamically
  Future<void> updateSosRequest(String sosId, Map<String, dynamic> data) async {
    await updateSOSRequest(sosId, data);
  }

  // ── Missions ──────────────────────────────────────────────────────────────

  /// Creates a new mission document and returns its generated document ID.
  Future<String> createMission(Map<String, dynamic> data) async {
    final ref = await _missions.add({
      ...data,
      'created_at': FieldValue.serverTimestamp(),
    });
    return ref.id;
  }

  /// Updates an existing mission document.
  Future<void> updateMission(
    String missionId,
    Map<String, dynamic> data,
  ) async {
    await _missions.doc(missionId).update(data);
  }

  // ── Reports ───────────────────────────────────────────────────────────────

  /// Submits a new incident report and returns its generated document ID.
  Future<String> createReport(Map<String, dynamic> data) async {
    final ref = await _reports.add({
      ...data,
      'status': 'pending',
      'created_at': FieldValue.serverTimestamp(),
    });
    return ref.id;
  }

  /// Updates an existing report document.
  Future<void> updateReport(String reportId, Map<String, dynamic> data) async {
    await _reports.doc(reportId).update(data);
  }

  /// Publishes a report: sets status to 'published', records moderator + timestamp.
  /// Also writes the report to community_feed as a denormalised copy.
  Future<void> publishReport(String reportId, String moderatorId) async {
    final now = FieldValue.serverTimestamp();

    // 1. Update the report document.
    await _reports.doc(reportId).update({
      'status': 'published',
      'moderator_id': moderatorId,
      'published_at': now,
    });

    // 2. Fetch the updated snapshot to denormalise into community_feed.
    final reportDoc = await _reports.doc(reportId).get();
    final reportData = reportDoc.data() as Map<String, dynamic>;

    // 3. Write to community_feed (client-side replacement for Cloud Function trigger).
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

  // ── Evacuation Centers ────────────────────────────────────────────────────

  /// FIXED: Ginawang List<Map<String, dynamic>> representation para compatible
  /// sa custom processing loops ng UI components mo.
  Future<List<Map<String, dynamic>>> getEvacCenters() async {
    final snap = await _evacCenters.get();
    return snap.docs
        .map((doc) => {'id': doc.id, ...doc.data() as Map<String, dynamic>})
        .toList();
  }

  // ── Rescuers ──────────────────────────────────────────────────────────────

  /// Toggles a rescuer's on-duty status.
  Future<void> updateRescuerDuty(String uid, bool isOnDuty) async {
    await _rescuers.doc(uid).set({
      'is_on_duty': isOnDuty,
      'duty_updated_at': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  /// Updates a rescuer's last-known GPS coordinates.
  /// Called periodically from LocationService while the rescuer is on duty.
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
          // Firestore throws PERMISSION_DENIED after logout — ignore silently.
          // _RootRouter will automatically redirect to LoginScreen.
          debugPrint('userStream permission error (post-logout): $e');
        });
  }

  /// Fetch a user document as a [UserModel]. Returns null if not found.
  Future<UserModel?> getUserById(String uid) async {
    final doc = await _users.doc(uid).get();
    if (!doc.exists) return null;
    return UserModel.fromFirestore(doc);
  }

  /// Fetch a rescuer document as a raw map. Returns null if not found.
  Future<Map<String, dynamic>?> getRescuerById(String uid) async {
    final doc = await _rescuers.doc(uid).get();
    if (!doc.exists) return null;
    return {'id': doc.id, ...doc.data() as Map<String, dynamic>};
  }

  /// Update a single field on a user document (merge-safe).
  Future<void> updateUserField(String uid, String field, dynamic value) async {
    await _users.doc(uid).set({field: value}, SetOptions(merge: true));
  }

  /// Returns the [limit] most-recent SOS requests by a given citizen.
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

  /// Returns the [limit] most-recent reports by a given reporter.
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
  // EXTENDED HELPERS ADDED FOR THE SCREENS (FIXES COMPILATION ERRORS)
  // ═══════════════════════════════════════════════════════════════════════════

  /// Updates fields inside the 'rescuers' collection (e.g. active_mission_count).
  Future<void> updateRescuer(String uid, Map<String, dynamic> data) async {
    await _rescuers.doc(uid).update(data);
  }

  /// Fetches a specific mission by its ID.
  Future<MissionModel?> getMissionById(String missionId) async {
    final doc = await _missions.doc(missionId).get();
    if (!doc.exists) return null;
    return MissionModel.fromFirestore(doc);
  }

  /// FIXED: Inalign sa unified PascalCase naming 'getSOSRequestById' para walang lito
  Future<SOSRequestModel?> getSOSRequestById(String sosId) async {
    final doc = await _sosRequests.doc(sosId).get();
    if (!doc.exists) return null;
    return SOSRequestModel.fromFirestore(doc);
  }

  /// Fallback method for camelCase callers from the automated UI pipeline
  Future<SOSRequestModel?> getSosRequestById(String sosId) async {
    return getSOSRequestById(sosId);
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // MODERATOR STATISTICS
  // ═══════════════════════════════════════════════════════════════════════════

  /// Real-time stream of aggregated statistics for a specific moderator.
  /// Returns a map with: published, rejected, pending, avgReviewMinutes,
  /// highConfidence, mediumConfidence, lowConfidence, recentActivity.
  Stream<Map<String, dynamic>> moderatorStatsStream(String moderatorId) {
    // Combine two streams: reviewed reports (by this moderator) + all pending
    final reviewedStream = _reports
        .where('moderator_id', isEqualTo: moderatorId)
        .limit(50)
        .snapshots();

    final pendingStream = _reports
        .where('status', isEqualTo: 'pending')
        .snapshots();

    return reviewedStream.asyncMap((reviewedSnap) async {
      // Get pending count separately (one-time read to avoid double stream)
      final pendingSnap = await _reports
          .where('status', isEqualTo: 'pending')
          .count()
          .get();
      final pendingCount = pendingSnap.count ?? 0;

      final reviewed = reviewedSnap.docs;

      // Counts
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

        // Count by status
        if (status == 'published') published++;
        if (status == 'rejected') rejected++;

        // AI score breakdown (only published)
        if (status == 'published') {
          if (aiScore >= 75) {
            highConfidence++;
          } else if (aiScore >= 40) {
            mediumConfidence++;
          } else {
            lowConfidence++;
          }
        }

        // Avg review time
        if (createdAt != null && publishedAt != null) {
          final diffMinutes =
              publishedAt.toDate().difference(createdAt.toDate()).inSeconds /
              60.0;
          if (diffMinutes >= 0) {
            totalReviewMinutes += diffMinutes;
            reviewedWithTime++;
          }
        }

        // Recent activity (last 10)
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
