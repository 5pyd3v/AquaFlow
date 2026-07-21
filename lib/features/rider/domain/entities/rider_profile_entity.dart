import 'package:equatable/equatable.dart';

enum RiderShiftStatus {
  offline,
  available,
  onDelivery,
  suspended;

  String get dbValue => switch (this) {
        RiderShiftStatus.offline => 'offline',
        RiderShiftStatus.available => 'available',
        RiderShiftStatus.onDelivery => 'on_delivery',
        RiderShiftStatus.suspended => 'suspended',
      };

  String get label => switch (this) {
        RiderShiftStatus.offline => 'Offline',
        RiderShiftStatus.available => 'Available',
        RiderShiftStatus.onDelivery => 'On Delivery',
        RiderShiftStatus.suspended => 'Suspended',
      };

  static RiderShiftStatus fromDbValue(String value) {
    return RiderShiftStatus.values.firstWhere((s) => s.dbValue == value, orElse: () => RiderShiftStatus.offline);
  }
}

class RiderProfileEntity extends Equatable {
  final String id;
  final String profileId;
  final String? vendorId;
  final String? vendorName;
  final String? vehicleType;
  final String? vehiclePlate;
  final RiderShiftStatus status;
  final double rating;
  final int totalDeliveries;
  final bool isOnShift;

  const RiderProfileEntity({
    required this.id,
    required this.profileId,
    this.vendorId,
    this.vendorName,
    this.vehicleType,
    this.vehiclePlate,
    required this.status,
    required this.rating,
    required this.totalDeliveries,
    required this.isOnShift,
  });

  bool get isLinkedToVendor => vendorId != null;

  @override
  List<Object?> get props => [
        id,
        profileId,
        vendorId,
        vendorName,
        vehicleType,
        vehiclePlate,
        status,
        rating,
        totalDeliveries,
        isOnShift,
      ];
}
