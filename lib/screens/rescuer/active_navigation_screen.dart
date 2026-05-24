import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;

import '../../models/mission_model.dart';
import '../../models/sos_request_model.dart';
import '../../services/firestore_service.dart';
import '../../services/location_service.dart';
import '../../theme/app_theme.dart';

const String _apiKey = 'AIzaSyCOooBNKqe-MshDk11ADPQQDK7k90W5Sl4';

/// Re-fetch route only when rescuer moves more than this many meters.
const double _routeRefreshThresholdMeters = 50.0;

/// Minimum seconds between consecutive Directions API calls.
const int _routeDebounceSeconds = 15;

class ActiveNavigationScreen extends StatefulWidget {
  final String missionId;
  const ActiveNavigationScreen({super.key, required this.missionId});

  @override
  State<ActiveNavigationScreen> createState() => _ActiveNavigationScreenState();
}

class _ActiveNavigationScreenState extends State<ActiveNavigationScreen> {
  final FirestoreService _firestoreService = FirestoreService.instance;
  final LocationService _locationService = LocationService.instance;
  final String uid = FirebaseAuth.instance.currentUser!.uid;

  GoogleMapController? _mapController;

  MissionModel? _mission;
  SOSRequestModel? _sosRequest;

  LatLng? _rescuerLatLng;
  LatLng? _victimLatLng;

  // Route fetch throttle state
  LatLng? _lastDirectionsFetchLatLng;
  DateTime? _lastDirectionsFetchTime;
  bool _fetchingDirections = false;

  final Set<Marker> _markers = {};
  final Set<Polyline> _polylines = {};

  StreamSubscription? _locationSubscription;
  Timer? _locationUpdateTimer;

  double? _etaMinutes;
  double? _distanceKm;
  String _nextInstruction = 'Calculating route...';
  String _nextDistance = '';

  bool _arriving = false;
  bool _routeLoaded = false;

  @override
  void initState() {
    super.initState();
    _loadMission();
  }

