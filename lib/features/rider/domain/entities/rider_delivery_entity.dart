import 'package:equatable/equatable.dart';
import '../../../../core/constants/order_status.dart';
import '../../../orders/domain/entities/order_entity.dart';

/// What the rider needs to actually execute a delivery — customer
/// contact + coordinates for navigation, vendor pickup info, order
/// contents, and status. Deliberately does NOT carry the OTP itself;
/// completion goes through `verify_delivery_otp`, which checks the
/// code server-side and never exposes it to the rider's client.
class RiderDeliveryEntity extends Equatable {
  final String id;
  final String orderNumber;
  final String vendorId;
  final String vendorName;
  final String? vendorAddress;
  final double? vendorLat;
  final double? vendorLng;
  final String? customerProfileId;
  final String customerName;
  final String customerPhone;
  final String deliveryAddress;
  final double deliveryLat;
  final double deliveryLng;
  final OrderStatus status;
  final bool isEmergency;
  final double totalAmount;
  final String paymentMethod;
  final DateTime createdAt;
  final List<OrderItemEntity> items;

  const RiderDeliveryEntity({
    required this.id,
    required this.orderNumber,
    required this.vendorId,
    required this.vendorName,
    this.vendorAddress,
    this.vendorLat,
    this.vendorLng,
    this.customerProfileId,
    required this.customerName,
    required this.customerPhone,
    required this.deliveryAddress,
    required this.deliveryLat,
    required this.deliveryLng,
    required this.status,
    required this.isEmergency,
    required this.totalAmount,
    required this.paymentMethod,
    required this.createdAt,
    this.items = const [],
  });

  bool get isCodPayment => paymentMethod == 'cod';

  @override
  List<Object?> get props => [
        id,
        orderNumber,
        vendorId,
        vendorName,
        vendorAddress,
        vendorLat,
        vendorLng,
        customerProfileId,
        customerName,
        customerPhone,
        deliveryAddress,
        deliveryLat,
        deliveryLng,
        status,
        isEmergency,
        totalAmount,
        paymentMethod,
        createdAt,
        items,
      ];
}
