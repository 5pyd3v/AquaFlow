import '../../../../core/constants/order_status.dart';
import '../../../orders/data/models/order_model.dart';
import '../../domain/entities/rider_delivery_entity.dart';

/// Maps a row from:
/// ```
/// orders.select('*, vendors(business_name, address, lat, lng),
///   profiles!orders_customer_profile_id_fkey(full_name, phone),
///   addresses(full_address, lat, lng), order_items(*, products(name, image_url)))
/// ```
class RiderDeliveryModel extends RiderDeliveryEntity {
  const RiderDeliveryModel({
    required super.id,
    required super.orderNumber,
    required super.vendorId,
    required super.vendorName,
    super.vendorAddress,
    super.vendorLat,
    super.vendorLng,
    super.customerProfileId,
    required super.customerName,
    required super.customerPhone,
    required super.deliveryAddress,
    required super.deliveryLat,
    required super.deliveryLng,
    required super.status,
    required super.isEmergency,
    required super.totalAmount,
    required super.paymentMethod,
    required super.createdAt,
    super.items,
  });

  factory RiderDeliveryModel.fromJson(Map<String, dynamic> json) {
    final vendor = json['vendors'] as Map<String, dynamic>?;
    final customer = json['profiles'] as Map<String, dynamic>?;
    final address = json['addresses'] as Map<String, dynamic>?;
    final itemRows = json['order_items'] as List? ?? [];

    return RiderDeliveryModel(
      id: json['id'] as String,
      orderNumber: json['order_number'] as String? ?? '',
      vendorId: json['vendor_id'] as String? ?? '',
      vendorName: vendor?['business_name'] as String? ?? 'Vendor',
      vendorAddress: vendor?['address'] as String?,
      vendorLat: (vendor?['lat'] as num?)?.toDouble(),
      vendorLng: (vendor?['lng'] as num?)?.toDouble(),
      customerProfileId: json['customer_profile_id'] as String?,
      customerName: customer?['full_name'] as String? ?? 'Customer',
      customerPhone: customer?['phone'] as String? ?? '',
      deliveryAddress: address?['full_address'] as String? ?? '',
      deliveryLat: (address?['lat'] as num?)?.toDouble() ?? 0,
      deliveryLng: (address?['lng'] as num?)?.toDouble() ?? 0,
      status: OrderStatus.fromDbValue(json['status'] as String? ?? 'assigned'),
      isEmergency: json['is_emergency'] as bool? ?? false,
      totalAmount: (json['total_amount'] as num?)?.toDouble() ?? 0,
      paymentMethod: json['payment_method'] as String? ?? 'cod',
      createdAt: DateTime.tryParse(json['created_at']?.toString() ?? '') ?? DateTime.now(),
      items: itemRows.map((row) => OrderItemModel.fromJson(row as Map<String, dynamic>)).toList(),
    );
  }
}
