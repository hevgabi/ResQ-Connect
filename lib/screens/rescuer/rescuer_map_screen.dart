import 'dart:async';
import 'dart:convert';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;

import '../../models/sos_request_model.dart';
import '../../models/evac_center_model.dart';
import '../../services/firestore_service.dart';
import '../../services/location_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/rescuer_bottom_nav.dart';
import 'mission_queue_screen.dart';

const String _apiKey = 'AIzaSyCOooBNKqe-MshDk11ADPQQDK7k90W5Sl4';

class RescuerMapScreen extends StatefulWidget {
  const RescuerMapScreen({super.key});

  @override
  State<RescuerMapScreen> createState() => _RescuerMapScreenState();
}

class _RescuerMapScreenState extends State<RescuerMapScreen> {
  final FirestoreService _firestoreService = FirestoreService.instance;
  final LocationService _locationService = LocationService.instance;
  final String uid = FirebaseAuth.instance.currentUser!.uid;

  GoogleMapController? _mapController;
  LatLng? _rescuerLatLng;

  final Set<Marker> _markers = {};
  final Set<Polyline> _polylines = {};

  StreamSubscription? _sosSubscription;
  List<SOSRequestModel> _sosList = [];
  List<EvacCenterModel> _evacCenters = [];

  SOSRequestModel? _selectedSos;
  bool _fetchingPreviewRoute = false;

  @override
  void initState() {
    super.initState();
    _initLocation();
    _listenSOS();
    _loadEvacCenters();
  }

  Future<void> _initLocation() async {
    try {
      final pos = await _locationService.getCurrentPosition();
      if (!mounted || pos == null) return;
      setState(() {
        _rescuerLatLng = LatLng(pos.latitude, pos.longitude);
      });
      _rebuildMarkers();
      _mapController?.animateCamera(
        CameraUpdate.newLatLngZoom(_rescuerLatLng!, 13),
      );
    } catch (_) {}
  }

  void _listenSOS() {
    _sosSubscription = _firestoreService.openSOSStream(excludeRescuerId: uid).listen((list) {
      if (!mounted) return;
      setState(() {
        _sosList = list;
      });
      _rebuildMarkers();
    });
  }

  Future<void> _loadEvacCenters() async {
    try {
      final List<dynamic> centersData =
      await _firestoreService.getEvacCenters();
      if (!mounted) return;
      setState(() {
        _evacCenters = centersData.map((data) {
          if (data is Map<String, dynamic>) {
            return EvacCenterModel.fromMap(data);
          }
          return EvacCenterModel.fromFirestore(data);
        }).toList();
      });
      _rebuildMarkers();
    } catch (_) {}
  }

  void _rebuildMarkers() {
    if (!mounted) return;
    setState(() {
      _markers.clear();

      // ── Rescuer marker (blue) ───────────────────────────────────────────
      if (_rescuerLatLng != null) {
        _markers.add(
          Marker(
            markerId: const MarkerId('rescuer_self'),
            position: _rescuerLatLng!,
            icon: BitmapDescriptor.defaultMarkerWithHue(
              BitmapDescriptor.hueAzure,
            ),
            infoWindow: const InfoWindow(
              title: '🚑 You (Rescuer)',
              snippet: 'Your current location',
            ),
            zIndex: 3,
          ),
        );
      }

      // ── SOS / Citizen markers (red) ─────────────────────────────────────
      for (final sos in _sosList) {
        _markers.add(
          Marker(
            markerId: MarkerId('sos_${sos.id}'),
            position: LatLng(sos.latitude, sos.longitude),
            icon: BitmapDescriptor.defaultMarkerWithHue(
              BitmapDescriptor.hueRed,
            ),
            infoWindow: InfoWindow(
              title: '🆘 ${sos.citizenName}',
              snippet: sos.description ?? 'Emergency — tap for details',
            ),
            onTap: () => _onSosTapped(sos),
            zIndex: 2,
          ),
        );
      }

      // ── Evacuation center markers (green) ───────────────────────────────
      for (final center in _evacCenters) {
        _markers.add(
          Marker(
            markerId: MarkerId('evac_${center.id}'),
            position: LatLng(center.latitude, center.longitude),
            icon: BitmapDescriptor.defaultMarkerWithHue(
              BitmapDescriptor.hueGreen,
            ),
            infoWindow: InfoWindow(
              title: '🏥 ${center.name}',
              snippet: 'Evacuation Center',
            ),
            zIndex: 1,
          ),
        );
      }
    });
  }

