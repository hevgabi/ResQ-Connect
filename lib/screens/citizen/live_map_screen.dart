import 'dart:async';
import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../../widgets/app_bottom_nav.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../models/evac_center_model.dart';
import '../../models/sos_request_model.dart';
import '../../services/location_service.dart';
import '../../widgets/app_bottom_nav.dart';
import '../../services/storage_service.dart';
// Idinagdag na import para sa hamburger menu function at role
import '../settings/hamburger_menu_screen.dart'; // i-adjust path depende sa location

// ─── Constants ────────────────────────────────────────────────────────────────

const _primaryBlue = Color(0xFF0D47A1);
const _dangerRed = Color(0xFFD7263D);
const _successGreen = Color(0xFF1FAA59);
const _cardWhite = Color(0xFFFFFFFF);
const _textSecondary = Color(0xFF546E7A);
const _background = Color(0xFFF5F7FA);

// Default center: Metro Manila
const _defaultCenter = LatLng(14.5995, 120.9842);

// ─── Live Map Screen ──────────────────────────────────────────────────────────

class LiveMapScreen extends StatefulWidget {
  const LiveMapScreen({super.key});

  @override
  State<LiveMapScreen> createState() => _LiveMapScreenState();
}

class _LiveMapScreenState extends State<LiveMapScreen> {
  // ── Map controller ────────────────────────────────────────────────────────
  Completer<GoogleMapController> _mapCompleter = Completer();
  GoogleMapController? _mapController;

  // ── State ─────────────────────────────────────────────────────────────────
  LatLng? _userPosition;
  bool _isLocating = true;
  bool _isLoadingMarkers = false;
  String? _error;

  // ── Marker sets ───────────────────────────────────────────────────────────
  final Set<Marker> _markers = {};
  final Set<Circle> _circles = {};

  // ── Data cache (for bottom sheets) ────────────────────────────────────────
  final Map<String, SosRequestModel> _sosMap = {};
  final Map<String, EvacCenterModel> _evacMap = {};

  // ── Custom BitmapDescriptors ──────────────────────────────────────────────
  BitmapDescriptor? _rescuerIcon;
  BitmapDescriptor? _evacIcon;

  @override
  void initState() {
    super.initState();
    _initMap();
  }

  @override
  void dispose() {
    // FIX: Bawal i-dispose nang direkta ang GoogleMapController sa Flutter;
    // Kusang nililinis ng plugin ang native channels nito. Ang pagtawag nito ay magdudulot ng crash.
    super.dispose();
  }

  // ─── Initialization ───────────────────────────────────────────────────────

  Future<void> _initMap() async {
    await _loadCustomIcons();
    await _getUserLocation();
    await _loadAllMarkers();
  }

  Future<void> _loadCustomIcons() async {
    _rescuerIcon =
        await BitmapDescriptor.fromAssetImage(
          const ImageConfiguration(size: Size(36, 36)),
          'assets/icons/rescuer_marker.png',
        ).catchError(
          (_) =>
              BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueBlue),
        );

