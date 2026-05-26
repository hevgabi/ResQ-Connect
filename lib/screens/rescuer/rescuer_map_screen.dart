import 'dart:async';
import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;

import '../../models/sos_request_model.dart';
import '../../models/evac_center_model.dart';
import '../../models/user_model.dart';
import '../../services/firestore_service.dart';
import '../../services/location_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/rescuer_bottom_nav.dart';
import 'active_navigation_screen.dart';
import 'mission_queue_screen.dart';

const String _apiKey = 'AIzaSyCOooBNKqe-MshDk11ADPQQDK7k90W5Sl4';

class RescuerMapScreen extends StatefulWidget {
  const RescuerMapScreen({super.key});

  @override
  State<RescuerMapScreen> createState() => _RescuerMapScreenState();
}

class _RescuerMapScreenState extends State<RescuerMapScreen>
    with SingleTickerProviderStateMixin {
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

  // ETA for selected SOS
  double? _previewEtaMinutes;
  double? _previewDistanceKm;

  // Layer toggles
  bool _showEvacCenters = true;
  bool _showSosMarkers = true;

  // SOS tray expand/collapse
  bool _sosListExpanded = false;

  // Detail panel animation
  late AnimationController _panelController;
  late Animation<Offset> _panelSlide;
  bool _panelVisible = false;

  // Filter
  String? _activeFilter;

  // Accept state
  bool _accepting = false;

  @override
  void initState() {
    super.initState();
    _panelController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 280),
    );
    _panelSlide = Tween<Offset>(begin: const Offset(0, 1), end: Offset.zero)
        .animate(
          CurvedAnimation(parent: _panelController, curve: Curves.easeOutCubic),
        );

    _initLocation();
    _listenSOS();
    _loadEvacCenters();
  }

  Future<void> _initLocation() async {
    try {
      final pos = await _locationService.getCurrentPosition();
      if (!mounted || pos == null) return;
      setState(() => _rescuerLatLng = LatLng(pos.latitude, pos.longitude));
      _rebuildMarkers();
      _mapController?.animateCamera(
        CameraUpdate.newLatLngZoom(_rescuerLatLng!, 14),
      );
    } catch (_) {}
  }

  void _listenSOS() {
    _sosSubscription = _firestoreService
        .openSOSStream(excludeRescuerId: uid)
        .listen((list) {
          if (!mounted) return;
          setState(() => _sosList = list);
          _rebuildMarkers();
        });
  }

  Future<void> _loadEvacCenters() async {
    try {
      final data = await _firestoreService.getEvacCenters();
      if (!mounted) return;
      setState(() {
        _evacCenters = data
            .map((d) => EvacCenterModel.fromMap(d as Map<String, dynamic>))
            .toList();
      });
      _rebuildMarkers();
    } catch (_) {}
  }

  void _rebuildMarkers() {
    if (!mounted) return;
    setState(() {
      _markers.clear();
      if (_rescuerLatLng != null) {
        _markers.add(
          Marker(
            markerId: const MarkerId('rescuer_self'),
            position: _rescuerLatLng!,
            icon: BitmapDescriptor.defaultMarkerWithHue(
              BitmapDescriptor.hueAzure,
            ),
            infoWindow: const InfoWindow(
              title: '🚑 You',
              snippet: 'Your location',
            ),
            zIndex: 3,
          ),
        );
      }
      if (_showSosMarkers) {
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
                snippet: sos.address ?? sos.description ?? 'Tap for details',
              ),
              onTap: () => _onSosTapped(sos),
              zIndex: 2,
            ),
          );
        }
      }
      if (_showEvacCenters) {
        for (final c in _evacCenters) {
          _markers.add(
            Marker(
              markerId: MarkerId('evac_${c.id}'),
              position: LatLng(c.latitude, c.longitude),
              icon: BitmapDescriptor.defaultMarkerWithHue(
                BitmapDescriptor.hueGreen,
              ),
              infoWindow: InfoWindow(
                title: '🏥 ${c.name}',
                snippet: c.status == 'open'
                    ? 'Open · ${c.availableSlots} slots'
                    : 'Closed',
              ),
              zIndex: 1,
            ),
          );
        }
      }
    });
  }

  void _onSosTapped(SOSRequestModel sos) {
    setState(() {
      _selectedSos = sos;
      _panelVisible = true;
      _sosListExpanded = false;
      _previewEtaMinutes = null;
      _previewDistanceKm = null;
    });
    _panelController.forward();
    if (_rescuerLatLng != null) {
      _fitBounds([_rescuerLatLng!, LatLng(sos.latitude, sos.longitude)]);
    }
    _drawPreviewRoute(sos);
  }

  void _closePanel() {
    _panelController.reverse().then((_) {
      if (mounted) {
        setState(() {
          _panelVisible = false;
          _selectedSos = null;
          _polylines.clear();
          _previewEtaMinutes = null;
          _previewDistanceKm = null;
        });
      }
    });
  }

  Future<void> _drawPreviewRoute(SOSRequestModel sos) async {
    if (_rescuerLatLng == null || _fetchingPreviewRoute) return;
    _fetchingPreviewRoute = true;
    try {
      final uri = Uri.parse(
        'https://maps.googleapis.com/maps/api/directions/json'
        '?origin=${_rescuerLatLng!.latitude},${_rescuerLatLng!.longitude}'
        '&destination=${sos.latitude},${sos.longitude}'
        '&mode=driving&alternatives=false'
        '&traffic_model=best_guess&departure_time=now'
        '&key=$_apiKey',
      );
      final res = await http.get(uri).timeout(const Duration(seconds: 8));
      if (res.statusCode != 200) return;
      final json = jsonDecode(res.body) as Map<String, dynamic>;
      if (json['status'] != 'OK') return;
      final routes = json['routes'] as List?;
      if (routes == null || routes.isEmpty) return;

      final route = routes[0] as Map<String, dynamic>;
      final leg = (route['legs'] as List)[0] as Map<String, dynamic>;
      final durField = leg['duration_in_traffic'] ?? leg['duration'];
      final etaSecs = (durField?['value'] as int?) ?? 0;
      final distMeters = (leg['distance']?['value'] as int?) ?? 0;

      final points = _decodePolyline(
        route['overview_polyline']['points'] as String,
      );

      if (!mounted) return;
      setState(() {
        _previewEtaMinutes = etaSecs / 60.0;
        _previewDistanceKm = distMeters / 1000.0;
        _polylines
          ..clear()
          ..add(
            Polyline(
              polylineId: const PolylineId('preview_route'),
              points: points,
              color: AppTheme.primaryBlue.withOpacity(0.8),
              width: 5,
              patterns: [PatternItem.dash(20), PatternItem.gap(8)],
              startCap: Cap.roundCap,
              endCap: Cap.roundCap,
              geodesic: true,
            ),
          );
      });
    } catch (e) {
      debugPrint('Route error: $e');
    } finally {
      _fetchingPreviewRoute = false;
    }
  }

  // ── Accept mission directly from the map ───────────────────────────────────
  Future<void> _acceptMission(SOSRequestModel sos) async {
    if (_accepting) return;
    setState(() => _accepting = true);

    final firestore = FirebaseFirestore.instance;
    final sosRef = firestore.collection('sos_requests').doc(sos.id);
    final rescuerRef = firestore.collection('rescuers').doc(uid);
    final missionRef = firestore.collection('missions').doc();

    try {
      await firestore.runTransaction((transaction) async {
        final sosDoc = await transaction.get(sosRef);
        if (!sosDoc.exists) throw Exception('SOS Request no longer exists.');
        final currentStatus = sosDoc.data()?['status'] ?? 'open';
        if (currentStatus != 'open') {
          throw Exception(
            'This emergency has already been taken by another responder.',
          );
        }

        transaction.set(missionRef, {
          'id': missionRef.id,
          'sos_id': sos.id,
          'rescuer_id': uid,
          'status': 'en_route',
          'created_at': FieldValue.serverTimestamp(),
          'completed_at': null,
          'notes': '',
        });

        transaction.update(sosRef, {
          'status': 'assigned',
          'assigned_rescuer_id': uid,
        });

        transaction.update(rescuerRef, {
          'active_mission_count': FieldValue.increment(1),
        });
      });

      _closePanel();
      if (!mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ActiveNavigationScreen(missionId: missionRef.id),
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.toString().replaceAll('Exception:', '').trim()),
            backgroundColor: AppTheme.dangerRed,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _accepting = false);
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
    double minLat = points.first.latitude, maxLat = points.first.latitude;
    double minLng = points.first.longitude, maxLng = points.first.longitude;
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
        120,
      ),
    );
  }

  String _priorityLabel(SOSRequestModel sos) {
    if (sos.createdAt == null) return 'MODERATE';
    final m = DateTime.now().difference(sos.createdAt!).inMinutes;
    if (m > 30) return 'CRITICAL';
    if (m > 15) return 'HIGH';
    return 'MODERATE';
  }

  Color _priorityColor(String p) {
    if (p == 'CRITICAL') return AppTheme.dangerRed;
    if (p == 'HIGH') return AppTheme.warningOrange;
    return AppTheme.successGreen;
  }

  String _timeAgo(DateTime? dt) {
    if (dt == null) return '';
    final d = DateTime.now().difference(dt);
    if (d.inMinutes < 1) return 'Just now';
    if (d.inMinutes < 60) return '${d.inMinutes}m ago';
    return '${d.inHours}h ago';
  }

  Map<String, int> _counts() {
    int c = 0, h = 0, m = 0;
    for (final s in _sosList) {
      final p = _priorityLabel(s);
      if (p == 'CRITICAL')
        c++;
      else if (p == 'HIGH')
        h++;
      else
        m++;
    }
    return {'CRITICAL': c, 'HIGH': h, 'MODERATE': m};
  }

  List<SOSRequestModel> get _filteredSos => _activeFilter == null
      ? _sosList
      : _sosList.where((s) => _priorityLabel(s) == _activeFilter).toList();

  void _recenter() {
    if (_rescuerLatLng != null) {
      _mapController?.animateCamera(
        CameraUpdate.newLatLngZoom(_rescuerLatLng!, 15),
      );
    }
  }

  @override
  void dispose() {
    _sosSubscription?.cancel();
    _panelController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final counts = _counts();
    final topPad = MediaQuery.of(context).padding.top;

    return Scaffold(
      body: Stack(
        children: [
          // ── Map ────────────────────────────────────────────────────────────
          GoogleMap(
            initialCameraPosition: CameraPosition(
              target: _rescuerLatLng ?? const LatLng(14.5995, 120.9842),
              zoom: 14,
            ),
            markers: _markers,
            polylines: _polylines,
            myLocationEnabled: false,
            myLocationButtonEnabled: false,
            trafficEnabled: false,
            zoomControlsEnabled: false,
            onMapCreated: (c) {
              _mapController = c;
              if (_rescuerLatLng != null) {
                c.animateCamera(
                  CameraUpdate.newLatLngZoom(_rescuerLatLng!, 14),
                );
              }
            },
            onTap: (_) {
              if (_panelVisible) _closePanel();
              if (_sosListExpanded) setState(() => _sosListExpanded = false);
              if (_polylines.isNotEmpty) setState(() => _polylines.clear());
            },
          ),

          // ── Top bar ────────────────────────────────────────────────────────
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Container(
              padding: EdgeInsets.fromLTRB(16, topPad + 10, 16, 14),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    AppTheme.primaryBlue.withOpacity(0.96),
                    AppTheme.primaryBlue.withOpacity(0.0),
                  ],
                  stops: const [0.5, 1.0],
                ),
              ),
              child: Row(
                children: [
                  const Text(
                    'Rescue Map',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      letterSpacing: -0.3,
                    ),
                  ),
                  const Spacer(),
                  _LayerToggle(
                    icon: Icons.sos_outlined,
                    label: 'SOS',
                    active: _showSosMarkers,
                    activeColor: AppTheme.dangerRed,
                    onTap: () {
                      setState(() => _showSosMarkers = !_showSosMarkers);
                      _rebuildMarkers();
                    },
                  ),
                  const SizedBox(width: 6),
                  _LayerToggle(
                    icon: Icons.local_hospital_outlined,
                    label: 'Evac',
                    active: _showEvacCenters,
                    activeColor: AppTheme.successGreen,
                    onTap: () {
                      setState(() => _showEvacCenters = !_showEvacCenters);
                      _rebuildMarkers();
                    },
                  ),
                  const SizedBox(width: 6),
                  GestureDetector(
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const MissionQueueScreen(),
                      ),
                    ),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 7,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.12),
                            blurRadius: 6,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.assignment_outlined,
                            size: 14,
                            color: AppTheme.primaryBlue,
                          ),
                          SizedBox(width: 4),
                          Text(
                            'Missions',
                            style: TextStyle(
                              color: AppTheme.primaryBlue,
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // ── Bottom tray ────────────────────────────────────────────────────
          if (!_panelVisible)
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: Container(
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black26,
                      blurRadius: 16,
                      offset: Offset(0, -4),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      margin: const EdgeInsets.only(top: 10, bottom: 8),
                      width: 36,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.grey.shade300,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),

                    // Header row
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 0, 16, 0),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                '${_sosList.length}',
                                style: const TextStyle(
                                  fontSize: 36,
                                  fontWeight: FontWeight.w800,
                                  color: AppTheme.textPrimary,
                                  height: 1,
                                ),
                              ),
                              const Text(
                                'Active SOS',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: AppTheme.textSecondary,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(width: 20),
                          _FilterPill(
                            label: 'CRITICAL',
                            count: counts['CRITICAL'] ?? 0,
                            color: AppTheme.dangerRed,
                            selected: _activeFilter == 'CRITICAL',
                            onTap: () => setState(
                              () => _activeFilter = _activeFilter == 'CRITICAL'
                                  ? null
                                  : 'CRITICAL',
                            ),
                          ),
                          const SizedBox(width: 8),
                          _FilterPill(
                            label: 'HIGH',
                            count: counts['HIGH'] ?? 0,
                            color: AppTheme.warningOrange,
                            selected: _activeFilter == 'HIGH',
                            onTap: () => setState(
                              () => _activeFilter = _activeFilter == 'HIGH'
                                  ? null
                                  : 'HIGH',
                            ),
                          ),
                          const SizedBox(width: 8),
                          _FilterPill(
                            label: 'MOD',
                            count: counts['MODERATE'] ?? 0,
                            color: AppTheme.successGreen,
                            selected: _activeFilter == 'MODERATE',
                            onTap: () => setState(
                              () => _activeFilter = _activeFilter == 'MODERATE'
                                  ? null
                                  : 'MODERATE',
                            ),
                          ),
                          const Spacer(),
                          Material(
                            color: AppTheme.primaryBlue,
                            borderRadius: BorderRadius.circular(12),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(12),
                              onTap: _recenter,
                              child: const Padding(
                                padding: EdgeInsets.all(10),
                                child: Icon(
                                  Icons.my_location,
                                  color: Colors.white,
                                  size: 20,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 12),

                    // Expand/collapse toggle
                    if (_sosList.isNotEmpty)
                      GestureDetector(
                        onTap: () => setState(
                          () => _sosListExpanded = !_sosListExpanded,
                        ),
                        child: Container(
                          margin: const EdgeInsets.symmetric(horizontal: 20),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 9,
                          ),
                          decoration: BoxDecoration(
                            color: AppTheme.background,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: AppTheme.divider),
                          ),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.list_alt_outlined,
                                size: 16,
                                color: AppTheme.textSecondary,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                _sosListExpanded
                                    ? 'Hide SOS list'
                                    : 'View all SOS requests (${_filteredSos.length})',
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: AppTheme.textSecondary,
                                ),
                              ),
                              const Spacer(),
                              AnimatedRotation(
                                turns: _sosListExpanded ? 0.5 : 0,
                                duration: const Duration(milliseconds: 250),
                                child: const Icon(
                                  Icons.keyboard_arrow_down,
                                  size: 18,
                                  color: AppTheme.textSecondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),

                    // SOS list
                    AnimatedSize(
                      duration: const Duration(milliseconds: 280),
                      curve: Curves.easeOutCubic,
                      child: _sosListExpanded
                          ? ConstrainedBox(
                              constraints: BoxConstraints(
                                maxHeight:
                                    MediaQuery.of(context).size.height * 0.38,
                              ),
                              child: ListView.separated(
                                padding: const EdgeInsets.fromLTRB(
                                  20,
                                  10,
                                  20,
                                  4,
                                ),
                                shrinkWrap: true,
                                itemCount: _filteredSos.length,
                                separatorBuilder: (_, __) =>
                                    const SizedBox(height: 8),
                                itemBuilder: (_, i) {
                                  final sos = _filteredSos[i];
                                  final priority = _priorityLabel(sos);
                                  final color = _priorityColor(priority);
                                  return FutureBuilder<UserModel?>(
                                    future: _firestoreService.getUserById(
                                      sos.citizenId,
                                    ),
                                    builder: (context, userSnap) {
                                      final citizen = userSnap.data;
                                      final displayName = citizen != null
                                          ? '${citizen.firstName ?? ''} ${citizen.lastName ?? ''}'
                                                .trim()
                                          : (sos.citizenName.isNotEmpty
                                                ? sos.citizenName
                                                : null);
                                      return GestureDetector(
                                        onTap: () => _onSosTapped(sos),
                                        child: Container(
                                          padding: const EdgeInsets.all(14),
                                          decoration: BoxDecoration(
                                            color: color.withOpacity(0.05),
                                            borderRadius: BorderRadius.circular(
                                              14,
                                            ),
                                            border: Border.all(
                                              color: color.withOpacity(0.25),
                                            ),
                                          ),
                                          child: Row(
                                            children: [
                                              Container(
                                                width: 8,
                                                height: 8,
                                                decoration: BoxDecoration(
                                                  color: color,
                                                  shape: BoxShape.circle,
                                                ),
                                              ),
                                              const SizedBox(width: 10),
                                              Expanded(
                                                child: Column(
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.start,
                                                  children: [
                                                    Row(
                                                      children: [
                                                        Container(
                                                          padding:
                                                              const EdgeInsets.symmetric(
                                                                horizontal: 6,
                                                                vertical: 2,
                                                              ),
                                                          decoration: BoxDecoration(
                                                            color: color,
                                                            borderRadius:
                                                                BorderRadius.circular(
                                                                  4,
                                                                ),
                                                          ),
                                                          child: Text(
                                                            priority,
                                                            style:
                                                                const TextStyle(
                                                                  color: Colors
                                                                      .white,
                                                                  fontSize: 9,
                                                                  fontWeight:
                                                                      FontWeight
                                                                          .w800,
                                                                ),
                                                          ),
                                                        ),
                                                        const Spacer(),
                                                        Text(
                                                          _timeAgo(
                                                            sos.createdAt,
                                                          ),
                                                          style: TextStyle(
                                                            color: AppTheme
                                                                .textSecondary,
                                                            fontSize: 11,
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                    const SizedBox(height: 4),
                                                    // Name
                                                    Text(
                                                      displayName?.isNotEmpty ==
                                                              true
                                                          ? displayName!
                                                          : (userSnap.connectionState ==
                                                                    ConnectionState
                                                                        .waiting
                                                                ? 'Loading...'
                                                                : 'Unknown Citizen'),
                                                      style: const TextStyle(
                                                        fontWeight:
                                                            FontWeight.w700,
                                                        fontSize: 14,
                                                        color: AppTheme
                                                            .textPrimary,
                                                      ),
                                                    ),
                                                    const SizedBox(height: 3),
                                                    // Address or description
                                                    if ((sos.address != null &&
                                                        sos
                                                            .address!
                                                            .isNotEmpty))
                                                      Row(
                                                        children: [
                                                          Icon(
                                                            Icons
                                                                .location_on_outlined,
                                                            size: 12,
                                                            color: AppTheme
                                                                .textSecondary,
                                                          ),
                                                          const SizedBox(
                                                            width: 2,
                                                          ),
                                                          Expanded(
                                                            child: Text(
                                                              sos.address!,
                                                              style: TextStyle(
                                                                color: AppTheme
                                                                    .textSecondary,
                                                                fontSize: 12,
                                                              ),
                                                              maxLines: 1,
                                                              overflow:
                                                                  TextOverflow
                                                                      .ellipsis,
                                                            ),
                                                          ),
                                                        ],
                                                      )
                                                    else if (sos.description !=
                                                            null &&
                                                        sos
                                                            .description!
                                                            .isNotEmpty)
                                                      Row(
                                                        children: [
                                                          Icon(
                                                            Icons
                                                                .notes_outlined,
                                                            size: 12,
                                                            color: AppTheme
                                                                .textSecondary,
                                                          ),
                                                          const SizedBox(
                                                            width: 2,
                                                          ),
                                                          Expanded(
                                                            child: Text(
                                                              sos.description!,
                                                              style: TextStyle(
                                                                color: AppTheme
                                                                    .textSecondary,
                                                                fontSize: 12,
                                                              ),
                                                              maxLines: 1,
                                                              overflow:
                                                                  TextOverflow
                                                                      .ellipsis,
                                                            ),
                                                          ),
                                                        ],
                                                      )
                                                    else
                                                      Row(
                                                        children: [
                                                          Icon(
                                                            Icons
                                                                .location_off_outlined,
                                                            size: 12,
                                                            color: AppTheme
                                                                .textSecondary,
                                                          ),
                                                          const SizedBox(
                                                            width: 2,
                                                          ),
                                                          Text(
                                                            'Location on map',
                                                            style: TextStyle(
                                                              color: AppTheme
                                                                  .textSecondary,
                                                              fontSize: 12,
                                                              fontStyle:
                                                                  FontStyle
                                                                      .italic,
                                                            ),
                                                          ),
                                                        ],
                                                      ),
                                                    const SizedBox(height: 5),
                                                    // Quick-info chips: people count + blood type
                                                    Row(
                                                      children: [
                                                        _InfoChip(
                                                          icon: Icons
                                                              .people_outline,
                                                          label:
                                                              '${sos.personsCount} ${sos.personsCount == 1 ? 'person' : 'persons'}',
                                                        ),
                                                        const SizedBox(
                                                          width: 6,
                                                        ),
                                                        if (sos.bloodType !=
                                                            'N/A')
                                                          _InfoChip(
                                                            icon: Icons
                                                                .bloodtype_outlined,
                                                            label:
                                                                sos.bloodType,
                                                          ),
                                                      ],
                                                    ),
                                                  ],
                                                ),
                                              ),
                                              const SizedBox(width: 8),
                                              Icon(
                                                Icons.chevron_right,
                                                color: color,
                                                size: 20,
                                              ),
                                            ],
                                          ),
                                        ),
                                      );
                                    }, // FutureBuilder builder end
                                  ); // FutureBuilder end
                                },
                              ),
                            )
                          : const SizedBox.shrink(),
                    ),

                    const SizedBox(height: 12),
                  ],
                ),
              ),
            ),

          // ── SOS Detail panel ───────────────────────────────────────────────
          if (_panelVisible && _selectedSos != null)
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: SlideTransition(
                position: _panelSlide,
                child: _SosDetailPanel(
                  sos: _selectedSos!,
                  priority: _priorityLabel(_selectedSos!),
                  priorityColor: _priorityColor(_priorityLabel(_selectedSos!)),
                  timeAgo: _timeAgo(_selectedSos!.createdAt),
                  etaMinutes: _previewEtaMinutes,
                  distanceKm: _previewDistanceKm,
                  accepting: _accepting,
                  onAccept: () => _acceptMission(_selectedSos!),
                  onDismiss: _closePanel,
                ),
              ),
            ),
        ],
      ),
      bottomNavigationBar: RescuerBottomNav(currentIndex: 1),
    );
  }
}

