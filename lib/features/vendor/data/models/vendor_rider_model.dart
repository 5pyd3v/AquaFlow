import '../../domain/entities/vendor_rider_entity.dart';

class VendorRiderModel extends VendorRiderEntity {
  const VendorRiderModel({
    required super.id,
    required super.profileId,
    required super.fullName,
    required super.phone,
    required super.status,
    required super.rating,
    required super.totalDeliveries,
    super.vehicleType,
    super.isApproved,
  });

  factory VendorRiderModel.fromJson(Map<String, dynamic> json) {
    final profile = json['profiles'] as Map<String, dynamic>?;
    return VendorRiderModel(
      id: json['id'] as String,
      profileId: json['profile_id'] as String,
      fullName: profile?['full_name'] as String? ?? 'Rider',
      phone: profile?['phone'] as String? ?? '',
      status: RiderStatus.fromDbValue(json['status'] as String? ?? 'offline'),
      rating: (json['rating'] as num?)?.toDouble() ?? 5.0,
      totalDeliveries: (json['total_deliveries'] as num?)?.toInt() ?? 0,
      vehicleType: json['vehicle_type'] as String?,
      isApproved: profile?['is_active'] as bool? ?? true,
    );
  }
}
