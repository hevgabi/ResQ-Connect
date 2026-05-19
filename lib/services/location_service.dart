import 'dart:math';
import 'package:geolocator/geolocator.dart';

/// Singleton location service for ResQConnect.
///
/// Wraps [geolocator] to handle permissions cleanly and exposes:
/// - one-shot position reads
/// - a live position stream (used for rescuer tracking)
/// - Haversine distance calculation (client-side nearest-rescuer logic)
class LocationService {
  // ─── Singleton ────────────────────────────────────────────────────────────
  LocationService._();
  static final LocationService instance = LocationService._();

  // ─── Location settings ────────────────────────────────────────────────────

  /// High-accuracy stream: updates every 10 m of movement.
  /// 10 m filter keeps Firestore writes reasonable while still tracking rescuers
  /// accurately through narrow Philippine streets and alleys.
  static const _streamSettings = LocationSettings(
    accuracy: LocationAccuracy.high,
    distanceFilter: 10, // metres
  );

  // ═══════════════════════════════════════════════════════════════════════════
  // PERMISSION
  // ═══════════════════════════════════════════════════════════════════════════

  /// Requests location permission if not already granted.
  ///
  /// Returns `true` when the app has [LocationPermission.always] or
  /// [LocationPermission.whileInUse]. Returns `false` for denied / permanently
  /// denied states, so callers can show an in-app explanation banner instead
  /// of crashing.
  Future<bool> requestPermission() async {
    // Check whether the device's location service is enabled at all.
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return false;

    LocationPermission permission = await Geolocator.checkPermission();

    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    return permission == LocationPermission.always ||
        permission == LocationPermission.whileInUse;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // ONE-SHOT READ
  // ═══════════════════════════════════════════════════════════════════════════

  /// Returns the device's current position, or `null` if permission is denied
  /// or the location service is unavailable.
  ///
  /// Uses [LocationAccuracy.high] for the initial fix so the SOS pin and
  /// rescuer dispatch start from the most accurate coordinates possible.
  Future<Position?> getCurrentPosition() async {
    final granted = await requestPermission();
    if (!granted) return null;

    try {
      return await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      );
    } catch (_) {
      return null;
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // LIVE STREAM
  // ═══════════════════════════════════════════════════════════════════════════

  /// A continuous stream of [Position] updates.
  ///
  /// Used by the rescuer's active-navigation screen to push live coordinates
  /// to Firestore so citizens can watch rescuer movement in real time.
  ///
  /// The stream will emit errors if permission is revoked mid-session; callers
  /// should handle with [StreamBuilder]'s `hasError` branch.
  Stream<Position> getPositionStream() {
    return Geolocator.getPositionStream(locationSettings: _streamSettings);
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // HAVERSINE DISTANCE
  // ═══════════════════════════════════════════════════════════════════════════

  /// Calculates the great-circle distance between two WGS-84 coordinates.
  ///
  /// Returns the result in **kilometres**.
  ///
  /// Used by the Flutter client to find the nearest on-duty rescuer from a
  /// list fetched from Firestore — replacing what would otherwise need a
  /// Cloud Function or a geo-query library.
  ///
  /// Formula: https://en.wikipedia.org/wiki/Haversine_formula
  double calculateDistance(double lat1, double lng1, double lat2, double lng2) {
    const earthRadiusKm = 6371.0;

    final dLat = _toRadians(lat2 - lat1);
    final dLng = _toRadians(lng2 - lng1);

    final a =
        sin(dLat / 2) * sin(dLat / 2) +
        cos(_toRadians(lat1)) *
            cos(_toRadians(lat2)) *
            sin(dLng / 2) *
            sin(dLng / 2);

    final c = 2 * atan2(sqrt(a), sqrt(1 - a));
    return earthRadiusKm * c;
  }

  double _toRadians(double degrees) => degrees * (pi / 180.0);

  // ═══════════════════════════════════════════════════════════════════════════
  // CONVENIENCE: NEAREST RESCUER
  // ═══════════════════════════════════════════════════════════════════════════

  /// Given a list of rescuer data maps (each with 'uid', 'latitude', 'longitude',
  /// 'is_on_duty'), returns the uid of the nearest on-duty rescuer to [targetLat]/
  /// [targetLng], or `null` if none are available.
  ///
  /// Call after fetching the `rescuers` collection from [FirestoreService].
  String? findNearestRescuer(
    List<Map<String, dynamic>> rescuers,
    double targetLat,
    double targetLng,
  ) {
    String? nearestUid;
    double nearestDistance = double.infinity;

    for (final r in rescuers) {
      // Skip rescuers who are off-duty or have no location data.
      if (r['is_on_duty'] != true) continue;
      final lat = (r['latitude'] as num?)?.toDouble();
      final lng = (r['longitude'] as num?)?.toDouble();
      if (lat == null || lng == null) continue;

      final dist = calculateDistance(targetLat, targetLng, lat, lng);
      if (dist < nearestDistance) {
        nearestDistance = dist;
        nearestUid = r['uid'] as String?;
      }
    }

    return nearestUid;
  }
}
