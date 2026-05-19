import 'dart:async';
import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:maps_toolkit/maps_toolkit.dart' show PolygonUtil;
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../models/mission_model.dart';
import '../../models/sos_request_model.dart';
import '../../services/firestore_service.dart';
import '../../services/location_service.dart';
import '../../theme/app_theme.dart';
import 'mission_queue_screen.dart';

const String _apiKey = 'YOUR_API_KEY';

class ActiveNavigationScreen extends StatefulWidget {
  final String missionId;
  const ActiveNavigationScreen({super.key, required this.missionId});

  @override
  State<ActiveNavigationScreen> createState() => _ActiveNavigationScreenState();
}

class _ActiveNavigationScreenState extends State<ActiveNavigationScreen> {
  final FirestoreService _firestoreService = FirestoreService.instance;
  final LocationService _locationService = LocationService();
  final String uid = FirebaseAuth.instance.currentUser!.uid;

  GoogleMapController? _mapController;

  MissionModel? _mission;
  SosRequestModel? _sosRequest;

  LatLng? _rescuerLatLng;
  LatLng? _victimLatLng;

  final Set<Marker> _markers = {};
  final Set<Polyline> _polylines = {};

  StreamSubscription? _locationSubscription;
  Timer? _locationUpdateTimer;

  double? _etaMinutes;
  String _nextInstruction = 'Calculating route...';
  String _nextDistance = '';

  bool _arriving = false;

  @override
  void initState() {
    super.initState();
    _loadMission();
  }

  Future<void> _loadMission() async {
    try {
      final mission = await _firestoreService.getMissionById(widget.missionId);
      if (!mounted || mission == null) return;
      setState(() => _mission = mission);

      final sos = await _firestoreService.getSosRequestById(mission.sosId);
      if (!mounted || sos == null) return;
      setState(() {
        _sosRequest = sos;
        _victimLatLng = LatLng(sos.latitude, sos.longitude);
        _updateVictimMarker();
      });

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
    _locationSubscription = _locationService.getPositionStream().listen((
      pos,
    ) async {
      if (!mounted) return;
      setState(() {
        _rescuerLatLng = LatLng(pos.latitude, pos.longitude);
        _updateRescuerMarker();
        _recalculateEta();
      });
    });

    // Update Firestore every 5 seconds
    _locationUpdateTimer = Timer.periodic(const Duration(seconds: 5), (
      _,
    ) async {
      if (_rescuerLatLng == null) return;
      await _firestoreService.updateRescuerLocation(
        uid,
        _rescuerLatLng!.latitude,
        _rescuerLatLng!.longitude,
      );
    });

    // Initial directions fetch after getting first location
    Future.delayed(const Duration(seconds: 2), () {
      if (_rescuerLatLng != null && _victimLatLng != null) {
        _fetchDirections();
      }
    });
  }

  Future<void> _fetchDirections() async {
    if (_rescuerLatLng == null || _victimLatLng == null) return;
    try {
      final url =
          'https://maps.googleapis.com/maps/api/directions/json'
          '?origin=${_rescuerLatLng!.latitude},${_rescuerLatLng!.longitude}'
          '&destination=${_victimLatLng!.latitude},${_victimLatLng!.longitude}'
          '&mode=driving'
          '&key=$_apiKey';

      final response = await http.get(Uri.parse(url));
      if (response.statusCode != 200) return;

      final json = jsonDecode(response.body);
      final routes = json['routes'] as List?;
      if (routes == null || routes.isEmpty) return;

      final route = routes[0];
      final encoded = route['overview_polyline']['points'] as String;

      // Decode polyline
      final List<LatLng> points = _decodePolyline(encoded);

      // Get first step instruction
      final steps = route['legs']?[0]?['steps'] as List? ?? [];
      if (steps.isNotEmpty) {
        final step = steps[0];
        final rawHtml = step['html_instructions'] as String? ?? '';
        final instruction = rawHtml.replaceAll(RegExp(r'<[^>]*>'), '');
        final dist = step['distance']?['text'] ?? '';
        if (mounted) {
          setState(() {
            _nextInstruction = instruction;
            _nextDistance = dist;
          });
        }
      }

      if (!mounted) return;
      setState(() {
        _polylines.clear();
        _polylines.add(
          Polyline(
            polylineId: const PolylineId('route'),
            points: points,
            color: AppTheme.primaryBlue,
            width: 5,
          ),
        );
      });

      _mapController?.animateCamera(CameraUpdate.newLatLng(_rescuerLatLng!));
    } catch (e) {
      debugPrint('Directions error: $e');
    }
  }

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
      final int dlat = ((result & 1) != 0 ? ~(result >> 1) : (result >> 1));
      lat += dlat;

      shift = 0;
      result = 0;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);
      final int dlng = ((result & 1) != 0 ? ~(result >> 1) : (result >> 1));
      lng += dlng;