    _evacIcon =
        await BitmapDescriptor.fromAssetImage(
          const ImageConfiguration(size: Size(36, 36)),
          'assets/icons/evac_marker.png',
        ).catchError(
          (_) =>
              BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
        );
  }

  Future<void> _getUserLocation() async {
    if (!mounted) return;
    setState(() {
      _isLocating = true;
      _error = null;
    });

    try {
      final position = await LocationService.instance.getCurrentPosition();
      if (!mounted) return;

      // SOLUSYON: Maglagay ng null check bago gamitin ang position data
      if (position == null) {
        setState(() {
          _isLocating = false;
          _userPosition = _defaultCenter;
          _error =
              'Could not get your location. Please check your GPS permissions.';
        });
        return;
      }

      setState(() {
        _userPosition = LatLng(position.latitude, position.longitude);
        _isLocating = false;
      });

      _updateUserCircle();
      _animateTo(_userPosition!);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLocating = false;
        _userPosition = _defaultCenter;
        _error = 'Could not get your location. Showing default map.';
      });
    }
  }

  void _updateUserCircle() {
    if (_userPosition == null) return;
    setState(() {
      _circles
        ..removeWhere((c) => c.circleId.value == 'user_position')
        ..add(
          Circle(
            circleId: const CircleId('user_position'),
            center: _userPosition!,
            radius: 60,
            fillColor: _primaryBlue.withOpacity(0.25),
            strokeColor: _primaryBlue,
            strokeWidth: 2,
            zIndex: 10,
          ),
        );
    });
  }

  Future<void> _animateTo(LatLng position, {double zoom = 14.0}) async {
    try {
      final ctrl = await _mapCompleter.future;
      ctrl.animateCamera(CameraUpdate.newLatLngZoom(position, zoom));
    } catch (e) {
      debugPrint('Map animation error: $e');
    }
  }

  // ─── Marker Loading ───────────────────────────────────────────────────────

  Future<void> _loadAllMarkers() async {
    if (!mounted) return;
    setState(() => _isLoadingMarkers = true);

    try {
      await Future.wait([
        _loadSosMarkers(),
        _loadEvacMarkers(),
        _loadRescuerMarkers(),
      ]);
    } catch (e) {
      if (mounted) {
        setState(
          () => _error = 'Failed to load map data. Tap refresh to try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _isLoadingMarkers = false);
    }
  }

  Future<void> _loadSosMarkers() async {
    final snapshot = await FirebaseFirestore.instance
        .collection('sos_requests')
        .where('status', isEqualTo: 'open')
        .get();

    _sosMap.clear();
    final newMarkers = <Marker>{};

    for (final doc in snapshot.docs) {
      final sos = SosRequestModel.fromFirestore(doc);
      _sosMap[doc.id] = sos;

      // FIX: Ang latitude at longitude sa model mo ay non-nullable doubles (laging may value na 0.0 default).
      // Kaya tinanggal ang null validation check dito.
      newMarkers.add(
        Marker(
          markerId: MarkerId('sos_${doc.id}'),
          position: LatLng(sos.latitude, sos.longitude),
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
          infoWindow: InfoWindow(
            title: '🆘 SOS Request',
            // FIX: Ginamit ang description o 'Emergency' dahil walang property na emergencyType ang model mo.
            snippet: sos.description ?? 'Emergency',
          ),
          onTap: () => _showSosBottomSheet(sos),
          zIndex: 5,
        ),
      );
    }

    if (mounted) {
      setState(() {
        _markers.removeWhere((m) => m.markerId.value.startsWith('sos_'));
        _markers.addAll(newMarkers);
      });
    }
  }

  Future<void> _loadEvacMarkers() async {
    final snapshot = await FirebaseFirestore.instance
        .collection('evacuation_centers')
        .get();

    _evacMap.clear();
    final newMarkers = <Marker>{};

    for (final doc in snapshot.docs) {
      final evac = EvacCenterModel.fromFirestore(doc);
      _evacMap[doc.id] = evac;

      if (evac.latitude == null || evac.longitude == null) continue;

      newMarkers.add(
        Marker(
          markerId: MarkerId('evac_${doc.id}'),
          position: LatLng(evac.latitude!, evac.longitude!),
          icon:
              _evacIcon ??
              BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
          infoWindow: InfoWindow(
            title: '🏥 ${evac.name}',
            snippet: evac.address,
          ),
          onTap: () => _showEvacBottomSheet(evac),
          zIndex: 3,
        ),
      );
    }

    if (mounted) {
      setState(() {
        _markers.removeWhere((m) => m.markerId.value.startsWith('evac_'));
        _markers.addAll(newMarkers);
      });
    }
  }

  Future<void> _loadRescuerMarkers() async {
    final snapshot = await FirebaseFirestore.instance
        .collection('rescuers')
        .where('is_on_duty', isEqualTo: true)
        .get();

    final newMarkers = <Marker>{};

    for (final doc in snapshot.docs) {
      final data = doc.data();
      final lat = (data['current_lat'] as num?)?.toDouble();
      final lng = (data['current_lng'] as num?)?.toDouble();
      if (lat == null || lng == null) continue;

      final name = data['display_name'] as String? ?? 'Rescuer';
      final agency = data['agency_name'] as String? ?? '';

      newMarkers.add(
        Marker(
          markerId: MarkerId('rescuer_${doc.id}'),
          position: LatLng(lat, lng),
          icon:
              _rescuerIcon ??
              BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
          infoWindow: InfoWindow(
            title: '🚑 $name',
            snippet: agency.isNotEmpty ? agency : 'On Duty',
          ),
          zIndex: 4,
        ),
      );
    }

    if (mounted) {
      setState(() {
        _markers.removeWhere((m) => m.markerId.value.startsWith('rescuer_'));
        _markers.addAll(newMarkers);
      });
    }
  }

  // ─── Bottom Sheets ────────────────────────────────────────────────────────

  void _showSosBottomSheet(SosRequestModel sos) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _SosBottomSheet(sos: sos),
    );
  }

  void _showEvacBottomSheet(EvacCenterModel evac) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _EvacBottomSheet(evac: evac),
    );
  }

  // ─── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final center = _userPosition ?? _defaultCenter;

    return Scaffold(
      backgroundColor: _background,
      body: Stack(
        children: [
          // ── Map ────────────────────────────────────────────────────────
          GoogleMap(
            initialCameraPosition: CameraPosition(target: center, zoom: 13.5),
            markers: _markers,
            circles: _circles,
            myLocationButtonEnabled: false,
            zoomControlsEnabled: false,
            mapToolbarEnabled: false,
            compassEnabled: true,
            onMapCreated: (ctrl) {
              if (_mapCompleter.isCompleted) {
                _mapCompleter = Completer();
              }
              _mapCompleter.complete(ctrl);
              _mapController = ctrl;
            },
          ),

          // ── Top Header ─────────────────────────────────────────────────
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: _MapHeader(isLoading: _isLocating || _isLoadingMarkers),
          ),

          // ── Error Banner ───────────────────────────────────────────────
          if (_error != null)
            Positioned(
              top: 88,
              left: 16,
              right: 16,
              child: _ErrorBanner(
                message: _error!,
                onDismiss: () => setState(() => _error = null),
              ),
            ),

          // ── Legend ─────────────────────────────────────────────────────
          const Positioned(bottom: 100, left: 16, child: _MapLegend()),

          // ── FABs ───────────────────────────────────────────────────────
          Positioned(
            bottom: 100,
            right: 16,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Refresh markers
                FloatingActionButton.small(
                  heroTag: 'refresh',
                  onPressed: _isLoadingMarkers ? null : _loadAllMarkers,
                  backgroundColor: _cardWhite,
                  foregroundColor: _primaryBlue,
                  elevation: 4,
                  child: _isLoadingMarkers
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: _primaryBlue,
                          ),
                        )
                      : const Icon(Icons.refresh_rounded, size: 20),
                ),
                const SizedBox(height: 10),
                // My location
                FloatingActionButton.small(
                  heroTag: 'my_location',
                  onPressed: _isLocating
                      ? null
                      : () {
                          if (_userPosition != null) {
                            _animateTo(_userPosition!, zoom: 15);
                          } else {
                            _getUserLocation();
                          }
                        },
                  backgroundColor: _primaryBlue,
                  foregroundColor: Colors.white,
                  elevation: 4,
                  child: _isLocating
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.my_location_rounded, size: 20),
                ),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: const AppBottomNav(currentIndex: 1),
    );
  }
}

