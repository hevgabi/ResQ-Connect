import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../models/sos_request_model.dart';
import '../../models/evac_center_model.dart';
import '../../services/firestore_service.dart';
import '../../services/location_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/rescuer_bottom_nav.dart';
import 'mission_queue_screen.dart';

class RescuerMapScreen extends StatefulWidget {
  const RescuerMapScreen({super.key});

  @override
  State<RescuerMapScreen> createState() => _RescuerMapScreenState();
}

class _RescuerMapScreenState extends State<RescuerMapScreen> {
  final FirestoreService _firestoreService = FirestoreService.instance;
  final LocationService _locationService = LocationService.instance;

  GoogleMapController? _mapController;
  LatLng? _rescuerLatLng;

  final Set<Marker> _markers = {};
  final Set<Polyline> _polylines = {};

  StreamSubscription? _sosSubscription;
  List<SOSRequestModel> _sosList = [];
  List<EvacCenterModel> _evacCenters = [];

  // For selected SOS pin
  SOSRequestModel? _selectedSos;

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
        _rebuildMarkers();
      });
      _mapController?.animateCamera(
        CameraUpdate.newLatLngZoom(_rescuerLatLng!, 13),
      );
    } catch (_) {}
  }

  void _listenSOS() {
    _sosSubscription = _firestoreService.openSOSStream().listen((list) {
      if (!mounted) return;
      setState(() {
        _sosList = list;
        _rebuildMarkers();
      });
    });
  }

  Future<void> _loadEvacCenters() async {
    try {
      // Sinasalo ang dynamic data at pinapasa sa factory mapping ng EvacCenterModel natin
      final List<dynamic> centersData = await _firestoreService
          .getEvacCenters();
      if (!mounted) return;
      setState(() {
        _evacCenters = centersData.map((data) {
          if (data is Map<String, dynamic>) {
            return EvacCenterModel.fromMap(data);
          }
          return EvacCenterModel.fromFirestore(data);
        }).toList();
        _rebuildMarkers();
      });
    } catch (_) {}
  }

  void _rebuildMarkers() {
    setState(() {
      _markers.clear();

      // Rescuer marker
      if (_rescuerLatLng != null) {
        _markers.add(
          Marker(
            markerId: const MarkerId('rescuer'),
            position: _rescuerLatLng!,
            icon: BitmapDescriptor.defaultMarkerWithHue(
              BitmapDescriptor.hueBlue,
            ),
            infoWindow: const InfoWindow(title: 'You (R)'),
            zIndex: 2,
          ),
        );
      }

      // SOS markers
      for (final sos in _sosList) {
        _markers.add(
          Marker(
            markerId: MarkerId('sos_${sos.id}'),
            position: LatLng(sos.latitude, sos.longitude),
            icon: BitmapDescriptor.defaultMarkerWithHue(
              BitmapDescriptor.hueRed,
            ),
            infoWindow: InfoWindow(
              title: '🆘 SOS - ${sos.citizenName}',
              snippet: sos.description ?? 'No description provided.',
            ),
            onTap: () => _onSosTapped(sos),
            zIndex: 1,
          ),
        );
      }

      // Evacuation center markers
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
          ),
        );
      }
    });
  }

  void _onSosTapped(SOSRequestModel sos) {
    setState(() => _selectedSos = sos);
    _showSosBottomSheet(sos);
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
          // Full-screen map
          GoogleMap(
            initialCameraPosition: CameraPosition(
              target: _rescuerLatLng ?? const LatLng(14.5995, 120.9842),
              zoom: 12,
            ),
            markers: _markers,
            polylines: _polylines,
            myLocationButtonEnabled: false,
            onMapCreated: (c) => _mapController = c,
          ),

          // AppBar overlay
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
            ),
          ),

          // Draggable summary tray
          DraggableScrollableSheet(
            initialChildSize: 0.18,
            minChildSize: 0.12,
            maxChildSize: 0.4,
            builder: (context, scrollController) {
              return Container(
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

          // FAB Queue Button
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

  const _SosDetailSheet({
    required this.sos,
    required this.firestoreService,
    required this.onAccept,
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
              Text(
                'SOS from ${sos.citizenName}',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                ),
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
