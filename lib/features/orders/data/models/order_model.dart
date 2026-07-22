import '../../../../core/constants/order_status.dart';
import '../../domain/entities/order_entity.dart';

class OrderItemModel extends OrderItemEntity {
  const OrderItemModel({
    required super.id,
    required super.productId,
    required super.productName,
    super.productImageUrl,
    required super.quantity,
    required super.unitPrice,
    required super.unitDeposit,
  });

  factory OrderItemModel.fromJson(Map<String, dynamic> json) {
    final product = json['products'] as Map<String, dynamic>?;
    return OrderItemModel(
      id: json['id'] as String,
      productId: json['product_id'] as String,
      productName: product?['name'] as String? ?? 'Product',
      productImageUrl: product?['image_url'] as String?,
      quantity: (json['quantity'] as num).toInt(),
      unitPrice: (json['unit_price'] as num).toDouble(),
      unitDeposit: (json['unit_deposit'] as num?)?.toDouble() ?? 0,
    );
  }
}

/// Maps a row from:
/// ```
/// orders.select('*, vendors(business_name), riders(profile_id, profiles(full_name, phone)), addresses(full_address), order_items(*, products(name, image_url)))
/// ```
class OrderModel extends OrderEntity {
  const OrderModel({
    required super.id,
    required super.orderNumber,
    required super.vendorId,
    required super.vendorName,
    super.riderId,
    super.riderName,
    super.riderPhone,
    super.deliveryCode,
    required super.status,
    required super.deliveryAddress,
    required super.isEmergency,
    required super.subtotal,
    required super.depositTotal,
    required super.discountAmount,
    required super.deliveryFee,
    required super.totalAmount,
    required super.paymentMethod,
    required super.paymentStatus,
    super.amountPaid,
    super.outstandingAmount,
    super.creditApplied,
    required super.createdAt,
    super.deliveredAt,
    super.items,
  });

  factory OrderModel.fromJson(Map<String, dynamic> json) {
    final vendor = json['vendors'] as Map<String, dynamic>?;
    final rider = json['riders'] as Map<String, dynamic>?;
    final riderProfile = rider?['profiles'] as Map<String, dynamic>?;
    final address = json['addresses'] as Map<String, dynamic>?;
    final itemRows = json['order_items'] as List? ?? [];

    return OrderModel(
      id: json['id'] as String,
      orderNumber: json['order_number'] as String? ?? '',
      vendorId: json['vendor_id'] as String? ?? '',
      vendorName: vendor?['business_name'] as String? ?? 'Vendor',
      riderId: json['rider_id'] as String?,
      riderName: riderProfile?['full_name'] as String?,
      riderPhone: riderProfile?['phone'] as String?,
      deliveryCode: json['rider_otp'] as String?,
      status: OrderStatus.fromDbValue(json['status'] as String? ?? 'pending'),
      deliveryAddress: address?['full_address'] as String? ?? '',
      isEmergency: json['is_emergency'] as bool? ?? false,
      subtotal: (json['subtotal'] as num?)?.toDouble() ?? 0,
      depositTotal: (json['deposit_total'] as num?)?.toDouble() ?? 0,
      discountAmount: (json['discount_amount'] as num?)?.toDouble() ?? 0,
      deliveryFee: (json['delivery_fee'] as num?)?.toDouble() ?? 0,
      totalAmount: (json['total_amount'] as num?)?.toDouble() ?? 0,
      paymentMethod: json['payment_method'] as String? ?? 'cod',
      paymentStatus: json['payment_status'] as String? ?? 'pending',
      amountPaid: (json['amount_paid'] as num?)?.round() ?? 0,
      outstandingAmount: (json['outstanding_amount'] as num?)?.round() ?? 0,
      creditApplied: (json['credit_applied'] as num?)?.round() ?? 0,
      createdAt: DateTime.tryParse(json['created_at']?.toString() ?? '') ?? DateTime.now(),
      deliveredAt: json['delivered_at'] != null ? DateTime.tryParse(json['delivered_at'].toString()) : null,
      items: itemRows.map((row) => OrderItemModel.fromJson(row as Map<String, dynamic>)).toList(),
    );
  }
}