// ─── Map Header ───────────────────────────────────────────────────────────────

class _MapHeader extends StatelessWidget {
  final bool isLoading;
  const _MapHeader({required this.isLoading});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: _primaryBlue,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.18),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      padding: EdgeInsets.only(
        top: MediaQuery.of(context).padding.top + 10,
        bottom: 14,
        left: 8, // Ginawa kong 8 para magkasya yung menu button sa gilid
        right: 20,
      ),
      child: Row(
        children: [
          // Dito inilagay ang IconButton para magamit ang HamburgerMenu ng Citizen
          IconButton(
            icon: const Icon(Icons.menu, color: Colors.white),
            tooltip: 'Menu',
            onPressed: () =>
                showHamburgerMenu(context, role: HamburgerRole.citizen),
          ),
          const SizedBox(width: 4),
          const Icon(Icons.map_rounded, color: Colors.white, size: 22),
          const SizedBox(width: 10),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Live Disaster Map',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.2,
                  ),
                ),
                Text(
                  'Philippines — Real-time view',
                  style: TextStyle(color: Colors.white70, fontSize: 12),
                ),
              ],
            ),
          ),
          if (isLoading)
            const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white,
              ),
            ),
        ],
      ),
    );
  }
}

// ─── Map Legend ───────────────────────────────────────────────────────────────