// ── Widgets ───────────────────────────────────────────────────────────────────

class _LayerToggle extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool active;
  final Color activeColor;
  final VoidCallback onTap;

  const _LayerToggle({
    required this.icon,
    required this.label,
    required this.active,
    required this.activeColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
        decoration: BoxDecoration(
          color: active ? activeColor : Colors.white.withOpacity(0.2),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.white.withOpacity(0.3)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 13, color: Colors.white),
            const SizedBox(width: 3),
            Text(
              label,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FilterPill extends StatelessWidget {
  final String label;
  final int count;
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  const _FilterPill({
    required this.label,
    required this.count,
    required this.color,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? color : color.withOpacity(0.08),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: selected ? color : color.withOpacity(0.3)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '$count',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: selected ? Colors.white : color,
                height: 1,
              ),
            ),
            const SizedBox(height: 1),
            Text(
              label,
              style: TextStyle(
                fontSize: 8,
                fontWeight: FontWeight.w700,
                color: selected ? Colors.white : color,
                letterSpacing: 0.2,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SosDetailPanel extends StatelessWidget {
  final SOSRequestModel sos;
  final String priority;
  final Color priorityColor;
  final String timeAgo;
  final double? etaMinutes;
  final double? distanceKm;
  final bool accepting;
  final VoidCallback onAccept;
  final VoidCallback onDismiss;

  const _SosDetailPanel({
    required this.sos,
    required this.priority,
    required this.priorityColor,
    required this.timeAgo,
    required this.etaMinutes,
    required this.distanceKm,
    required this.accepting,
    required this.onAccept,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        boxShadow: [
          BoxShadow(
            color: Colors.black26,
            blurRadius: 20,
            offset: Offset(0, -6),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle
          Container(
            margin: const EdgeInsets.only(top: 10, bottom: 4),
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey.shade300,
              borderRadius: BorderRadius.circular(4),
            ),
          ),

          // Priority + time + close
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 12, 0),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: priorityColor,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    priority,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  timeAgo,
                  style: const TextStyle(
                    color: AppTheme.textSecondary,
                    fontSize: 12,
                  ),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.close, size: 20),
                  onPressed: onDismiss,
                  color: AppTheme.textSecondary,
                ),
              ],
            ),
          ),

          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Name
                Text(
                  sos.citizenName,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.textPrimary,
                  ),
                ),

                // Address
                if (sos.address != null && sos.address!.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      const Icon(
                        Icons.location_on_outlined,
                        size: 14,
                        color: AppTheme.textSecondary,
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          sos.address!,
                          style: const TextStyle(
                            fontSize: 13,
                            color: AppTheme.textSecondary,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ],

                if (sos.description != null && sos.description!.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    sos.description!,
                    style: const TextStyle(
                      fontSize: 13,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                ],

                const SizedBox(height: 12),

                // ETA banner
                if (etaMinutes != null)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: AppTheme.primaryBlue,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(
                          Icons.timer_outlined,
                          color: Colors.white,
                          size: 18,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'ETA: ${etaMinutes!.toStringAsFixed(0)} min'
                          '${distanceKm != null ? '  •  ${distanceKm!.toStringAsFixed(1)} km' : ''}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                          ),
                        ),
                      ],
                    ),
                  )
                else
                  // Loading ETA
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                        SizedBox(width: 8),
                        Text(
                          'Calculating route…',
                          style: TextStyle(
                            color: AppTheme.textSecondary,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),

                const SizedBox(height: 12),

                // Info chips
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _InfoChip(
                      icon: Icons.people_outline,
                      label:
                          '${sos.personsCount} person${sos.personsCount > 1 ? 's' : ''}',
                    ),
                    _InfoChip(
                      icon: Icons.bloodtype_outlined,
                      label: sos.bloodType,
                    ),
                  ],
                ),

                const SizedBox(height: 16),

                // Accept button
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: accepting ? null : onAccept,
                    icon: accepting
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.check_circle_outline),
                    label: Text(
                      accepting ? 'Accepting…' : 'Accept Mission',
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppTheme.primaryBlue,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  final IconData icon;
  final String label;

  const _InfoChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppTheme.background,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: AppTheme.textSecondary),
          const SizedBox(width: 4),
          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: AppTheme.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}
