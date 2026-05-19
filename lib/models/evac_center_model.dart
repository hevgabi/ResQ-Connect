import 'package:cloud_firestore/cloud_firestore.dart';

class EvacCenterModel {
  final String id;
  final String name;
  final String address;
  final double latitude;
  final double longitude;
  final int capacity;
  final int currentOccupancy;
  final bool isOpen;
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
    required this.isOpen,
    this.contactNumber,
    this.facilities = const [],
    this.updatedAt,
  });

  /// Remaining slots (never negative)
  int get availableSlots => (capacity - currentOccupancy).clamp(0, capacity);

  /// Occupancy percentage 0.0 – 1.0
  double get occupancyRate =>
      capacity > 0 ? (currentOccupancy / capacity).clamp(0.0, 1.0) : 0.0;

  factory EvacCenterModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return EvacCenterModel(
      id: doc.id,
      name: data['name'] ?? '',
      address: data['address'] ?? '',
      latitude: (data['latitude'] as num?)?.toDouble() ?? 0.0,
      longitude: (data['longitude'] as num?)?.toDouble() ?? 0.0,
      capacity: data['capacity'] ?? 0,
      currentOccupancy: data['current_occupancy'] ?? 0,
      isOpen: data['is_open'] ?? false,
      contactNumber: data['contact_number'],
      facilities: List<String>.from(data['facilities'] ?? []),
      updatedAt: (data['updated_at'] as Timestamp?)?.toDate(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'address': address,
      'latitude': latitude,
      'longitude': longitude,
      'capacity': capacity,
      'current_occupancy': currentOccupancy,
      'is_open': isOpen,
      if (contactNumber != null) 'contact_number': contactNumber,
      'facilities': facilities,
      if (updatedAt != null) 'updated_at': Timestamp.fromDate(updatedAt!),
    };
  }
}