class _MapLegend extends StatelessWidget {
  const _MapLegend();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: _cardWhite.withOpacity(0.94),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.10),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          _LegendItem(color: _dangerRed, label: 'SOS Request'),
          SizedBox(height: 6),
          _LegendItem(color: _successGreen, label: 'Evacuation Center'),
          SizedBox(height: 6),
          _LegendItem(color: Color(0xFF1565C0), label: 'Rescuer On Duty'),
          SizedBox(height: 6),
          _LegendItem(
            color: _primaryBlue,
            label: 'Your Position',
            isCircle: true,
          ),
        ],
      ),
    );
  }
}

class _LegendItem extends StatelessWidget {
  final Color color;
  final String label;
  final bool isCircle;

  const _LegendItem({
    required this.color,
    required this.label,
    this.isCircle = false,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: color,
            shape: isCircle ? BoxShape.circle : BoxShape.rectangle,
            borderRadius: isCircle ? null : BorderRadius.circular(3),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            color: Color(0xFF37474F),
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}

// ─── Error Banner ─────────────────────────────────────────────────────────────

class _ErrorBanner extends StatelessWidget {
  final String message;
  final VoidCallback onDismiss;

  const _ErrorBanner({required this.message, required this.onDismiss});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF3E0),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFFF6B00).withOpacity(0.4)),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.07), blurRadius: 6),
        ],
      ),
      child: Row(
        children: [
          const Icon(
            Icons.warning_amber_rounded,
            color: Color(0xFFFF6B00),
            size: 18,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(fontSize: 13, color: Color(0xFF37474F)),
            ),
          ),
          GestureDetector(
            onTap: onDismiss,
            child: const Icon(Icons.close, size: 16, color: _textSecondary),
          ),
        ],
      ),
    );
  }
}

// ─── SOS Bottom Sheet ─────────────────────────────────────────────────────────

class _SosBottomSheet extends StatelessWidget {
  final SosRequestModel sos;
  const _SosBottomSheet({required this.sos});

  String _timeElapsed(DateTime? createdAt) {
    if (createdAt == null) return 'Unknown';
    final diff = DateTime.now().difference(createdAt);
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }

  @override
  Widget build(BuildContext context) {
    return _BottomSheetContainer(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: _dangerRed.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.sos_rounded,
                  color: _dangerRed,
                  size: 26,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'SOS Request',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: _dangerRed,
                      ),
                    ),
                    Text(
                      // FIX: Ginamit ang citizenName o fallback placeholder string
                      sos.citizenName.isNotEmpty
                          ? sos.citizenName
                          : 'Emergency Call',
                      style: const TextStyle(
                        fontSize: 13,
                        color: _textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              _StatusChip(label: sos.status.toUpperCase(), color: _dangerRed),
            ],
          ),

          const SizedBox(height: 20),
          const Divider(color: Color(0xFFECEFF1)),
          const SizedBox(height: 16),

          // Details
          _DetailRow(
            icon: Icons.access_time_rounded,
            label: 'Time',
            value: _timeElapsed(sos.createdAt),
          ),
          const SizedBox(height: 12),
          _DetailRow(
            icon: Icons.location_on_outlined,
            label: 'Coordinates',
            // FIX: Inalis ang null checks dahil laging valid double ang coordinates sa model mo
            value:
                '${sos.latitude.toStringAsFixed(5)}, ${sos.longitude.toStringAsFixed(5)}',
          ),
          if (sos.description != null && sos.description!.isNotEmpty) ...[
            const SizedBox(height: 12),
            _DetailRow(
              icon: Icons.description_outlined,
              label: 'Details',
              value: sos.description!,
            ),
          ],
          // FIX: Inalis ang error tungkol sa numberOfPeople dahil na-update na ito base sa model definition
          if (sos.numberOfPeople != null) ...[
            const SizedBox(height: 12),
            _DetailRow(
              icon: Icons.group_outlined,
              label: 'People',
              value: '${sos.numberOfPeople} person(s) affected',
            ),
          ],

          const SizedBox(height: 20),
        ],
      ),
    );
  }
}

// ─── Evac Center Bottom Sheet ─────────────────────────────────────────────────

class _EvacBottomSheet extends StatelessWidget {
  final EvacCenterModel evac;
  const _EvacBottomSheet({required this.evac});

