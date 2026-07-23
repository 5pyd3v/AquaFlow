import 'package:equatable/equatable.dart';

import '../../../../core/constants/rider_status.dart';

export '../../../../core/constants/rider_status.dart' show RiderStatus;

class RiderProfileEntity extends Equatable {
  final String id;
  final String profileId;
  final String? vendorId;
  final String? vendorName;
  final String? vehicleType;
  final String? vehiclePlate;
  final RiderStatus status;
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
