import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:share_plus/share_plus.dart'; // Siguraduhing na-install sa pubspec.yaml
import 'package:url_launcher/url_launcher.dart'; // Para sa canLaunchUrl at launchUrl

import '../../models/sos_request_model.dart';
import '../../models/user_model.dart';
import '../../services/firestore_service.dart';
import '../../services/location_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_bottom_nav.dart';

class RescuerAssignedScreen extends StatefulWidget {
  final String sosId;
  const RescuerAssignedScreen({super.key, required this.sosId});

  @override
  State<RescuerAssignedScreen> createState() => _RescuerAssignedScreenState();
}

class _RescuerAssignedScreenState extends State<RescuerAssignedScreen>
    with SingleTickerProviderStateMixin {
  final FirestoreService _firestoreService = FirestoreService.instance;
  final LocationService _locationService = LocationService.instance;

  StreamSubscription? _sosSubscription;
  StreamSubscription? _rescuerLocationSubscription;

  SosRequestModel? _sosRequest;
  UserModel? _rescuerUser;
  Map<String, dynamic>? _rescuerData;

  LatLng? _victimLatLng;
  LatLng? _rescuerLatLng;
  double? _etaMinutes;

  GoogleMapController? _mapController;
  final Set<Marker> _markers = {};
  final Set<Polyline> _polylines = {};

  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  bool _loadingRescuer = false;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    )..repeat(reverse: true);
    _pulseAnimation = Tween<double>(
      begin: 0.7,
      end: 1.0,
    ).animate(_pulseController);

    _listenToSos();
  }

  void _listenToSos() {
    _sosSubscription = _firestoreService.sosRequestStream(widget.sosId).listen((
      sos,
    ) {
      if (!mounted) return;
      setState(() => _sosRequest = sos);

      if (sos == null) return;

      _victimLatLng = LatLng(sos.latitude, sos.longitude);
      _updateVictimMarker();

      if (sos.assignedRescuerId != null && !_loadingRescuer) {
        _loadRescuerAndListen(sos.assignedRescuerId!);
      }
    });
  }

  Future<void> _loadRescuerAndListen(String rescuerId) async {
    _loadingRescuer = true;
    try {
      final user = await _firestoreService.getUserById(rescuerId);
      final rescuerDoc = await _firestoreService.getRescuerById(rescuerId);
      if (!mounted) return;
      setState(() {
        _rescuerUser = user;
        _rescuerData = rescuerDoc;
      });
    } catch (e) {
      debugPrint('Error loading rescuer: $e');
    }

    _rescuerLocationSubscription?.cancel();
    _rescuerLocationSubscription = _firestoreService
        .rescuerStream(rescuerId)
        .listen((data) {
          if (!mounted || data == null) return;
          final lat = data['latitude'] as double?;
          final lng = data['longitude'] as double?;
          if (lat == null || lng == null) return;

          setState(() {
            _rescuerLatLng = LatLng(lat, lng);
            _updateRescuerMarker();
            _updatePolyline();
            _recalculateEta();
            _animateToFitRoute();
          });
        });
  }

  void _updateVictimMarker() {
    if (_victimLatLng == null) return;
    _markers.removeWhere((m) => m.markerId.value == 'victim');
    _markers.add(
      Marker(
        markerId: const MarkerId('victim'),
        position: _victimLatLng!,
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
        infoWindow: const InfoWindow(title: 'Your Location (V)'),
      ),
    );
  }

  void _updateRescuerMarker() {
    if (_rescuerLatLng == null) return;
    _markers.removeWhere((m) => m.markerId.value == 'rescuer');
    _markers.add(
      Marker(
        markerId: const MarkerId('rescuer'),
        position: _rescuerLatLng!,
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueBlue),
        infoWindow: const InfoWindow(title: 'Rescuer (R)'),
      ),
    );
  }

  void _updatePolyline() {
    if (_victimLatLng == null || _rescuerLatLng == null) return;
    _polylines.clear();
    _polylines.add(
      Polyline(
        polylineId: const PolylineId('route'),
        points: [_rescuerLatLng!, _victimLatLng!],
        color: AppTheme.primaryBlue,
        width: 3,
        patterns: [PatternItem.dash(12), PatternItem.gap(8)],
      ),
    );
  }

  void _animateToFitRoute() {
    if (_mapController == null ||
        _victimLatLng == null ||
        _rescuerLatLng == null)
      return;

    LatLngBounds bounds = LatLngBounds(
      southwest: LatLng(
        min(_rescuerLatLng!.latitude, _victimLatLng!.latitude),
        min(_rescuerLatLng!.longitude, _victimLatLng!.longitude),
      ),
      northeast: LatLng(
        max(_rescuerLatLng!.latitude, _victimLatLng!.latitude),
        max(_rescuerLatLng!.longitude, _victimLatLng!.longitude),
      ),
    );

    _mapController!.animateCamera(CameraUpdate.newLatLngBounds(bounds, 50));
  }

  void _recalculateEta() {
    if (_victimLatLng == null || _rescuerLatLng == null) return;
    final distKm = _locationService.calculateDistance(
      _rescuerLatLng!.latitude,
      _rescuerLatLng!.longitude,
      _victimLatLng!.latitude,
      _victimLatLng!.longitude,
    );
    setState(() => _etaMinutes = (distKm / 40) * 60);
  }

  Future<void> _callRescuer() async {
    final phone = _rescuerUser?.phone ?? _rescuerData?['phone'];
    if (phone == null) return;
    final uri = Uri(scheme: 'tel', path: phone);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
  }

  void _shareLocation() {
    if (_victimLatLng == null) return;
    Share.share(
      'My emergency location: ${_victimLatLng!.latitude}, ${_victimLatLng!.longitude}\n'
      'https://www.google.com/maps/search/?api=1&query=${_victimLatLng!.latitude},${_victimLatLng!.longitude}',
    );
  }

  @override
  void dispose() {
    _sosSubscription?.cancel();
    _rescuerLocationSubscription?.cancel();
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final assigned = _sosRequest?.assignedRescuerId != null;
    final arrived = _sosRequest?.status == 'arrived';

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: AppTheme.primaryBlue,
        foregroundColor: Colors.white,
        title: const Text(
          'Rescuer Status',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        elevation: 0,
      ),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            color: AppTheme.successGreen,
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
            child: const Row(
              children: [
                Icon(Icons.location_on, color: Colors.white, size: 18),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Rescuer can see your live location',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                  ),
                ),
              ],
            ),
          ),
          SizedBox(
            height: MediaQuery.of(context).size.height * 0.38,
            child: assigned && _victimLatLng != null
                ? GoogleMap(
                    initialCameraPosition: CameraPosition(
                      target: _victimLatLng!,
                      zoom: 14,
                    ),
                    markers: _markers,
                    polylines: _polylines,
                    onMapCreated: (c) => _mapController = c,
                    myLocationButtonEnabled: false,
                  )
                : _buildWaitingMap(),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: assigned
                  ? _buildAssignedContent(arrived)
                  : _buildWaitingContent(),
            ),
          ),
        ],
      ),
      bottomNavigationBar: AppBottomNav(currentIndex: 0),
    );
  }

  Widget _buildWaitingMap() {
    return Container(
      color: Colors.grey[200],
      child: const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.map_outlined, size: 48, color: Colors.grey),
            SizedBox(height: 8),
            Text(
              'Waiting for rescuer assignment...',
              style: TextStyle(color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWaitingContent() {
    return Column(
      children: [
        const SizedBox(height: 16),
        AnimatedBuilder(
          animation: _pulseAnimation,
          builder: (_, __) => Opacity(
            opacity: _pulseAnimation.value,
            child: Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.06),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: const Column(
                children: [
                  CircularProgressIndicator(color: AppTheme.primaryBlue),
                  SizedBox(height: 16),
                  Text(
                    'Waiting for rescuer...',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  SizedBox(height: 8),
                  Text(
                    'Your SOS has been received.',
                    style: TextStyle(color: AppTheme.textSecondary),
                  ),
                  SizedBox(height: 4),
                  Text(
                    'A rescuer will be assigned shortly.',
                    style: TextStyle(color: AppTheme.textSecondary),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppTheme.successGreen.withOpacity(0.1),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppTheme.successGreen.withOpacity(0.3)),
          ),
          child: const Row(
            children: [
              Icon(Icons.check_circle, color: AppTheme.successGreen),
              SizedBox(width: 12),
              Expanded(
                child: Text(
                  'SOS request submitted successfully.',
                  style: TextStyle(
                    color: AppTheme.successGreen,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildAssignedContent(bool arrived) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_etaMinutes != null)
          Container(
            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 20),
            decoration: BoxDecoration(
              color: AppTheme.primaryBlue,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.timer, color: Colors.white),
                const SizedBox(width: 8),
                Text(
                  'ETA: ${_etaMinutes!.toStringAsFixed(0)} min',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        const SizedBox(height: 16),
        Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            decoration: BoxDecoration(
              color: arrived ? AppTheme.successGreen : AppTheme.primaryBlue,
              borderRadius: BorderRadius.circular(24),
            ),
            child: Text(
              arrived ? '✅   Arrived' : '🚐   En Route',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 15,
              ),
            ),
          ),
        ),
        const SizedBox(height: 16),
        if (_rescuerData != null || _rescuerUser != null)
          Card(
            elevation: 2,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Rescuer Info',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                  const Divider(height: 20),
                  _infoRow(
                    Icons.groups,
                    _rescuerData?['team_name'] ?? 'Unknown Team',
                  ),
                  _infoRow(
                    Icons.account_balance,
                    _rescuerData?['agency'] ?? 'Unknown Agency',
                  ),
                  _infoRow(Icons.badge, _rescuerData?['badge_number'] ?? 'N/A'),
                  _infoRow(
                    Icons.person,
                    _rescuerData?['lead_officer'] ??
                        _rescuerUser?.displayName ??
                        'Unknown Officer',
                  ),
                ],
              ),
            ),
          ),
        const SizedBox(height: 16),
        ElevatedButton.icon(
          onPressed: _callRescuer,
          icon: const Icon(Icons.phone),
          label: const Text('Call Rescuer'),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppTheme.successGreen,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
        const SizedBox(height: 10),
        OutlinedButton.icon(
          onPressed: _shareLocation,
          icon: const Icon(Icons.share),
          label: const Text('Share Location'),
          style: OutlinedButton.styleFrom(
            foregroundColor: AppTheme.primaryBlue,
            side: const BorderSide(color: AppTheme.primaryBlue),
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
      ],
    );
  }

  Widget _infoRow(IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Icon(icon, size: 18, color: AppTheme.primaryBlue),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: const TextStyle(fontSize: 14))),
        ],
      ),
    );
  }
}
