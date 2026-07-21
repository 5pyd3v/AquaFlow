import '../../domain/entities/vendor_entity.dart';

class VendorModel extends VendorEntity {
  const VendorModel({
    required super.id,
    required super.profileId,
    super.businessName,
    required super.status,
    required super.rating,
    required super.totalOrders,
    super.address,
    super.latitude,
    super.longitude,
    required super.deliveryRadiusKm,
  });

  factory VendorModel.fromJson(Map<String, dynamic> json) {
    return VendorModel(
      id: json['id'] as String,
      profileId: json['profile_id'] as String,
      businessName: json['business_name'] as String?,
      status: VendorStatus.fromDbValue(json['status'] as String? ?? 'pending'),
      rating: (json['rating'] as num?)?.toDouble() ?? 5.0,
      totalOrders: (json['total_orders'] as num?)?.toInt() ?? 0,
      address: json['address'] as String?,
      latitude: (json['lat'] as num?)?.toDouble(),
      longitude: (json['lng'] as num?)?.toDouble(),
      deliveryRadiusKm: (json['delivery_radius_km'] as num?)?.toDouble() ?? 8.0,
    );
  }
}
