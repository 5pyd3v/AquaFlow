import '../../../../core/constants/order_status.dart';
import '../../../orders/data/models/order_model.dart';
import '../../domain/entities/vendor_order_entity.dart';

class VendorOrderModel extends VendorOrderEntity {
  const VendorOrderModel({
    required super.id,
    required super.orderNumber,
    required super.customerName,
    required super.customerPhone,
    super.riderId,
    super.riderName,
    required super.status,
    required super.deliveryAddress,
    required super.deliveryLat,
    required super.deliveryLng,
    required super.isEmergency,
    required super.totalAmount,
    required super.paymentMethod,
    required super.createdAt,
    super.items,
  });

  /// Maps a row from:
  /// ```
  /// orders.select('*, profiles!orders_customer_profile_id_fkey(full_name, phone),
  ///   riders(profiles(full_name)), addresses(full_address), order_items(*, products(name, image_url)))
  /// ```
  factory VendorOrderModel.fromJson(Map<String, dynamic> json) {
    final customer = json['profiles'] as Map<String, dynamic>?;
    final rider = json['riders'] as Map<String, dynamic>?;
    final riderProfile = rider?['profiles'] as Map<String, dynamic>?;
    final address = json['addresses'] as Map<String, dynamic>?;
    final itemRows = json['order_items'] as List? ?? [];

    return VendorOrderModel(
      id: json['id'] as String,
      orderNumber: json['order_number'] as String? ?? '',
      customerName: customer?['full_name'] as String? ?? 'Customer',
      customerPhone: customer?['phone'] as String? ?? '',
      riderId: json['rider_id'] as String?,
      riderName: riderProfile?['full_name'] as String?,
      status: OrderStatus.fromDbValue(json['status'] as String? ?? 'pending'),
      deliveryAddress: address?['full_address'] as String? ?? '',
      deliveryLat: (address?['lat'] as num?)?.toDouble() ?? 0,
      deliveryLng: (address?['lng'] as num?)?.toDouble() ?? 0,
      isEmergency: json['is_emergency'] as bool? ?? false,
      totalAmount: (json['total_amount'] as num?)?.toDouble() ?? 0,
      paymentMethod: json['payment_method'] as String? ?? 'cod',
      createdAt: DateTime.tryParse(json['created_at']?.toString() ?? '') ?? DateTime.now(),
      items: itemRows.map((row) => OrderItemModel.fromJson(row as Map<String, dynamic>)).toList(),
    );
  }
}
