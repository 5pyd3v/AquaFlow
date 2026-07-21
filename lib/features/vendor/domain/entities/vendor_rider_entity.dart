import 'package:equatable/equatable.dart';

enum RiderStatus {
  offline,
  available,
  onDelivery,
  suspended;

  String get dbValue => switch (this) {
        RiderStatus.offline => 'offline',
        RiderStatus.available => 'available',
        RiderStatus.onDelivery => 'on_delivery',
        RiderStatus.suspended => 'suspended',
      };

  String get label => switch (this) {
        RiderStatus.offline => 'Offline',
        RiderStatus.available => 'Available',
        RiderStatus.onDelivery => 'On Delivery',
        RiderStatus.suspended => 'Suspended',
      };

  static RiderStatus fromDbValue(String value) {
    return RiderStatus.values.firstWhere((s) => s.dbValue == value, orElse: () => RiderStatus.offline);
  }
}

class VendorRiderEntity extends Equatable {
  final String id;
  final String profileId;
  final String fullName;
  final String phone;
  final RiderStatus status;
  final double rating;
  final int totalDeliveries;
  final String? vehicleType;

  /// Whether the rider's account has been approved by this vendor.
  /// A freshly self-registered rider is inactive until approved, and
  /// shows up as a pending request in the vendor's rider list.
  final bool isApproved;

  const VendorRiderEntity({
    required this.id,
    required this.profileId,
    required this.fullName,
    required this.phone,
    required this.status,
    required this.rating,
    required this.totalDeliveries,
    this.vehicleType,
    this.isApproved = true,
  });

  @override
  List<Object?> get props =>
      [id, profileId, fullName, phone, status, rating, totalDeliveries, vehicleType, isApproved];
}
