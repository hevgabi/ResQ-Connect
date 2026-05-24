import 'package:cloud_firestore/cloud_firestore.dart';

class EvacCenterModel {
  final String id;
  final String name;
  final String address;
  final double latitude;
  final double longitude;
  final int capacity;
  final int currentOccupancy;

  /// Status of the evac center.
  /// Values: 'open' | 'full' | 'closed'
  final String status;

  final String? contactNumber;
  final List<String> facilities; // e.g. ['water', 'food', 'medical']
  final DateTime? updatedAt;

  EvacCenterModel({
    required this.id,
    required this.name,
    required this.address,
    required this.latitude,
    required this.longitude,
    required this.capacity,
    required this.currentOccupancy,
    required this.status,
    this.contactNumber,
    this.facilities = const [],
    this.updatedAt,
  });

  // ─── Getters ──────────────────────────────────────────────────────────────

  /// Remaining slots (never negative)
  int get availableSlots => (capacity - currentOccupancy).clamp(0, capacity);

  /// Occupancy percentage 0.0 – 1.0
  double get occupancyRate =>
      capacity > 0 ? (currentOccupancy / capacity).clamp(0.0, 1.0) : 0.0;

  /// Backward-compatible getter — true only when status is 'open'.
  /// Kept so existing citizen map screens don't break immediately.
  bool get isOpen => status == 'open';

  // ─── Factory constructors ─────────────────────────────────────────────────

  factory EvacCenterModel.fromMap(Map<String, dynamic> data) {
    // Support old 'is_open' bool field for backward compatibility
    // while new documents use the 'status' string field.
    final rawStatus = data['status'] as String?;
    final String resolvedStatus;
    if (rawStatus != null && rawStatus.isNotEmpty) {
      resolvedStatus = rawStatus;
    } else {
      // Fallback: derive from old is_open bool
      final oldIsOpen = data['is_open'] ?? data['isOpen'] ?? false;
      resolvedStatus = (oldIsOpen as bool) ? 'open' : 'closed';
    }

    return EvacCenterModel(
      id: data['id'] ?? '',
      name: data['name'] ?? '',
      address: data['address'] ?? '',
      latitude: (data['latitude'] as num?)?.toDouble() ?? 0.0,
      longitude: (data['longitude'] as num?)?.toDouble() ?? 0.0,
      capacity: (data['capacity'] as num?)?.toInt() ?? 0,
      currentOccupancy: (data['current_occupancy'] as num?)?.toInt() ??
          (data['currentOccupancy'] as num?)?.toInt() ?? 0,
      status: resolvedStatus,
      contactNumber: data['contact_number'] ?? data['contactNumber'],
      facilities: List<String>.from(data['facilities'] ?? []),
      updatedAt: data['updated_at'] is Timestamp
          ? (data['updated_at'] as Timestamp).toDate()
          : null,
    );
  }

  factory EvacCenterModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};

    // Support old 'is_open' bool field for backward compatibility
    final rawStatus = data['status'] as String?;
    final String resolvedStatus;
    if (rawStatus != null && rawStatus.isNotEmpty) {
      resolvedStatus = rawStatus;
    } else {
      final oldIsOpen = data['is_open'] ?? false;
      resolvedStatus = (oldIsOpen as bool) ? 'open' : 'closed';
    }

    return EvacCenterModel(
      id: doc.id,
      name: data['name'] ?? '',
      address: data['address'] ?? '',
      latitude: (data['latitude'] as num?)?.toDouble() ?? 0.0,
      longitude: (data['longitude'] as num?)?.toDouble() ?? 0.0,
      capacity: (data['capacity'] as num?)?.toInt() ?? 0,
      currentOccupancy: (data['current_occupancy'] as num?)?.toInt() ?? 0,
      status: resolvedStatus,
      contactNumber: data['contact_number'],
      facilities: List<String>.from(data['facilities'] ?? []),
      updatedAt: (data['updated_at'] as Timestamp?)?.toDate(),
    );
  }

  // ─── toMap ────────────────────────────────────────────────────────────────

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'address': address,
      'latitude': latitude,
      'longitude': longitude,
      'capacity': capacity,
      'current_occupancy': currentOccupancy,
      'status': status,
      // Keep is_open in sync so old citizen map screens still work
      // until they are updated to read 'status' directly.
      'is_open': isOpen,
      if (contactNumber != null) 'contact_number': contactNumber,
      'facilities': facilities,
      if (updatedAt != null) 'updated_at': Timestamp.fromDate(updatedAt!),
    };
  }

  // ─── copyWith ─────────────────────────────────────────────────────────────

  EvacCenterModel copyWith({
    String? id,
    String? name,
    String? address,
    double? latitude,
    double? longitude,
    int? capacity,
    int? currentOccupancy,
    String? status,
    String? contactNumber,
    List<String>? facilities,
    DateTime? updatedAt,
  }) {
    return EvacCenterModel(
      id: id ?? this.id,
      name: name ?? this.name,
      address: address ?? this.address,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      capacity: capacity ?? this.capacity,
      currentOccupancy: currentOccupancy ?? this.currentOccupancy,
      status: status ?? this.status,
      contactNumber: contactNumber ?? this.contactNumber,
      facilities: facilities ?? this.facilities,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}