  @override
  Widget build(BuildContext context) {
    final available = (evac.capacity ?? 0) - (evac.currentOccupancy ?? 0);
    final isFull = available <= 0;

    return _BottomSheetContainer(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: _successGreen.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.local_hospital_rounded,
                  color: _successGreen,
                  size: 26,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      evac.name ?? 'Evacuation Center',
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF1A2B3C),
                      ),
                    ),
                    const Text(
                      'Evacuation Center',
                      style: TextStyle(fontSize: 12, color: _textSecondary),
                    ),
                  ],
                ),
              ),
              _StatusChip(
                label: isFull ? 'FULL' : 'OPEN',
                color: isFull ? _dangerRed : _successGreen,
              ),
            ],
          ),

          const SizedBox(height: 20),
          const Divider(color: Color(0xFFECEFF1)),
          const SizedBox(height: 16),

          // Details
          if (evac.address != null) ...[
            _DetailRow(
              icon: Icons.location_on_outlined,
              label: 'Address',
              value: evac.address!,
            ),
            const SizedBox(height: 12),
          ],
          _DetailRow(
            icon: Icons.people_outline_rounded,
            label: 'Occupancy',
            value:
                '${evac.currentOccupancy ?? 0} / ${evac.capacity ?? 0} occupied',
          ),
          const SizedBox(height: 12),
          _DetailRow(
            icon: Icons.chair_outlined,
            label: 'Available Slots',
            value: isFull ? 'No slots available' : '$available slot(s) open',
            valueColor: isFull ? _dangerRed : _successGreen,
          ),
          if (evac.contactNumber != null) ...[
            const SizedBox(height: 12),
            _DetailRow(
              icon: Icons.phone_outlined,
              label: 'Contact',
              value: evac.contactNumber!,
            ),
          ],

          // Capacity bar
          const SizedBox(height: 16),
          _CapacityBar(
            current: evac.currentOccupancy ?? 0,
            max: evac.capacity ?? 1,
          ),

          const SizedBox(height: 20),
        ],
      ),
    );
  }
}

// ─── Shared Bottom Sheet Container ───────────────────────────────────────────

class _BottomSheetContainer extends StatelessWidget {
  final Widget child;
  const _BottomSheetContainer({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      decoration: const BoxDecoration(
        color: _cardWhite,
        borderRadius: BorderRadius.all(Radius.circular(20)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Drag handle
          Center(
            child: Container(
              margin: const EdgeInsets.only(top: 12, bottom: 4),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: const Color(0xFFCFD8DC),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
            child: child,
          ),
        ],
      ),
    );
  }
}

// ─── Shared Detail Row ────────────────────────────────────────────────────────

class _DetailRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color? valueColor;

  const _DetailRow({
    required this.icon,
    required this.label,
    required this.value,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: _textSecondary),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(
                  fontSize: 11,
                  color: _textSecondary,
                  fontWeight: FontWeight.w500,
                  letterSpacing: 0.3,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                style: TextStyle(
                  fontSize: 14,
                  color: valueColor ?? const Color(0xFF263238),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ─── Status Chip ──────────────────────────────────────────────────────────────

class _StatusChip extends StatelessWidget {
  final String label;
  final Color color;

  const _StatusChip({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          color: color,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

// ─── Capacity Bar ─────────────────────────────────────────────────────────────

class _CapacityBar extends StatelessWidget {
  final int current;
  final int max;

  const _CapacityBar({required this.current, required this.max});

  @override
  Widget build(BuildContext context) {
    final ratio = max > 0 ? (current / max).clamp(0.0, 1.0) : 0.0;
    final barColor = ratio >= 1.0
        ? _dangerRed
        : ratio >= 0.75
        ? const Color(0xFFFF6B00)
        : _successGreen;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Capacity',
              style: TextStyle(
                fontSize: 11,
                color: _textSecondary,
                fontWeight: FontWeight.w500,
              ),
            ),
            Text(
              '${(ratio * 100).toInt()}% full',
              style: TextStyle(
                fontSize: 11,
                color: barColor,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: ratio,
            minHeight: 8,
            backgroundColor: const Color(0xFFECEFF1),
            valueColor: AlwaysStoppedAnimation<Color>(barColor),
          ),
        ),
      ],
    );
  }
}