  Future<void> _loadMission() async {
    try {
      final missionDoc = await FirebaseFirestore.instance
          .collection('missions')
          .doc(widget.missionId)
          .get();

      if (!mounted || !missionDoc.exists) return;
      final mission = MissionModel.fromFirestore(missionDoc);
      setState(() => _mission = mission);

      final sosDoc = await FirebaseFirestore.instance
          .collection('sos_requests')
          .doc(mission.sosId)
          .get();

      if (!mounted || !sosDoc.exists) return;
      final sos = SOSRequestModel.fromFirestore(sosDoc);
      setState(() {
        _sosRequest = sos;
        _victimLatLng = LatLng(sos.latitude, sos.longitude);
      });
      _updateVictimMarker();
      _startLocationTracking();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error loading mission: $e')));
      }
    }
  }

  void _startLocationTracking() {
    _locationSubscription =
        _locationService.getPositionStream().listen((pos) {
          if (!mounted) return;
          final newLatLng = LatLng(pos.latitude, pos.longitude);
          setState(() => _rescuerLatLng = newLatLng);
          _updateRescuerMarker(newLatLng);
          _recalculateEtaFallback(newLatLng);
          // Only call Directions API when the rescuer has moved enough
          _maybeRefreshRoute(newLatLng);
        });

    // Write location to Firestore every 5 s — totally decoupled from route logic
    _locationUpdateTimer =
        Timer.periodic(const Duration(seconds: 5), (_) async {
          if (_rescuerLatLng == null) return;
          await _firestoreService.updateRescuerLocation(
            uid,
            _rescuerLatLng!.latitude,
            _rescuerLatLng!.longitude,
          );
        });
  }

  /// Throttled route refresh: only calls the API when:
  ///   1. No route has been drawn yet, OR
  ///   2. Rescuer moved >= threshold AND cooldown has elapsed.
  void _maybeRefreshRoute(LatLng current) {
    if (_fetchingDirections || _victimLatLng == null) return;

    final bool noRoute = !_routeLoaded;
    final bool movedEnough = _lastDirectionsFetchLatLng == null ||
        _haversineMeters(_lastDirectionsFetchLatLng!, current) >=
            _routeRefreshThresholdMeters;
    final bool cooledDown = _lastDirectionsFetchTime == null ||
        DateTime.now()
            .difference(_lastDirectionsFetchTime!)
            .inSeconds >=
            _routeDebounceSeconds;

    if (noRoute || (movedEnough && cooledDown)) {
      _fetchDirections(current);
    }
  }

  /// Haversine distance between two LatLng points, in metres.
  double _haversineMeters(LatLng a, LatLng b) {
    const double r = 6371000;
    final double dLat = _rad(b.latitude - a.latitude);
    final double dLng = _rad(b.longitude - a.longitude);
    final double h = math.pow(math.sin(dLat / 2), 2) +
        math.cos(_rad(a.latitude)) *
            math.cos(_rad(b.latitude)) *
            math.pow(math.sin(dLng / 2), 2);
    return 2 * r * math.asin(math.sqrt(h));
  }

  double _rad(double deg) => deg * math.pi / 180;

  /// Fetch the fastest driving route via Google Directions API.
  /// Requests real-time traffic data for accurate ETA.
  Future<void> _fetchDirections(LatLng origin) async {
    _fetchingDirections = true;
    _lastDirectionsFetchLatLng = origin;
    _lastDirectionsFetchTime = DateTime.now();

    try {
      final uri = Uri.parse(
        'https://maps.googleapis.com/maps/api/directions/json'
            '?origin=${origin.latitude},${origin.longitude}'
            '&destination=${_victimLatLng!.latitude},${_victimLatLng!.longitude}'
            '&mode=driving'
            '&alternatives=false'
            '&traffic_model=best_guess'
            '&departure_time=now'
            '&key=$_apiKey',
      );

      final response =
      await http.get(uri).timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) return;

      final json = jsonDecode(response.body) as Map<String, dynamic>;
      if (json['status'] != 'OK') {
        debugPrint('Directions API: ${json['status']}');
        return;
      }

      final routes = json['routes'] as List?;
      if (routes == null || routes.isEmpty) return;

      final route = routes[0] as Map<String, dynamic>;
      final leg = (route['legs'] as List)[0] as Map<String, dynamic>;

      // Prefer traffic-aware duration when available
      final durField = leg['duration_in_traffic'] ?? leg['duration'];
      final etaSecs = (durField?['value'] as int?) ?? 0;
      final distMeters = (leg['distance']?['value'] as int?) ?? 0;

      final encoded = route['overview_polyline']['points'] as String;
      final List<LatLng> points = _decodePolyline(encoded);

      // First step instruction
      final steps = leg['steps'] as List? ?? [];
      String instruction = 'Head toward victim';
      String dist = '';
      if (steps.isNotEmpty) {
        final step = steps[0] as Map<String, dynamic>;
        final rawHtml = step['html_instructions'] as String? ?? '';
        instruction = rawHtml.replaceAll(RegExp(r'<[^>]*>'), '');
        dist = step['distance']?['text'] ?? '';
      }

      if (!mounted) return;
      setState(() {
        _etaMinutes = etaSecs / 60.0;
        _distanceKm = distMeters / 1000.0;
        _nextInstruction = instruction;
        _nextDistance = dist;
        _routeLoaded = true;

        _polylines
          ..clear()
          ..add(
            Polyline(
              polylineId: const PolylineId('rescue_route'),
              points: points,
              color: AppTheme.primaryBlue,
              width: 6,
              startCap: Cap.roundCap,
              endCap: Cap.roundCap,
              jointType: JointType.round,
              geodesic: true,
            ),
          );
      });

      // Fit camera to show rescuer + victim + full route
      if (_mapController != null && points.isNotEmpty) {
        _mapController!.animateCamera(
          CameraUpdate.newLatLngBounds(
            _latLngBounds([origin, _victimLatLng!, ...points]),
            80,
          ),
        );
      }
    } catch (e) {
      debugPrint('Directions fetch error: $e');
    } finally {
      _fetchingDirections = false;
    }
  }

  /// Google Encoded Polyline Algorithm decoder.
  List<LatLng> _decodePolyline(String encoded) {
    final List<LatLng> poly = [];
    int index = 0;
    final int len = encoded.length;
    int lat = 0, lng = 0;
    while (index < len) {
      int b, shift = 0, result = 0;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);
      lat += ((result & 1) != 0 ? ~(result >> 1) : (result >> 1));
      shift = 0;
      result = 0;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);
      lng += ((result & 1) != 0 ? ~(result >> 1) : (result >> 1));
      poly.add(LatLng(lat / 1e5, lng / 1e5));
    }
    return poly;
  }

  LatLngBounds _latLngBounds(List<LatLng> points) {
    double minLat = points.first.latitude;
    double maxLat = points.first.latitude;
    double minLng = points.first.longitude;
    double maxLng = points.first.longitude;
    for (final p in points) {
      if (p.latitude < minLat) minLat = p.latitude;
      if (p.latitude > maxLat) maxLat = p.latitude;
      if (p.longitude < minLng) minLng = p.longitude;
      if (p.longitude > maxLng) maxLng = p.longitude;
    }
    return LatLngBounds(
      southwest: LatLng(minLat, minLng),
      northeast: LatLng(maxLat, maxLng),
    );
  }

  void _updateRescuerMarker(LatLng pos) {
    setState(() {
      _markers.removeWhere((m) => m.markerId.value == 'rescuer');
      _markers.add(
        Marker(
          markerId: const MarkerId('rescuer'),
          position: pos,
          icon: BitmapDescriptor.defaultMarkerWithHue(
              BitmapDescriptor.hueAzure),
          infoWindow: const InfoWindow(
            title: '🚑 You (Rescuer)',
            snippet: 'Your current location',
          ),
          zIndex: 2,
        ),
      );
    });
  }

  void _updateVictimMarker() {
    if (_victimLatLng == null) return;
    final sos = _sosRequest;
    setState(() {
      _markers.removeWhere((m) => m.markerId.value == 'victim');
      _markers.add(
        Marker(
          markerId: const MarkerId('victim'),
          position: _victimLatLng!,
          icon: BitmapDescriptor.defaultMarkerWithHue(
              BitmapDescriptor.hueRed),
          infoWindow: InfoWindow(
            title: '🆘 ${sos?.citizenName ?? 'Victim'}',
            snippet: sos?.description ?? 'Emergency location',
          ),
          zIndex: 1,
        ),
      );
    });
  }

  /// Straight-line ETA fallback — shown while the first API call is in flight.
  void _recalculateEtaFallback(LatLng from) {
    if (_routeLoaded || _victimLatLng == null) return;
    final distKm = _locationService.calculateDistance(
      from.latitude,
      from.longitude,
      _victimLatLng!.latitude,
      _victimLatLng!.longitude,
    );
    setState(() {
      _etaMinutes = (distKm / 40) * 60;
      _distanceKm = distKm;
    });
  }

  Future<bool> _confirmLeave() async {
    return await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Leave Navigation?'),
        content: const Text(
          'Are you sure you want to leave active navigation? '
              'The mission will remain active.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(
              'Leave',
              style: TextStyle(color: AppTheme.dangerRed),
            ),
          ),
        ],
      ),
    ) ??
        false;
  }

  Future<void> _markArrived() async {
    if (_arriving) return;
    setState(() => _arriving = true);
    try {
      final firestore = FirebaseFirestore.instance;
      final rescuerRef = firestore.collection('rescuers').doc(uid);

      // Read current count first to avoid going below 0
      final rescuerDoc = await rescuerRef.get();
      final currentCount =
          (rescuerDoc.data()?['active_mission_count'] as int?) ?? 0;
      final newCount = currentCount > 0 ? currentCount - 1 : 0;

      await Future.wait([
        _firestoreService.updateMission(widget.missionId, {
          'status': 'arrived',
          'completed_at': FieldValue.serverTimestamp(),
        }),
        _firestoreService.updateSOSRequest(_sosRequest!.id, {
          'status': 'resolved',
          'resolved_at': FieldValue.serverTimestamp(),
        }),
        rescuerRef.update({
          'active_mission_count': newCount,
        }),
      ]);
      if (!mounted) return;
      Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: AppTheme.dangerRed,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _arriving = false);
    }
  }

  @override
  void dispose() {
    _locationSubscription?.cancel();
    _locationUpdateTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final sos = _sosRequest;
    final initialTarget =
        _rescuerLatLng ?? _victimLatLng ?? const LatLng(14.5995, 120.9842);

    return WillPopScope(
      onWillPop: _confirmLeave,
      child: Scaffold(
        body: Stack(
          children: [
            // ── Full-screen map ────────────────────────────────────────────
            GoogleMap(
              initialCameraPosition:
              CameraPosition(target: initialTarget, zoom: 15),
              markers: _markers,
              polylines: _polylines,
              onMapCreated: (c) {
                _mapController = c;
                if (_rescuerLatLng != null && _victimLatLng != null) {
                  c.animateCamera(CameraUpdate.newLatLngBounds(
                    _latLngBounds([_rescuerLatLng!, _victimLatLng!]),
                    80,
                  ));
                }
              },
              myLocationEnabled: false,
              myLocationButtonEnabled: false,
              trafficEnabled: true,
              zoomControlsEnabled: true,
            ),

            // ── Turn-by-turn banner ────────────────────────────────────────
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: SafeArea(
                child: Container(
                  margin: const EdgeInsets.all(12),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 14),
                  decoration: BoxDecoration(
                    color: AppTheme.primaryBlue,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: const [
                      BoxShadow(
                        color: Colors.black26,
                        blurRadius: 8,
                        offset: Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.navigation_outlined,
                          color: Colors.white, size: 24),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _nextInstruction,
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            if (_nextDistance.isNotEmpty)
                              Text(
                                'In $_nextDistance',
                                style: const TextStyle(
                                  color: Colors.white70,
                                  fontSize: 12,
                                ),
                              ),
                          ],
                        ),
                      ),
                      if (_etaMinutes != null)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: AppTheme.successGreen,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                _etaMinutes!.toStringAsFixed(0),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 18,
                                ),
                              ),
                              const Text('min',
                                  style: TextStyle(
                                      color: Colors.white70, fontSize: 10)),
                              if (_distanceKm != null)
                                Text(
                                  '${_distanceKm!.toStringAsFixed(1)} km',
                                  style: const TextStyle(
                                      color: Colors.white60, fontSize: 9),
                                ),
                            ],
                          ),
                        )
                      else
                        const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white),
                        ),
                    ],
                  ),
                ),
              ),
            ),

            // ── Bottom victim info panel ───────────────────────────────────
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: Container(
                padding: const EdgeInsets.all(20),
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius:
                  BorderRadius.vertical(top: Radius.circular(20)),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black26,
                      blurRadius: 12,
                      offset: Offset(0, -4),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.person_pin_outlined,
                            color: AppTheme.dangerRed),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            sos?.citizenName ?? 'Victim',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                        ),
                        // Re-center button
                        IconButton(
                          icon: const Icon(Icons.fit_screen,
                              color: AppTheme.primaryBlue),
                          tooltip: 'Fit route on screen',
                          onPressed: () {
                            if (_rescuerLatLng != null &&
                                _victimLatLng != null) {
                              _mapController?.animateCamera(
                                CameraUpdate.newLatLngBounds(
                                  _latLngBounds(
                                      [_rescuerLatLng!, _victimLatLng!]),
                                  80,
                                ),
                              );
                            }
                          },
                        ),
                      ],
                    ),
                    if (sos?.description != null &&
                        sos!.description!.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(
                          sos.description!,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: AppTheme.textSecondary,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: _arriving ? null : _markArrived,
                        icon: _arriving
                            ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white),
                        )
                            : const Icon(Icons.check_circle_outline),
                        label: const Text('Arrived',
                            style: TextStyle(fontSize: 16)),
                        style: FilledButton.styleFrom(
                          backgroundColor: AppTheme.successGreen,
                          padding:
                          const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}