      poly.add(LatLng(lat / 1e5, lng / 1e5));
    }
    return poly;
  }

  void _updateRescuerMarker() {
    if (_rescuerLatLng == null) return;
    _markers.removeWhere((m) => m.markerId.value == 'rescuer');
    _markers.add(
      Marker(
        markerId: const MarkerId('rescuer'),
        position: _rescuerLatLng!,
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueBlue),
        infoWindow: const InfoWindow(title: 'You (R)'),
        zIndex: 2,
      ),
    );
    _fetchDirections();
  }

  void _updateVictimMarker() {
    if (_victimLatLng == null) return;
    _markers.removeWhere((m) => m.markerId.value == 'victim');
    _markers.add(
      Marker(
        markerId: const MarkerId('victim'),
        position: _victimLatLng!,
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
        infoWindow: const InfoWindow(title: 'Victim (V)'),
      ),
    );
  }

  void _recalculateEta() {
    if (_rescuerLatLng == null || _victimLatLng == null) return;
    final distKm = _locationService.calculateDistance(
      _rescuerLatLng!.latitude,
      _rescuerLatLng!.longitude,
      _victimLatLng!.latitude,
      _victimLatLng!.longitude,
    );
    setState(() => _etaMinutes = (distKm / 40) * 60);
  }

  Future<bool> _confirmLeave() async {
    return await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Leave Navigation?'),
            content: const Text(
              'Are you sure you want to leave active navigation? The mission will remain active.',
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
      await Future.wait([
        _firestoreService.updateMission(widget.missionId, {
          'status': 'arrived',
          'arrived_at': FieldValue.serverTimestamp(),
        }),
        _firestoreService.updateSosRequest(_sosRequest!.id, {
          'status': 'resolved',
          'resolved_at': FieldValue.serverTimestamp(),
        }),
        _firestoreService.updateRescuer(uid, {
          'active_mission_count': FieldValue.increment(-1),
        }),
      ]);
      if (!mounted) return;
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const MissionQueueScreen()),
        (route) => false,
      );
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

    return WillPopScope(
      onWillPop: _confirmLeave,
      child: Scaffold(
        body: Stack(
          children: [
            // Full-screen map
            GoogleMap(
              initialCameraPosition: CameraPosition(
                target:
                    _rescuerLatLng ??
                    _victimLatLng ??
                    const LatLng(14.5995, 120.9842),
                zoom: 14,
              ),
              markers: _markers,
              polylines: _polylines,
              onMapCreated: (c) => _mapController = c,
              myLocationButtonEnabled: false,
            ),

            // Direction banner (top)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: SafeArea(
                child: Column(
                  children: [
                    Container(
                      margin: const EdgeInsets.all(12),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 14,
                      ),
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
                          const Icon(
                            Icons.navigation_outlined,
                            color: Colors.white,
                            size: 24,
                          ),
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

                          // ETA badge
                          if (_etaMinutes != null)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: AppTheme.successGreen,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Column(
                                children: [
                                  Text(
                                    '${_etaMinutes!.toStringAsFixed(0)}',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 18,
                                    ),
                                  ),
                                  const Text(
                                    'min',
                                    style: TextStyle(
                                      color: Colors.white70,
                                      fontSize: 10,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // Bottom victim info panel
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: Container(
                padding: const EdgeInsets.all(20),
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
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
                        const Icon(
                          Icons.person_pin_outlined,
                          color: AppTheme.dangerRed,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          sos?.citizenName ?? 'Victim',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                        const Spacer(),
                        if (sos?.bloodType != null)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: AppTheme.dangerRed.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              '🩸 ${sos!.bloodType!}',
                              style: const TextStyle(
                                color: AppTheme.dangerRed,
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        const SizedBox(width: 8),
                        if (_mission != null)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: AppTheme.primaryBlue.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              '👥 ${_mission!.personsCount}',
                              style: const TextStyle(
                                color: AppTheme.primaryBlue,
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                              ),
                            ),
                          ),
                      ],
                    ),
                    if (sos?.description != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        sos!.description!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: AppTheme.textSecondary,
                          fontSize: 13,
                        ),
                      ),
                    ],
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
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(Icons.check_circle_outline),
                        label: const Text(
                          'Arrived',
                          style: TextStyle(fontSize: 16),
                        ),
                        style: FilledButton.styleFrom(
                          backgroundColor: AppTheme.successGreen,
                          padding: const EdgeInsets.symmetric(vertical: 14),
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
