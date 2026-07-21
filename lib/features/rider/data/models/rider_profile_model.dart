import '../../domain/entities/rider_profile_entity.dart';

class RiderProfileModel extends RiderProfileEntity {
  const RiderProfileModel({
    required super.id,
    required super.profileId,
    super.vendorId,
    super.vendorName,
    super.vehicleType,
    super.vehiclePlate,
    required super.status,
    required super.rating,
    required super.totalDeliveries,
    required super.isOnShift,
  });

  factory RiderProfileModel.fromJson(Map<String, dynamic> json) {
    final vendor = json['vendors'] as Map<String, dynamic>?;
    return RiderProfileModel(
      id: json['id'] as String,
      profileId: json['profile_id'] as String,
      vendorId: json['vendor_id'] as String?,
      vendorName: vendor?['business_name'] as String?,
      vehicleType: json['vehicle_type'] as String?,
      vehiclePlate: json['vehicle_plate'] as String?,
      status: RiderShiftStatus.fromDbValue(json['status'] as String? ?? 'offline'),
      rating: (json['rating'] as num?)?.toDouble() ?? 5.0,
      totalDeliveries: (json['total_deliveries'] as num?)?.toInt() ?? 0,
      isOnShift: json['is_on_shift'] as bool? ?? false,
    );
  }
}
