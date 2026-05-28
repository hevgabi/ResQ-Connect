import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:ui' as ui;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../models/sos_request_model.dart';
import '../../models/user_model.dart';
import '../../services/firestore_service.dart';
import '../../services/location_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_bottom_nav.dart';
import 'citizen_home_screen.dart';

const String _apiKey = 'AIzaSyCOooBNKqe-MshDk11ADPQQDK7k90W5Sl4';
const double _routeRefreshThresholdMeters = 50.0;
const int _routeDebounceSeconds = 15;

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
  double? _distanceKm;
  bool _routeLoaded = false;
  bool _fetchingDirections = false;
  LatLng? _lastDirectionsFetchLatLng;
  DateTime? _lastDirectionsFetchTime;

  GoogleMapController? _mapController;
  final Set<Marker> _markers = {};
  final Set<Polyline> _polylines = {};
  BitmapDescriptor? _rescuerIcon;

  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  bool _loadingRescuer = false;

  // Track whether we've already shown the arrived banner / review sheet
  bool _onSiteShown = false;
  bool _arrivedSheetShown = false;

  // Cancel button — visible for 30 s from screen load, only while status == open
  bool _cancelButtonVisible = true;
  Timer? _cancelVisibilityTimer;

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
    // Cancel button disappears after 30 seconds
    _cancelVisibilityTimer = Timer(const Duration(seconds: 30), () {
      if (mounted) setState(() => _cancelButtonVisible = false);
    });
  }

  void _listenToSos() {
    _sosSubscription = _firestoreService.sosRequestStream(widget.sosId).listen((
      sos,
    ) {
      if (!mounted) return;
      setState(() {
        _sosRequest = sos;
        if (sos != null) {
          _victimLatLng = LatLng(sos.latitude, sos.longitude);
        }
      });
      if (sos == null) return;
      _updateVictimMarker();
      if (sos.assignedRescuerId != null && !_loadingRescuer) {
        _loadRescuerAndListen(sos.assignedRescuerId!);
      }
      // Show review sheet only when the mission is fully resolved
      if (sos.status == 'resolved' && !_arrivedSheetShown) {
        _arrivedSheetShown = true;
        // Small delay so the UI settles first
        Future.delayed(const Duration(milliseconds: 800), () {
          if (mounted) _showReviewSheet();
        });
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

          final newLatLng = LatLng(lat, lng);
          setState(() {
            _rescuerLatLng = newLatLng;
            _animateToFitRoute();
          });
          _updateRescuerMarker();

          _recalculateEtaFallback(newLatLng);
          _maybeRefreshRoute(newLatLng);
        });
  }

  void _maybeRefreshRoute(LatLng rescuerPos) {
    if (_fetchingDirections || _victimLatLng == null) return;
    final bool noRoute = !_routeLoaded;
    final bool movedEnough =
        _lastDirectionsFetchLatLng == null ||
        _haversineMeters(_lastDirectionsFetchLatLng!, rescuerPos) >=
            _routeRefreshThresholdMeters;
    final bool cooledDown =
        _lastDirectionsFetchTime == null ||
        DateTime.now().difference(_lastDirectionsFetchTime!).inSeconds >=
            _routeDebounceSeconds;
    if (noRoute || (movedEnough && cooledDown)) {
      _fetchDirections(rescuerPos);
    }
  }

  Future<void> _fetchDirections(LatLng rescuerPos) async {
    _fetchingDirections = true;
    _lastDirectionsFetchLatLng = rescuerPos;
    _lastDirectionsFetchTime = DateTime.now();
    try {
      final uri = Uri.parse(
        'https://maps.googleapis.com/maps/api/directions/json'
        '?origin=${rescuerPos.latitude},${rescuerPos.longitude}'
        '&destination=${_victimLatLng!.latitude},${_victimLatLng!.longitude}'
        '&mode=driving'
        '&alternatives=false'
        '&traffic_model=best_guess'
        '&departure_time=now'
        '&key=$_apiKey',
      );
      final response = await http.get(uri).timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) return;
      final json = jsonDecode(response.body) as Map<String, dynamic>;
      if (json['status'] != 'OK') return;
      final routes = json['routes'] as List?;
      if (routes == null || routes.isEmpty) return;
      final route = routes[0] as Map<String, dynamic>;
      final leg = (route['legs'] as List)[0] as Map<String, dynamic>;
      final durField = leg['duration_in_traffic'] ?? leg['duration'];
      final etaSecs = (durField?['value'] as int?) ?? 0;
      final distMeters = (leg['distance']?['value'] as int?) ?? 0;
      final encoded = route['overview_polyline']['points'] as String;
      final List<LatLng> points = _decodePolyline(encoded);
      if (!mounted) return;
      setState(() {
        _etaMinutes = etaSecs / 60.0;
        _distanceKm = distMeters / 1000.0;
        _routeLoaded = true;
        _polylines
          ..clear()
          ..add(
            Polyline(
              polylineId: const PolylineId('rescue_route'),
              points: points,
              color: AppTheme.primaryBlue,
              width: 5,
              startCap: Cap.roundCap,
              endCap: Cap.roundCap,
              jointType: JointType.round,
              geodesic: true,
            ),
          );
      });
      if (_mapController != null && points.isNotEmpty) {
        _mapController!.animateCamera(
          CameraUpdate.newLatLngBounds(
            _latLngBoundsFrom([rescuerPos, _victimLatLng!, ...points]),
            60,
          ),
        );
      }
    } catch (e) {
      debugPrint('Directions fetch error (citizen): $e');
    } finally {
      _fetchingDirections = false;
    }
  }

  void _recalculateEtaFallback(LatLng from) {
    if (_routeLoaded || _victimLatLng == null) return;
    final distKm = _locationService.calculateDistance(
      from.latitude,
      from.longitude,
      _victimLatLng!.latitude,
      _victimLatLng!.longitude,
    );
    if (!mounted) return;
    setState(() {
      _etaMinutes = (distKm / 40) * 60;
      _distanceKm = distKm;
    });
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

  double _haversineMeters(LatLng a, LatLng b) {
    const double r = 6371000;
    final double dLat = _rad(b.latitude - a.latitude);
    final double dLng = _rad(b.longitude - a.longitude);
    final double h =
        pow(sin(dLat / 2), 2) +
        cos(_rad(a.latitude)) * cos(_rad(b.latitude)) * pow(sin(dLng / 2), 2);
    return 2 * r * asin(sqrt(h));
  }

  double _rad(double deg) => deg * pi / 180;

  LatLngBounds _latLngBoundsFrom(List<LatLng> points) {
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

  void _animateToFitRoute() {
    if (_mapController == null ||
        _victimLatLng == null ||
        _rescuerLatLng == null)
      return;
    _mapController!.animateCamera(
      CameraUpdate.newLatLngBounds(
        LatLngBounds(
          southwest: LatLng(
            min(_rescuerLatLng!.latitude, _victimLatLng!.latitude),
            min(_rescuerLatLng!.longitude, _victimLatLng!.longitude),
          ),
          northeast: LatLng(
            max(_rescuerLatLng!.latitude, _victimLatLng!.latitude),
            max(_rescuerLatLng!.longitude, _victimLatLng!.longitude),
          ),
        ),
        60,
      ),
    );
  }

  void _updateVictimMarker() {
    if (_victimLatLng == null) return;
    _markers.removeWhere((m) => m.markerId.value == 'victim');
    _markers.add(
      Marker(
        markerId: const MarkerId('victim'),
        position: _victimLatLng!,
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
        infoWindow: const InfoWindow(
          title: '📍 Your Location',
          snippet: 'Rescuer is on the way',
        ),
        zIndex: 1,
      ),
    );
  }

  Future<BitmapDescriptor> _buildRescuerIcon() async {
    const double size = 120;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);

    // Outer white circle (border)
    final borderPaint = Paint()..color = Colors.white;
    canvas.drawCircle(const Offset(size / 2, size / 2), size / 2, borderPaint);

    // Inner blue circle
    final bgPaint = Paint()..color = const Color(0xFF1565C0);
    canvas.drawCircle(const Offset(size / 2, size / 2), size / 2 - 6, bgPaint);

    // Draw ambulance cross (white plus sign)
    final crossPaint = Paint()
      ..color = Colors.white
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 14;

    // Horizontal bar
    canvas.drawLine(
      Offset(size * 0.28, size / 2),
      Offset(size * 0.72, size / 2),
      crossPaint,
    );
    // Vertical bar
    canvas.drawLine(
      Offset(size / 2, size * 0.28),
      Offset(size / 2, size * 0.72),
      crossPaint,
    );

    final picture = recorder.endRecording();
    final image = await picture.toImage(size.toInt(), size.toInt());
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    return BitmapDescriptor.fromBytes(bytes!.buffer.asUint8List());
  }

  Future<void> _updateRescuerMarker() async {
    if (_rescuerLatLng == null) return;
    _rescuerIcon ??= await _buildRescuerIcon();
    if (!mounted) return;
    setState(() {
      _markers.removeWhere((m) => m.markerId.value == 'rescuer');
      _markers.add(
        Marker(
          markerId: const MarkerId('rescuer'),
          position: _rescuerLatLng!,
          icon: _rescuerIcon!,
          infoWindow: const InfoWindow(
            title: '🚑 Rescuer',
            snippet: 'On the way to you',
          ),
          zIndex: 2,
        ),
      );
    });
  }

  Future<void> _callRescuer() async {
    final phone = _rescuerUser?.phone ?? _rescuerData?['phone'];
    if (phone == null) return;
    final uri = Uri(scheme: 'tel', path: phone);
    if (await canLaunchUrl(uri)) await launchUrl(uri);
  }

  void _shareLocation() {
    if (_victimLatLng == null) return;
    Share.share(
      'My emergency location: ${_victimLatLng!.latitude}, ${_victimLatLng!.longitude}\n'
      'https://www.google.com/maps/search/?api=1&query=${_victimLatLng!.latitude},${_victimLatLng!.longitude}',
    );
  }

  Future<void> _cancelSosRequest() async {
    final status = _sosRequest?.status;
    // Only allow cancel if SOS is still open (unassigned)
    if (status != 'open' && status != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Cannot cancel — a rescuer has already been assigned.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cancel SOS?'),
        content: const Text(
          'Are you sure you want to cancel this SOS request? This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Keep'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(
              'Cancel SOS',
              style: TextStyle(color: Colors.red),
            ),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      await FirebaseFirestore.instance
          .collection('sos_requests')
          .doc(widget.sosId)
          .update({
            'status': 'cancelled',
            'updated_at': FieldValue.serverTimestamp(),
          });
      if (!mounted) return;
      _goHome();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to cancel. Please try again.')),
      );
    }
  }

  void _goHome() {
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const CitizenHomeScreen()),
      (route) => false,
    );
  }

  // ── Review / Rating bottom sheet ──────────────────────────────────────────
  void _showReviewSheet() {
    showModalBottomSheet(
      context: context,
      isDismissible: false,
      enableDrag: false,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _ReviewSheet(
        rescuerName:
            _rescuerData?['lead_officer'] ??
            _rescuerUser?.displayName ??
            'Your Rescuer',
        rescuerId: _sosRequest?.assignedRescuerId ?? '',
        sosId: widget.sosId,
        onDone: _goHome,
      ),
    );
  }

  @override
  void dispose() {
    _sosSubscription?.cancel();
    _rescuerLocationSubscription?.cancel();
    _pulseController.dispose();
    _cancelVisibilityTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final assigned = _sosRequest?.assignedRescuerId != null;
    final arrived =
        _sosRequest?.status == 'resolved' ||
        _sosRequest?.status == 'arrived' ||
        _sosRequest?.status == 'on_site';

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
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          tooltip: 'Back to Home',
          onPressed: () => showDialog(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Text('Leave this screen?'),
              content: const Text(
                'Your SOS will remain active. You can return to it anytime by tapping the SOS button in the bottom navigation.',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Stay'),
                ),
                TextButton(
                  onPressed: () {
                    Navigator.pop(ctx);
                    _goHome();
                  },
                  child: Text(
                    'Go Home',
                    style: TextStyle(color: AppTheme.dangerRed),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      body: Column(
        children: [
          // "Rescuer can see your location" banner
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

          // ETA banner
          if (assigned && _etaMinutes != null) _buildEtaBanner(arrived),

          // Map
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
                    onMapCreated: (c) {
                      _mapController = c;
                      if (_rescuerLatLng != null) _animateToFitRoute();
                    },
                    myLocationButtonEnabled: false,
                    trafficEnabled: true,
                    zoomControlsEnabled: true,
                  )
                : _buildWaitingMap(),
          ),

          // Bottom info panel
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
      bottomNavigationBar: AppBottomNav(currentIndex: 0, hideViewButton: true),
    );
  }

  Widget _buildEtaBanner(bool arrived) {
    if (arrived) {
      return Container(
        width: double.infinity,
        color: AppTheme.successGreen,
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.check_circle, color: Colors.white),
            SizedBox(width: 8),
            Text(
              'Rescuer has arrived!',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 15,
              ),
            ),
          ],
        ),
      );
    }

    final eta = _etaMinutes!;
    final dist = _distanceKm;
    final isRealRoute = _routeLoaded;

    return Container(
      width: double.infinity,
      color: AppTheme.primaryBlue,
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.timer_outlined, color: Colors.white, size: 20),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'ETA: ${eta.toStringAsFixed(0)} min'
                '${dist != null ? '  •  ${dist.toStringAsFixed(1)} km' : ''}',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                ),
              ),
              Text(
                isRealRoute ? 'Via fastest road route' : 'Estimating…',
                style: const TextStyle(color: Colors.white70, fontSize: 11),
              ),
            ],
          ),
          if (!isRealRoute) ...[
            const SizedBox(width: 10),
            const SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white,
              ),
            ),
          ],
        ],
      ),
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
              'Waiting for rescuer assignment…',
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
                    'Waiting for rescuer…',
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
        // Cancel button — only visible for 30 s and only when status is open
        if (_cancelButtonVisible && _sosRequest?.status == 'open') ...[
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _cancelSosRequest,
              icon: const Icon(Icons.cancel_outlined, color: Colors.red),
              label: const Text(
                'Cancel SOS Request',
                style: TextStyle(color: Colors.red),
              ),
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: Colors.red),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildAssignedContent(bool arrived) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Status chip
        Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            decoration: BoxDecoration(
              color: arrived ? AppTheme.successGreen : AppTheme.primaryBlue,
              borderRadius: BorderRadius.circular(24),
            ),
            child: Text(
              arrived ? '✅  Arrived' : '🚐  En Route',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 15,
              ),
            ),
          ),
        ),
        const SizedBox(height: 16),

        // Rescuer info card
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

        // Route info card
        if (_routeLoaded && _etaMinutes != null)
          Card(
            elevation: 2,
            color: AppTheme.primaryBlue.withOpacity(0.05),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
              side: BorderSide(color: AppTheme.primaryBlue.withOpacity(0.2)),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  const Icon(
                    Icons.route,
                    color: AppTheme.primaryBlue,
                    size: 28,
                  ),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${_etaMinutes!.toStringAsFixed(0)} min  •  ${_distanceKm?.toStringAsFixed(1) ?? '--'} km',
                        style: const TextStyle(
                          color: AppTheme.primaryBlue,
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      const Text(
                        'Fastest road route · real-time traffic',
                        style: TextStyle(
                          color: AppTheme.textSecondary,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        const SizedBox(height: 16),

        // Call button
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

        // Share location button
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

// ── Review / Rating bottom sheet ───────────────────────────────────────────────
class _ReviewSheet extends StatefulWidget {
  final String rescuerName;
  final String rescuerId;
  final String sosId;
  final VoidCallback onDone;

  const _ReviewSheet({
    required this.rescuerName,
    required this.rescuerId,
    required this.sosId,
    required this.onDone,
  });

  @override
  State<_ReviewSheet> createState() => _ReviewSheetState();
}

class _ReviewSheetState extends State<_ReviewSheet> {
  int _stars = 0;
  final TextEditingController _commentCtrl = TextEditingController();
  bool _submitting = false;

  Future<void> _submit({bool skip = false}) async {
    if (_submitting) return;
    setState(() => _submitting = true);
    try {
      if (!skip && _stars > 0) {
        final firestore = FirebaseFirestore.instance;
        // Save review to a 'rescuer_reviews' subcollection and update rescuer's avg rating
        await firestore.collection('rescuer_reviews').add({
          'rescuer_id': widget.rescuerId,
          'sos_id': widget.sosId,
          'stars': _stars,
          'comment': _commentCtrl.text.trim(),
          'created_at': FieldValue.serverTimestamp(),
        });
      }
    } catch (e) {
      debugPrint('Review submit error: $e');
    } finally {
      if (mounted) {
        Navigator.pop(context); // close sheet
        widget.onDone();
      }
    }
  }

  @override
  void dispose() {
    _commentCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.fromLTRB(
        24,
        24,
        24,
        MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle bar
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey.shade300,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          const SizedBox(height: 20),

          // Success icon
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: AppTheme.successGreen.withOpacity(0.12),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.check_circle_rounded,
              color: AppTheme.successGreen,
              size: 48,
            ),
          ),
          const SizedBox(height: 16),

          const Text(
            'You\'re safe now!',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 6),
          Text(
            'How was your experience with ${widget.rescuerName}?',
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppTheme.textSecondary, fontSize: 14),
          ),
          const SizedBox(height: 20),

          // Star rating
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(5, (i) {
              final filled = i < _stars;
              return GestureDetector(
                onTap: () => setState(() => _stars = i + 1),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: Icon(
                    filled ? Icons.star_rounded : Icons.star_outline_rounded,
                    size: 40,
                    color: filled
                        ? const Color(0xFFFFC107)
                        : Colors.grey.shade300,
                  ),
                ),
              );
            }),
          ),
          const SizedBox(height: 16),

          // Comment field
          TextField(
            controller: _commentCtrl,
            maxLines: 3,
            maxLength: 200,
            decoration: InputDecoration(
              hintText: 'Leave a comment (optional)…',
              filled: true,
              fillColor: Colors.grey.shade50,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: Colors.grey.shade200),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: Colors.grey.shade200),
              ),
            ),
          ),
          const SizedBox(height: 12),

          // Submit button
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _stars == 0 ? null : () => _submit(),
              style: FilledButton.styleFrom(
                backgroundColor: AppTheme.primaryBlue,
                disabledBackgroundColor: Colors.grey.shade200,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: _submitting
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Text(
                      'Submit Review',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
            ),
          ),
          const SizedBox(height: 10),

          // Skip
          TextButton(
            onPressed: _submitting ? null : () => _submit(skip: true),
            child: Text(
              'Skip for now',
              style: TextStyle(color: AppTheme.textSecondary, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}
