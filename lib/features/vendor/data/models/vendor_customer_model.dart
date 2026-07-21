import '../../domain/entities/vendor_customer_entity.dart';

/// Parses a row from the `get_vendor_customers` RPC.
///
/// The RPC returns FLAT fields (not a nested `profiles` object), joining
/// `customers` → `profiles` server-side. Keys: `profile_id`, `full_name`,
/// `phone`, `email`, `pin`, `total_orders`, `address`, `created_at`.
class VendorCustomerModel extends VendorCustomerEntity {
  const VendorCustomerModel({
    required super.profileId,
    required super.fullName,
    required super.phone,
    super.email,
    super.pin,
    super.totalOrders,
    super.address,
    required super.createdAt,
  });

  factory VendorCustomerModel.fromJson(Map<String, dynamic> json) {
    return VendorCustomerModel(
      profileId: json['profile_id'] as String,
      fullName: (json['full_name'] as String?)?.trim().isNotEmpty == true
          ? json['full_name'] as String
          : 'Customer',
      phone: json['phone'] as String? ?? '',
      email: json['email'] as String?,
      pin: json['pin'] as String?,
      totalOrders: (json['total_orders'] as num?)?.toInt() ?? 0,
      address: json['address'] as String?,
      createdAt: DateTime.tryParse(json['created_at'] as String? ?? '') ??
          DateTime.now(),
    );
  }
}
