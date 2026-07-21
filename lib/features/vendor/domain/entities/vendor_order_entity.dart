import 'package:equatable/equatable.dart';
import '../../../../core/constants/order_status.dart';
import '../../../orders/domain/entities/order_entity.dart';

/// Same shape as the customer-facing `OrderEntity` but carries
/// customer contact info instead of vendor info — what the vendor
/// actually needs to act on an order (accept/reject/assign rider).
class VendorOrderEntity extends Equatable {
  final String id;
  final String orderNumber;
  final String customerName;
  final String customerPhone;
  final String? riderId;
  final String? riderName;
  final OrderStatus status;
  final String deliveryAddress;
  final double deliveryLat;
  final double deliveryLng;
  final bool isEmergency;
  final double totalAmount;
  final String paymentMethod;
  final DateTime createdAt;
  final List<OrderItemEntity> items;

  const VendorOrderEntity({
    required this.id,
    required this.orderNumber,
    required this.customerName,
    required this.customerPhone,
    this.riderId,
    this.riderName,
    required this.status,
    required this.deliveryAddress,
    required this.deliveryLat,
    required this.deliveryLng,
    required this.isEmergency,
    required this.totalAmount,
    required this.paymentMethod,
    required this.createdAt,
    this.items = const [],
  });

  @override
  List<Object?> get props => [
        id,
        orderNumber,
        customerName,
        customerPhone,
        riderId,
        riderName,
        status,
        deliveryAddress,
        isEmergency,
        totalAmount,
        deliveryLat,
        deliveryLng,
        paymentMethod,
        createdAt,
        items,
      ];
}