  void _onSosTapped(SOSRequestModel sos) {
    setState(() => _selectedSos = sos);
    // Animate camera to show both rescuer and victim
    if (_rescuerLatLng != null) {
      _fitBounds([_rescuerLatLng!, LatLng(sos.latitude, sos.longitude)]);
    }
    // Draw a preview route line
    _drawPreviewRoute(sos);
    _showSosBottomSheet(sos);
  }

  /// Draws a lightweight preview route from the rescuer to the tapped SOS pin.
  Future<void> _drawPreviewRoute(SOSRequestModel sos) async {
    if (_rescuerLatLng == null || _fetchingPreviewRoute) return;
    _fetchingPreviewRoute = true;

    final victim = LatLng(sos.latitude, sos.longitude);

    try {
      final uri = Uri.parse(
        'https://maps.googleapis.com/maps/api/directions/json'
            '?origin=${_rescuerLatLng!.latitude},${_rescuerLatLng!.longitude}'
            '&destination=${victim.latitude},${victim.longitude}'
            '&mode=driving'
            '&alternatives=false'
            '&key=$_apiKey',
      );

      final response = await http.get(uri).timeout(const Duration(seconds: 8));
      if (response.statusCode != 200) return;

      final json = jsonDecode(response.body) as Map<String, dynamic>;
      if (json['status'] != 'OK') return;

      final routes = json['routes'] as List?;
      if (routes == null || routes.isEmpty) return;

      final encoded =
      routes[0]['overview_polyline']['points'] as String;
      final points = _decodePolyline(encoded);

      if (!mounted) return;
      setState(() {
        _polylines
          ..clear()
          ..add(
            Polyline(
              polylineId: const PolylineId('preview_route'),
              points: points,
              color: AppTheme.primaryBlue.withOpacity(0.7),
              width: 5,
              patterns: [PatternItem.dash(20), PatternItem.gap(8)],
              startCap: Cap.roundCap,
              endCap: Cap.roundCap,
              geodesic: true,
            ),
          );
      });
    } catch (e) {
      debugPrint('Preview route error: $e');
    } finally {
      _fetchingPreviewRoute = false;
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

  void _fitBounds(List<LatLng> points) {
    if (points.isEmpty || _mapController == null) return;
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
    _mapController!.animateCamera(
      CameraUpdate.newLatLngBounds(
        LatLngBounds(
          southwest: LatLng(minLat, minLng),
          northeast: LatLng(maxLat, maxLng),
        ),
        100,
      ),
    );
  }

  void _showSosBottomSheet(SOSRequestModel sos) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _SosDetailSheet(
        sos: sos,
        firestoreService: _firestoreService,
        onAccept: () {
          Navigator.pop(context);
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const MissionQueueScreen()),
          );
        },
        onDismiss: () {
          // Clear preview route when sheet closed without accepting
          setState(() => _polylines.clear());
          Navigator.pop(context);
        },
      ),
    );
  }

  String _priorityLabel(SOSRequestModel sos) {
    if (sos.createdAt == null) return 'MODERATE';
    final minutes = DateTime.now().difference(sos.createdAt!).inMinutes;
    if (minutes > 30) return 'CRITICAL';
    if (minutes > 15) return 'HIGH';
    return 'MODERATE';
  }

  Map<String, int> _breakdownCounts() {
    int critical = 0, high = 0, moderate = 0;
    for (final s in _sosList) {
      final p = _priorityLabel(s);
      if (p == 'CRITICAL') {
        critical++;
      } else if (p == 'HIGH') {
        high++;
      } else {
        moderate++;
      }
    }
    return {'CRITICAL': critical, 'HIGH': high, 'MODERATE': moderate};
  }

  @override
  void dispose() {
    _sosSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final counts = _breakdownCounts();

    return Scaffold(
      body: Stack(
        children: [
          // ── Full-screen map ──────────────────────────────────────────────
          GoogleMap(
            initialCameraPosition: CameraPosition(
              target: _rescuerLatLng ?? const LatLng(14.5995, 120.9842),
              zoom: 13,
            ),
            markers: _markers,
            polylines: _polylines,
            myLocationEnabled: false,
            myLocationButtonEnabled: false,
            trafficEnabled: false, // FIXED: was showing Google traffic layer as if it were drawn route lines
            zoomControlsEnabled: true,
            onMapCreated: (c) {
              _mapController = c;
              if (_rescuerLatLng != null) {
                c.animateCamera(
                  CameraUpdate.newLatLngZoom(_rescuerLatLng!, 13),
                );
              }
            },
            onTap: (_) {
              // Clear preview route when user taps elsewhere
              if (_polylines.isNotEmpty) {
                setState(() => _polylines.clear());
              }
            },
          ),

          // ── AppBar overlay ───────────────────────────────────────────────
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: AppBar(
              backgroundColor: AppTheme.primaryBlue.withOpacity(0.92),
              foregroundColor: Colors.white,
              title: const Text(
                'Rescue Map',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              elevation: 0,
              actions: [
                // Re-center to rescuer location
                IconButton(
                  icon: const Icon(Icons.my_location),
                  tooltip: 'My location',
                  onPressed: () {
                    if (_rescuerLatLng != null) {
                      _mapController?.animateCamera(
                        CameraUpdate.newLatLngZoom(_rescuerLatLng!, 14),
                      );
                    }
                  },
                ),
              ],
            ),
          ),

          // ── Map legend ───────────────────────────────────────────────────
          Positioned(
            top: kToolbarHeight + MediaQuery.of(context).padding.top + 8,
            right: 12,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.92),
                borderRadius: BorderRadius.circular(10),
                boxShadow: const [
                  BoxShadow(color: Colors.black26, blurRadius: 6),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  _legendRow('🚑', 'You', AppTheme.primaryBlue),
                  const SizedBox(height: 4),
                  _legendRow('🆘', 'SOS', AppTheme.dangerRed),
                  const SizedBox(height: 4),
                  _legendRow('🏥', 'Evac', AppTheme.successGreen),
                ],
              ),
            ),
          ),

          // ── Draggable summary tray ───────────────────────────────────────
          DraggableScrollableSheet(
            initialChildSize: 0.18,
            minChildSize: 0.12,
            maxChildSize: 0.4,
            builder: (context, scrollController) {
              return Container(
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
                child: ListView(
                  controller: scrollController,
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  children: [
                    Center(
                      child: Container(
                        margin: const EdgeInsets.symmetric(vertical: 10),
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: Colors.grey.shade300,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(
                          Icons.sos_outlined,
                          color: AppTheme.dangerRed,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Total Active SOS: ${_sosList.length}',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        _countBadge(
                          'CRITICAL',
                          counts['CRITICAL'] ?? 0,
                          AppTheme.dangerRed,
                        ),
                        _countBadge(
                          'HIGH',
                          counts['HIGH'] ?? 0,
                          AppTheme.warningOrange,
                        ),
                        _countBadge(
                          'MODERATE',
                          counts['MODERATE'] ?? 0,
                          AppTheme.successGreen,
                        ),
                      ],
                    ),
                  ],
                ),
              );
            },
          ),

          // ── FAB: Mission Queue ───────────────────────────────────────────
          Positioned(
            bottom: 180,
            right: 16,
            child: FloatingActionButton.extended(
              backgroundColor: AppTheme.primaryBlue,
              foregroundColor: Colors.white,
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const MissionQueueScreen()),
              ),
              icon: const Icon(Icons.queue),
              label: const Text('Queue'),
            ),
          ),
        ],
      ),
      bottomNavigationBar: RescuerBottomNav(currentIndex: 1),
    );
  }

  Widget _legendRow(String emoji, String label, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(emoji, style: const TextStyle(fontSize: 13)),
        const SizedBox(width: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: color,
          ),
        ),
      ],
    );
  }

  Widget _countBadge(String label, int count, Color color) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: color.withOpacity(0.12),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: color.withOpacity(0.4)),
          ),
          child: Text(
            '$count',
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.bold,
              fontSize: 20,
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(
            color: color,
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _SosDetailSheet extends StatelessWidget {
  final SOSRequestModel sos;
  final FirestoreService firestoreService;
  final VoidCallback onAccept;
  final VoidCallback onDismiss;

  const _SosDetailSheet({
    required this.sos,
    required this.firestoreService,
    required this.onAccept,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.sos_outlined,
                color: AppTheme.dangerRed,
                size: 28,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'SOS from ${sos.citizenName}',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close),
                onPressed: onDismiss,
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            sos.description ?? 'No description provided.',
            style: const TextStyle(fontSize: 14),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              const Text(
                '👥 Population: ',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
              ),
              Text(
                '${sos.personsCount} person(s)',
                style: const TextStyle(fontSize: 13),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              const Text(
                '🩸 Blood Type Required: ',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
              ),
              Text(sos.bloodType, style: const TextStyle(fontSize: 13)),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '📍 ${sos.latitude.toStringAsFixed(5)}, ${sos.longitude.toStringAsFixed(5)}',
            style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: onAccept,
              icon: const Icon(Icons.check_circle_outline),
              label: const Text('Accept Mission'),
              style: FilledButton.styleFrom(
                backgroundColor: AppTheme.primaryBlue,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ),
        ],
      ),
    );
  }
}